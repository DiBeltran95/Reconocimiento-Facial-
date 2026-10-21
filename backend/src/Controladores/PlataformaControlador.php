<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;

/**
 * Administración de la plataforma (solo el superadministrador).
 *
 * Los planes se cobran fuera de las apps (política de Google Play). Cada app
 * tiene su plan (empresa_planes): una empresa puede pagar Ventario y usar
 * Presente gratis, o al revés. Aquí se asigna el plan de cada app después del
 * pago, se suspende o reactiva una empresa (o una sola app) y, al bajar un
 * plan, se ajusta la empresa a sus nuevos límites (sp_ajustar_cupos).
 */
final class PlataformaControlador
{
    private const APPS = ['INVENTARIO', 'ASISTENCIA'];

    public static function resumen(Request $req): never
    {
        Auth::superadmin($req);
        $f = Db::fila(
            "SELECT
               (SELECT COUNT(*) FROM empresas WHERE deleted_at IS NULL)                              AS empresas,
               (SELECT COUNT(*) FROM empresas WHERE deleted_at IS NULL AND estado = 'SUSPENDIDA')    AS suspendidas,
               (SELECT COUNT(*) FROM empresas
                 WHERE deleted_at IS NULL AND created_at >= UTC_TIMESTAMP() - INTERVAL 30 DAY)       AS nuevas_30_dias,
               (SELECT COUNT(*) FROM usuarios WHERE deleted_at IS NULL AND activo = 1 AND es_superadmin = 0) AS cuentas_activas",
        );
        $porPlan = Db::filas(
            'SELECT aplicativo, plan_codigo AS codigo, plan_nombre AS nombre, COUNT(*) AS empresas
               FROM v_empresa_uso_app GROUP BY aplicativo, plan_codigo, plan_nombre
              ORDER BY aplicativo, empresas DESC',
        );
        // Empresas con alguna app en el límite: candidatas a cambiar de plan.
        $enLimite = (int) Db::valor(
            'SELECT COUNT(DISTINCT empresa_id) FROM v_empresa_uso_app
              WHERE (max_sedes IS NOT NULL AND sedes_usadas >= max_sedes)
                 OR (max_personas IS NOT NULL AND personas_usadas >= max_personas)
                 OR (max_productos IS NOT NULL AND productos_usados >= max_productos)',
        );
        Response::json(['resumen' => array_map('intval', $f) + ['en_limite' => $enLimite], 'por_plan' => $porPlan]);
    }

    public static function empresas(Request $req): never
    {
        Auth::superadmin($req);
        $where = ['e.deleted_at IS NULL'];
        $params = [];
        if (($buscar = $req->query('buscar')) !== null) {
            $where[] = '(e.nombre LIKE ? OR e.nit LIKE ? OR e.email_contacto LIKE ?)';
            array_push($params, "%$buscar%", "%$buscar%", "%$buscar%");
        }
        if (($estado = $req->query('estado')) !== null && in_array($estado, ['ACTIVA', 'SUSPENDIDA'], true)) {
            $where[] = 'e.estado = ?';
            $params[] = $estado;
        }
        if (($plan = $req->query('plan')) !== null) {
            $where[] = 'EXISTS (SELECT 1 FROM v_empresa_uso_app x WHERE x.empresa_id = e.id AND x.plan_codigo = ?)';
            $params[] = $plan;
        }
        $filas = Db::filas(
            'SELECT e.id, e.uuid, e.nombre, e.nit, e.telefono, e.email_contacto, e.estado,
                    e.notas_plataforma, e.created_at
               FROM empresas e
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY e.created_at DESC
              LIMIT 500',
            $params,
        );
        Response::json(['empresas' => self::conPlanes($filas)]);
    }

