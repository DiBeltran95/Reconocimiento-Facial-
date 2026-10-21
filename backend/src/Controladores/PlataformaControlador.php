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
 * Los planes se cobran fuera de las apps (política de Google Play): aquí se
 * asigna el plan a cada empresa después del pago, se habilita cada app y se
 * suspende o reactiva una empresa.
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
            'SELECT plan_codigo AS codigo, plan_nombre AS nombre, COUNT(*) AS empresas
               FROM v_empresa_uso GROUP BY plan_codigo, plan_nombre ORDER BY empresas DESC',
        );
        // Empresas en el límite: candidatas a cambiar de plan.
        $enLimite = (int) Db::valor(
            'SELECT COUNT(*) FROM v_empresa_uso
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
            $where[] = 'u.plan_codigo = ?';
            $params[] = $plan;
        }
        $filas = Db::filas(
            'SELECT e.id, e.uuid, e.nombre, e.nit, e.telefono, e.email_contacto, e.estado, e.plan_id, e.plan_vence,
                    e.notas_plataforma, e.created_at,
                    u.plan_codigo, u.plan_nombre, u.plan_vencido,
                    u.sedes_usadas, u.max_sedes, u.personas_usadas, u.max_personas, u.productos_usados, u.max_productos,
                    (SELECT GROUP_CONCAT(aplicativo ORDER BY aplicativo) FROM empresa_aplicativos ea
                      WHERE ea.empresa_id = e.id AND ea.activo = 1) AS apps
               FROM empresas e
               JOIN v_empresa_uso u ON u.empresa_id = e.id
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY e.created_at DESC
              LIMIT 500',
            $params,
        );
        Response::json(['empresas' => array_map([self::class, 'empresaJson'], $filas)]);
    }

    /**
     * {plan_id?, plan_vence?: 'AAAA-MM-DD'|null, estado?: ACTIVA|SUSPENDIDA,
     *  apps?: {INVENTARIO: bool, ASISTENCIA: bool}, notas?: string}
     */
    public static function actualizarEmpresa(Request $req): never
    {
        Auth::superadmin($req);
        $id = $req->param('id');
        if (Db::valor('SELECT 1 FROM empresas WHERE id = ? AND deleted_at IS NULL', [$id]) === null) {
            throw HttpError::noEncontrado('Empresa');
        }
        $d = $req->json();
        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            if (array_key_exists('plan_id', $d)) {
                $plan = (int) $d['plan_id'];
                if (Db::valor('SELECT 1 FROM planes WHERE id = ? AND activo = 1', [$plan]) === null) {
                    throw HttpError::validacion('Plan inexistente o inactivo', 'plan_id');
                }
                Db::query('UPDATE empresas SET plan_id = ? WHERE id = ?', [$plan, $id]);
            }
            if (array_key_exists('plan_vence', $d)) {
                $vence = $d['plan_vence'];
                if ($vence !== null && !preg_match('/^\d{4}-\d{2}-\d{2}$/', (string) $vence)) {
                    throw HttpError::validacion('Fecha de vencimiento inválida (AAAA-MM-DD)', 'plan_vence');
                }
                Db::query('UPDATE empresas SET plan_vence = ? WHERE id = ?', [$vence, $id]);
            }
            if (array_key_exists('estado', $d)) {
                if (!in_array($d['estado'], ['ACTIVA', 'SUSPENDIDA'], true)) {
                    throw HttpError::validacion('Estado inválido', 'estado');
                }
                Db::query('UPDATE empresas SET estado = ? WHERE id = ?', [$d['estado'], $id]);
                if ($d['estado'] === 'SUSPENDIDA') {
                    // Sus sesiones de Inventario mueren ya; las de aquí se revalidan en cada petición.
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
            'SELECT e.id, e.uuid, e.nombre, e.nit, e.telefono, e.email_contacto, e.estado, e.plan_id, e.plan_vence,
                    e.notas_plataforma, e.created_at, u.plan_codigo, u.plan_nombre, u.plan_vencido,
                    u.sedes_usadas, u.max_sedes, u.personas_usadas, u.max_personas, u.productos_usados, u.max_productos,
                    (SELECT GROUP_CONCAT(aplicativo ORDER BY aplicativo) FROM empresa_aplicativos ea
                      WHERE ea.empresa_id = e.id AND ea.activo = 1) AS apps
               FROM empresas e JOIN v_empresa_uso u ON u.empresa_id = e.id WHERE e.id = ?',
            [$id],
        );
        Response::json(['empresa' => self::empresaJson($fila)]);
    }

    public static function planes(Request $req): never
    {
        Auth::superadmin($req);
        $filas = Db::filas(
            'SELECT p.*, (SELECT COUNT(*) FROM empresas e WHERE e.plan_id = p.id AND e.deleted_at IS NULL) AS empresas
               FROM planes p ORDER BY p.orden, p.id',
        );
        Response::json(['planes' => array_map([self::class, 'planJson'], $filas)]);
    }

    public static function crearPlan(Request $req): never
    {
        Auth::superadmin($req);
        $d = self::validarPlan($req->json(), true);
        Db::query(
            'INSERT INTO planes (codigo, nombre, descripcion, max_sedes, max_personas, max_productos, orden, activo)
             VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
            [$d['codigo'], $d['nombre'], $d['descripcion'], $d['max_sedes'], $d['max_personas'], $d['max_productos'], $d['orden']],
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
        Db::query(
            'UPDATE planes SET nombre = ?, descripcion = ?, max_sedes = ?, max_personas = ?, max_productos = ?,
                               orden = ?, activo = ? WHERE id = ?',
            [$d['nombre'], $d['descripcion'], $d['max_sedes'], $d['max_personas'], $d['max_productos'], $d['orden'], $activo, $id],
        );
        Response::json(['plan' => self::planJson(Db::fila(
            'SELECT p.*, (SELECT COUNT(*) FROM empresas e WHERE e.plan_id = p.id AND e.deleted_at IS NULL) AS empresas
               FROM planes p WHERE p.id = ?',
            [$id],
        ))]);
    }

    // ---------------------------------------------------------------------

    private static function empresaJson(array $e): array
    {
        $recurso = static fn ($u, $m) => ['usados' => (int) $u, 'maximo' => $m === null ? null : (int) $m];
        return [
            'id'             => (int) $e['id'],
            'uuid'           => $e['uuid'],
            'nombre'         => $e['nombre'],
            'nit'            => $e['nit'],
            'telefono'       => $e['telefono'],
            'email_contacto' => $e['email_contacto'],
            'estado'         => $e['estado'],
            'plan'           => [
                'id' => (int) $e['plan_id'], 'codigo' => $e['plan_codigo'], 'nombre' => $e['plan_nombre'],
                'vence' => $e['plan_vence'], 'vencido' => (bool) $e['plan_vencido'],
            ],
            'uso'            => [
                'sedes'     => $recurso($e['sedes_usadas'], $e['max_sedes']),
                'personas'  => $recurso($e['personas_usadas'], $e['max_personas']),
                'productos' => $recurso($e['productos_usados'], $e['max_productos']),
            ],
            'apps'           => $e['apps'] ? explode(',', $e['apps']) : [],
            'notas'          => $e['notas_plataforma'],
            'creada'         => $e['created_at'],
        ];
    }

    private static function planJson(array $p): array
    {
        $n = static fn ($v) => $v === null ? null : (int) $v;
        return [
            'id'            => (int) $p['id'],
            'codigo'        => $p['codigo'],
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
        $descripcion = trim((string) ($d['descripcion'] ?? ''));
        return [
            'codigo'        => $codigo,
            'nombre'        => $nombre,
            'descripcion'   => $descripcion === '' ? null : mb_substr($descripcion, 0, 255),
            'max_sedes'     => $limite($d['max_sedes'] ?? null, 'max_sedes'),
            'max_personas'  => $limite($d['max_personas'] ?? null, 'max_personas'),
            'max_productos' => $limite($d['max_productos'] ?? null, 'max_productos'),
            'orden'         => (int) ($d['orden'] ?? 0),
        ];
    }
}