    /**
     * {planes?: {INVENTARIO|ASISTENCIA: {plan_id?, plan_vence?: 'AAAA-MM-DD'|null}},
     *  estado?: ACTIVA|SUSPENDIDA, apps?: {INVENTARIO: bool, ASISTENCIA: bool}, notas?: string}
     *
     * Por compatibilidad, `plan_id` / `plan_vence` sueltos se aplican a las
     * DOS apps. Al cambiar un plan se ajustan los cupos de esa app (pausa a los
     * sobrantes y quita las sedes elegidas de más; no borra nada).
     */
    public static function actualizarEmpresa(Request $req): never
    {
        Auth::superadmin($req);
        $id = $req->param('id');
        if (Db::valor('SELECT 1 FROM empresas WHERE id = ? AND deleted_at IS NULL', [$id]) === null) {
            throw HttpError::noEncontrado('Empresa');
        }
        $d = $req->json();

        $porApp = [];
        if (isset($d['planes']) && is_array($d['planes'])) {
            foreach ($d['planes'] as $app => $cambio) {
                if (!in_array($app, self::APPS, true) || !is_array($cambio)) {
                    throw HttpError::validacion("App desconocida: $app", 'planes');
                }
                $porApp[$app] = $cambio;
            }
        }
        if (array_key_exists('plan_id', $d) || array_key_exists('plan_vence', $d)) {
            foreach (self::APPS as $app) {
                $porApp[$app] = ($porApp[$app] ?? []) + array_intersect_key($d, ['plan_id' => 1, 'plan_vence' => 1]);
            }
        }

        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            foreach ($porApp as $app => $cambio) {
                Db::query(
                    'INSERT IGNORE INTO empresa_planes (empresa_id, aplicativo, plan_id)
                     VALUES (?, ?, (SELECT id FROM planes WHERE codigo = \'GRATIS\'))',
                    [$id, $app],
                );
                if (array_key_exists('plan_id', $cambio)) {
                    $plan = (int) $cambio['plan_id'];
                    $valido = Db::fila(
                        'SELECT 1 AS x FROM planes WHERE id = ? AND activo = 1 AND (aplicativo IS NULL OR aplicativo = ?)',
                        [$plan, $app],
                    );
                    if ($valido === null) {
                        throw HttpError::validacion('Plan inexistente, inactivo o de la otra app', 'plan_id');
                    }
                    Db::query('UPDATE empresa_planes SET plan_id = ? WHERE empresa_id = ? AND aplicativo = ?', [$plan, $id, $app]);
                }
                if (array_key_exists('plan_vence', $cambio)) {
                    $vence = $cambio['plan_vence'];
                    if ($vence !== null && !preg_match('/^\d{4}-\d{2}-\d{2}$/', (string) $vence)) {
                        throw HttpError::validacion('Fecha de vencimiento inválida (AAAA-MM-DD)', 'plan_vence');
                    }
                    Db::query('UPDATE empresa_planes SET plan_vence = ? WHERE empresa_id = ? AND aplicativo = ?', [$vence, $id, $app]);
                }
                // Si el plan bajó: pausa sobrantes y quita sedes elegidas de más.
                Db::query('CALL sp_ajustar_cupos(?, ?)', [$id, $app])->closeCursor();
            }
            if (array_key_exists('estado', $d)) {
                if (!in_array($d['estado'], ['ACTIVA', 'SUSPENDIDA'], true)) {
                    throw HttpError::validacion('Estado inválido', 'estado');
                }
                Db::query('UPDATE empresas SET estado = ? WHERE id = ?', [$d['estado'], $id]);
                if ($d['estado'] === 'SUSPENDIDA') {
                    // Sus sesiones de Ventario mueren ya; las de aquí se revalidan en cada petición.
                    Db::query(
                        'UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP(3)
                          WHERE revoked_at IS NULL AND usuario_id IN (SELECT id FROM usuarios WHERE empresa_id = ?)',
                        [$id],
                    );
                }
            }
            if (isset($d['apps']) && is_array($d['apps'])) {
                foreach ($d['apps'] as $app => $activo) {
                    if (!in_array($app, self::APPS, true)) {
                        throw HttpError::validacion("App desconocida: $app", 'apps');
                    }
                    Db::query(
                        'INSERT INTO empresa_aplicativos (empresa_id, aplicativo, activo) VALUES (?, ?, ?)
                         ON DUPLICATE KEY UPDATE activo = VALUES(activo)',
                        [$id, $app, $activo ? 1 : 0],
                    );
                }
            }
            if (array_key_exists('notas', $d)) {
                $notas = trim((string) ($d['notas'] ?? ''));
                Db::query('UPDATE empresas SET notas_plataforma = ? WHERE id = ?', [$notas === '' ? null : mb_substr($notas, 0, 500), $id]);
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        $fila = Db::fila(
            'SELECT e.id, e.uuid, e.nombre, e.nit, e.telefono, e.email_contacto, e.estado, e.notas_plataforma, e.created_at
               FROM empresas e WHERE e.id = ?',
            [$id],
        );
        Response::json(['empresa' => self::conPlanes([$fila])[0]]);
    }

    public static function planes(Request $req): never
    {
        Auth::superadmin($req);
        $filas = Db::filas(
            'SELECT p.*, (SELECT COUNT(DISTINCT ep.empresa_id) FROM empresa_planes ep
                            JOIN empresas e ON e.id = ep.empresa_id AND e.deleted_at IS NULL
                           WHERE ep.plan_id = p.id) AS empresas
               FROM planes p ORDER BY p.orden, p.id',
        );
        Response::json(['planes' => array_map([self::class, 'planJson'], $filas)]);
    }

    public static function crearPlan(Request $req): never
    {
        Auth::superadmin($req);
        $d = self::validarPlan($req->json(), true);
        Db::query(
            'INSERT INTO planes (codigo, aplicativo, nombre, descripcion, max_sedes, max_personas, max_productos, orden, activo)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)',
            [$d['codigo'], $d['aplicativo'], $d['nombre'], $d['descripcion'], $d['max_sedes'], $d['max_personas'], $d['max_productos'], $d['orden']],
        );
        $id = (int) Db::pdo()->lastInsertId();
        Response::json(['plan' => self::planJson(Db::fila('SELECT *, 0 AS empresas FROM planes WHERE id = ?', [$id]))], 201);
    }

    /**
     * Cambiar los límites de un plan aplica a todas sus empresas: las que ya
     * pasan del nuevo límite conservan lo que tienen, pero no pueden crear más.
     */
    public static function actualizarPlan(Request $req): never
    {
        Auth::superadmin($req);
        $id = $req->param('id');
        $actual = Db::fila('SELECT * FROM planes WHERE id = ?', [$id]) ?? throw HttpError::noEncontrado('Plan');
        $d = self::validarPlan($req->json() + $actual, false);
        $activo = array_key_exists('activo', $req->json()) ? ((bool) $req->json()['activo'] ? 1 : 0) : (int) $actual['activo'];
        if ($actual['codigo'] === 'GRATIS' && $activo === 0) {
            throw HttpError::validacion('El plan GRATIS no se puede desactivar: es el de las empresas nuevas', 'activo');
        }
        if ($actual['codigo'] === 'GRATIS' && $d['aplicativo'] !== null) {
            throw HttpError::validacion('El plan GRATIS es de las dos apps', 'aplicativo');
        }
        Db::query(
            'UPDATE planes SET nombre = ?, aplicativo = ?, descripcion = ?, max_sedes = ?, max_personas = ?, max_productos = ?,
                               orden = ?, activo = ? WHERE id = ?',
            [$d['nombre'], $d['aplicativo'], $d['descripcion'], $d['max_sedes'], $d['max_personas'], $d['max_productos'], $d['orden'], $activo, $id],
        );
        Response::json(['plan' => self::planJson(Db::fila(
            'SELECT p.*, (SELECT COUNT(DISTINCT ep.empresa_id) FROM empresa_planes ep WHERE ep.plan_id = p.id) AS empresas
               FROM planes p WHERE p.id = ?',
            [$id],
        ))]);
    }

    // ---------------------------------------------------------------------

    /** Agrega a cada empresa el plan y el uso de cada app. */
    private static function conPlanes(array $empresas): array
    {
        if ($empresas === []) {
            return [];
        }
        $ids = array_map(static fn ($e) => (int) $e['id'], $empresas);
        $usos = Db::filas(
            'SELECT * FROM v_empresa_uso_app WHERE empresa_id IN (' . Db::enLista($ids) . ')',
            $ids,
        );
        $porEmpresa = [];
        $recurso = static fn ($u, $m) => ['usados' => (int) $u, 'maximo' => $m === null ? null : (int) $m];
        foreach ($usos as $u) {
            $porEmpresa[(int) $u['empresa_id']][$u['aplicativo']] = [
                'activa'  => (int) $u['app_activa'] === 1,
                'plan'    => [
                    'id'       => (int) $u['plan_contratado_id'],
                    'codigo'   => $u['plan_codigo'],
                    'nombre'   => $u['plan_nombre'],
                    'vence'    => $u['plan_vence'],
                    'vencido'  => (bool) $u['plan_vencido'],
                ],
                'uso'     => [
                    'sedes'     => $recurso($u['sedes_usadas'], $u['max_sedes']),
                    'personas'  => $recurso($u['personas_usadas'], $u['max_personas']),
                    'productos' => $recurso($u['productos_usados'], $u['max_productos']),
                ],
            ];
        }
        return array_map(static function (array $e) use ($porEmpresa) {
            $apps = $porEmpresa[(int) $e['id']] ?? [];
            return [
                'id'             => (int) $e['id'],
                'uuid'           => $e['uuid'],
                'nombre'         => $e['nombre'],
                'nit'            => $e['nit'],
                'telefono'       => $e['telefono'],
                'email_contacto' => $e['email_contacto'],
                'estado'         => $e['estado'],
                'aplicativos'    => $apps,
                'apps'           => array_keys(array_filter($apps, static fn ($a) => $a['activa'])),
                'notas'          => $e['notas_plataforma'],
                'creada'         => $e['created_at'],
            ];
        }, $empresas);
    }

    private static function planJson(array $p): array
    {
        $n = static fn ($v) => $v === null ? null : (int) $v;
        return [
            'id'            => (int) $p['id'],
            'codigo'        => $p['codigo'],
            'aplicativo'    => $p['aplicativo'] ?? null,
            'nombre'        => $p['nombre'],
            'descripcion'   => $p['descripcion'],
            'max_sedes'     => $n($p['max_sedes']),
            'max_personas'  => $n($p['max_personas']),
            'max_productos' => $n($p['max_productos']),
            'orden'         => (int) $p['orden'],
            'activo'        => (int) $p['activo'] === 1,
            'empresas'      => (int) ($p['empresas'] ?? 0),
        ];
    }

    private static function validarPlan(array $d, bool $nuevo): array
    {
        $codigo = strtoupper(trim((string) ($d['codigo'] ?? '')));
        if ($nuevo && !preg_match('/^[A-Z0-9_]{3,20}$/', $codigo)) {
            throw HttpError::validacion('Código: 3 a 20 letras mayúsculas, números o _', 'codigo');
        }
        $nombre = trim((string) ($d['nombre'] ?? ''));
        if (mb_strlen($nombre) < 2 || mb_strlen($nombre) > 60) {
            throw HttpError::validacion('Nombre del plan: 2 a 60 caracteres', 'nombre');
        }
        // Vacío o null = sin límite.
        $limite = static function (mixed $v, string $campo): ?int {
            if ($v === null || $v === '') {
                return null;
            }
            $n = filter_var($v, FILTER_VALIDATE_INT);
            if ($n === false || $n < 1 || $n > 1_000_000) {
                throw HttpError::validacion('Límite inválido (vacío = sin límite)', $campo);
            }
            return $n;
        };
        // App del plan: INVENTARIO, ASISTENCIA o vacío (sirve para las dos).
        $app = $d['aplicativo'] ?? null;
        $app = $app === '' ? null : $app;
        if ($app !== null && !in_array($app, self::APPS, true)) {
            throw HttpError::validacion('App del plan inválida', 'aplicativo');
        }
        $descripcion = trim((string) ($d['descripcion'] ?? ''));
        return [
            'codigo'        => $codigo,
            'aplicativo'    => $app,
            'nombre'        => $nombre,
            'descripcion'   => $descripcion === '' ? null : mb_substr($descripcion, 0, 255),
            'max_sedes'     => $limite($d['max_sedes'] ?? null, 'max_sedes'),
            'max_personas'  => $limite($d['max_personas'] ?? null, 'max_personas'),
            'max_productos' => $limite($d['max_productos'] ?? null, 'max_productos'),
            'orden'         => (int) ($d['orden'] ?? 0),
        ];
    }
}
