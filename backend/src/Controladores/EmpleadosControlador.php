<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Fotos;
use App\Servicios\Horarios;
use App\Servicios\Tiempo;

/**
 * Personas que marcan asistencia con el rostro.
 *
 * Plataforma multiempresa: todo se acota a la empresa y a las sedes del
 * administrativo (las del gerente, o todas las de la empresa para el ADMIN).
 * El empleado (`empleados`) es la PERSONA, una sola vez para las dos apps:
 * nombre, documento, correo, teléfono, cargo y sede viven SOLO aquí. Se
 * registra aquí o en Ventario y aparece en las dos. Puede tener una cuenta de
 * acceso (`usuarios.empleado_id`) de Presente, de Ventario o de ambas, que
 * entra con SU correo; cuenta una vez en el cupo del plan y, si su cuenta se
 * inactiva, deja de poder marcar.
 */
final class EmpleadosControlador
{
    /** Un empleado con cuenta solo está activo si su cuenta también lo está. */
    private const SELECT = "SELECT e.id, e.empresa_id, e.sede_id, u.id AS usuario_id, e.documento, e.nombre, e.cargo,
                                   e.telefono, e.email, e.activo, e.en_pausa, e.consentimiento_en,
                                   u.rol AS cuenta_rol, u.rol_asistencia AS cuenta_rol_asistencia,
                                   (u.id IS NOT NULL AND u.activo <> 1) AS cuenta_inactiva
                              FROM empleados e
                              LEFT JOIN usuarios u ON u.empleado_id = e.id AND u.deleted_at IS NULL";

    public static function listar(Request $req): never
    {
        $admin = Auth::admin($req);
        $sedeId = (int) $req->query('sede_id', '0');
        $inactivos = $req->query('inactivos') === '1';

        $where = ['e.empresa_id = ?'];
        $params = [$admin['empresa_id']];
        if ($sedeId > 0) {
            Auth::exigirSede($admin, $sedeId);
            $where[] = 'e.sede_id = ?';
            $params[] = $sedeId;
        } else {
            if ($admin['sedes'] === []) {
                Response::json(['empleados' => []]);
            }
            $where[] = 'e.sede_id IN (' . Db::enLista($admin['sedes']) . ')';
            array_push($params, ...$admin['sedes']);
        }
        if (!$inactivos) {
            $where[] = 'e.activo = 1';
        }
        $sql = self::SELECT . ' WHERE ' . implode(' AND ', $where) . ' ORDER BY e.nombre';

        $filas = Db::filas($sql, $params);
        // Turno de esta semana de cada uno (una sola consulta para todos).
        $semana = Horarios::lunes(Tiempo::hoyLocal());
        $plan = Horarios::porSemana(array_map(static fn ($e) => (int) $e['id'], $filas), [$semana]);
        Response::json(['empleados' => array_map(static fn (array $e) => self::aJson($e) + [
            'turno_semana' => self::turnoCorto($plan[(int) $e['id']][$semana]['horario'] ?? null),
        ], $filas)]);
    }

    public static function ver(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'), $admin['empresa_id']);
        Auth::exigirSede($admin, (int) $empleado['sede_id']);
        Response::json(['empleado' => self::aJson($empleado)]);
    }

    public static function crear(Request $req): never
    {
        $admin = Auth::admin($req);
        $d = self::validar($req->json(), $admin['empresa_id']);
        Auth::exigirSede($admin, $d['sede_id']);
        // Autorización de datos biométricos (Ley 1581): quién y cuándo.
        $consiente = ($req->json()['consentimiento'] ?? false) === true;

        $existente = Db::fila(
            'SELECT id, nombre, activo, sede_id FROM empleados WHERE empresa_id = ? AND documento = ?',
            [$admin['empresa_id'], $d['documento']],
        );
        if ($existente !== null && (int) $existente['activo'] === 1) {
            throw new HttpError(409, "Ya existe un empleado con ese documento: {$existente['nombre']}", ['campo' => 'documento']);
        }
        if ($d['email'] !== null) {
            self::exigirCorreoLibre($d['email'], $existente === null ? null : (int) $existente['id']);
        }

        if ($existente !== null) {
            // Reingreso: se reactiva el mismo registro y conserva su historial.
            // El cupo del plan lo exige la base (LIMITE_PLAN → 409).
            Db::query(
                'UPDATE empleados SET sede_id = ?, nombre = ?, cargo = ?, telefono = ?, email = ?, activo = 1 WHERE id = ?',
                [$d['sede_id'], $d['nombre'], $d['cargo'], $d['telefono'], $d['email'], $existente['id']],
            );
            $id = (int) $existente['id'];
            $estado = 200;
        } else {
            Db::query(
                'INSERT INTO empleados (empresa_id, sede_id, documento, nombre, cargo, telefono, email)
                 VALUES (?, ?, ?, ?, ?, ?, ?)',
                [$admin['empresa_id'], $d['sede_id'], $d['documento'], $d['nombre'], $d['cargo'], $d['telefono'], $d['email']],
            );
            $id = (int) Db::pdo()->lastInsertId();
            $estado = 201;
        }
        if ($consiente) {
            self::registrarConsentimiento($id, $admin['id']);
        }

        Response::json([
            'empleado'   => self::aJson(self::buscar($id, $admin['empresa_id'])),
            'reactivado' => $existente !== null,
        ], $estado);
    }

    public static function actualizar(Request $req): never
    {
        $admin = Auth::admin($req);
        $actual = self::buscar($req->param('id'), $admin['empresa_id']);
        Auth::exigirSede($admin, (int) $actual['sede_id']);

        $d = self::validar($req->json() + [
            'sede_id'   => $actual['sede_id'],
            'documento' => $actual['documento'],
            'nombre'    => $actual['nombre'],
            'cargo'     => $actual['cargo'],
            'telefono'  => $actual['telefono'],
            'email'     => $actual['email'],
        ], $admin['empresa_id'], $actual['documento'] !== null);
        Auth::exigirSede($admin, $d['sede_id']);

        if ($d['documento'] !== null) {
            $duplicado = Db::valor(
                'SELECT nombre FROM empleados WHERE empresa_id = ? AND documento = ? AND id <> ?',
                [$admin['empresa_id'], $d['documento'], $actual['id']],
            );
            if ($duplicado !== null) {
                throw new HttpError(409, "Ese documento ya pertenece a: $duplicado", ['campo' => 'documento']);
            }
        }
        if ($d['email'] !== $actual['email']) {
            if ($d['email'] === null && $actual['usuario_id'] !== null) {
                // Con cuenta, el correo es con el que entra: no puede quedar vacío.
                throw HttpError::validacion('Con este correo entra a las apps: no puede quedar vacío', 'email');
            }
            if ($d['email'] !== null) {
                self::exigirCorreoLibre($d['email'], (int) $actual['id']);
            }
        }

        // Sus datos viven solo aquí: la cuenta (si tiene) los lee de este registro.
        Db::query(
            'UPDATE empleados SET sede_id = ?, documento = ?, nombre = ?, cargo = ?, telefono = ?, email = ? WHERE id = ?',
            [$d['sede_id'], $d['documento'], $d['nombre'], $d['cargo'], $d['telefono'], $d['email'], $actual['id']],
        );
        if (($req->json()['consentimiento'] ?? false) === true && $actual['consentimiento_en'] === null) {
            self::registrarConsentimiento((int) $actual['id'], $admin['id']);
        }
        Response::json(['empleado' => self::aJson(self::buscar((int) $actual['id'], $admin['empresa_id']))]);
    }

    /**
     * Pausa o reactiva a una persona en Presente cuando el plan no alcanza
     * para todos: en pausa no ocupa cupo ni marca, pero conserva sus fotos e
     * historial. Reactivar exige cupo (LIMITE_PLAN → 409).
     */
    public static function pausar(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'), $admin['empresa_id']);
        Auth::exigirSede($admin, (int) $empleado['sede_id']);
        $pausada = (bool) ($req->json()['pausada'] ?? true);
        if ($pausada && $empleado['cuenta_rol_asistencia'] === Auth::ROL_ADMIN) {
            throw HttpError::validacion('Al administrador no se le pausa');
        }
        Db::query('UPDATE empleados SET en_pausa = ? WHERE id = ?', [$pausada ? 1 : 0, $empleado['id']]);
        Response::json(['empleado' => self::aJson(self::buscar((int) $empleado['id'], $admin['empresa_id']))]);
    }

    /** Baja lógica: conserva el historial pero borra sus datos biométricos. */
    public static function desactivar(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'), $admin['empresa_id']);
        Auth::exigirSede($admin, (int) $empleado['sede_id']);
        if ($empleado['cuenta_rol_asistencia'] === Auth::ROL_ADMIN || $empleado['cuenta_rol'] === 'ADMIN') {
            throw HttpError::validacion('El administrador de la empresa no se da de baja');
        }

        // Sin empleado activo, su cuenta (si tiene) tampoco entra a las apps.
        Db::query('UPDATE empleados SET activo = 0 WHERE id = ?', [$empleado['id']]);
        Fotos::borrarTodas((int) $empleado['id']);
        Response::sinContenido();
    }

    /** Reemplaza las fotos del rostro (multipart, campo `fotos[]`). */
    public static function subirFotos(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'), $admin['empresa_id']);
        Auth::exigirSede($admin, (int) $empleado['sede_id']);
        if ((int) $empleado['activo'] !== 1) {
            throw HttpError::validacion('El empleado está inactivo');
        }
        // Sin autorización registrada no se guardan datos biométricos. La app la
        // envía en el mismo formulario (campo `consentimiento` = 1).
        if ($empleado['consentimiento_en'] === null) {
            if (($_POST['consentimiento'] ?? '') !== '1') {
                throw new HttpError(422, 'Falta la autorización del empleado para tratar sus datos biométricos', [
                    'codigo' => 'FALTA_CONSENTIMIENTO',
                    'campo'  => 'consentimiento',
                ]);
            }
            self::registrarConsentimiento((int) $empleado['id'], $admin['id']);
        }

        $subidas = Fotos::subidas('fotos');
        if ($subidas === []) {
            $subidas = Fotos::subidas('foto');
        }
        $fotos = Fotos::reemplazar((int) $empleado['id'], $subidas);
        self::marcarCambio((int) $empleado['id']);

        Response::json(['fotos' => $fotos]);
    }

    public static function borrarFotos(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'), $admin['empresa_id']);
        Auth::exigirSede($admin, (int) $empleado['sede_id']);

        Fotos::borrarTodas((int) $empleado['id']);
        self::marcarCambio((int) $empleado['id']);
        Response::sinContenido();
    }

    /** Descarga una foto. Kioscos: solo de su sede. Administradores: de sus sedes. */
    public static function foto(Request $req): never
    {
        $quien = Auth::adminODispositivo($req);
        $empleado = self::buscar($req->param('id'), $quien['empresa_id']);
        $sedeId = (int) $empleado['sede_id'];

        $permitido = $quien['tipo'] === 'dispositivo'
            ? $quien['sede_id'] === $sedeId
            : Auth::puedeSede($quien, $sedeId);
        if (!$permitido) {
            throw HttpError::prohibido();
        }

        $ruta = Fotos::ruta((int) $empleado['id'], $req->param('n'));
        if ($ruta === null) {
            throw HttpError::noEncontrado('Foto');
        }
        Response::archivo($ruta, 'image/jpeg', $req->header('If-None-Match'));
    }

    // ---------------------------------------------------------------------

    private static function turnoCorto(?array $h): ?array
    {
        return $h === null ? null : ['id' => $h['id'], 'nombre' => $h['nombre'], 'bloques' => $h['bloques']];
    }

    public static function aJson(array $e): array
    {
        return [
            'id'                => (int) $e['id'],
            'sede_id'           => (int) $e['sede_id'],
            'documento'         => $e['documento'],
            'nombre'            => $e['nombre'],
            'cargo'             => $e['cargo'],
            'telefono'          => $e['telefono'] ?? null,
            'email'             => $e['email'] ?? null,
            'activo'            => (int) $e['activo'] === 1,
            // En pausa por el plan: no ocupa cupo ni puede marcar hasta reactivarla.
            'en_pausa'          => (int) ($e['en_pausa'] ?? 0) === 1,
            // Con cuenta: entra a las apps con SU correo.
            'cuenta'            => isset($e['usuario_id']) && $e['usuario_id'] !== null
                ? [
                    'email'          => $e['email'],
                    'activa'         => !(bool) $e['cuenta_inactiva'],
                    'rol_asistencia' => $e['cuenta_rol_asistencia'] ?? null,
                    'rol_inventario' => $e['cuenta_rol'] ?? null,
                ]
                : null,
            'consentimiento_en' => isset($e['consentimiento_en']) && $e['consentimiento_en'] !== null
                ? Tiempo::utcSqlAIsoUtc((string) $e['consentimiento_en'])
                : null,
            'fotos'             => Fotos::listar((int) $e['id']),
        ];
    }

    private static function buscar(int $id, int $empresaId): array
    {
        $empleado = Db::fila(self::SELECT . ' WHERE e.id = ? AND e.empresa_id = ?', [$id, $empresaId]);
        if ($empleado === null) {
            throw HttpError::noEncontrado('Empleado');
        }
        return $empleado;
    }

    private static function registrarConsentimiento(int $empleadoId, int $usuarioId): void
    {
        Db::query(
            'UPDATE empleados SET consentimiento_en = UTC_TIMESTAMP(), consentimiento_por = ? WHERE id = ?',
            [$usuarioId, $empleadoId],
        );
    }

    /** Cambiar `updated_at` avisa a los kioscos que deben volver a sincronizarlo. */
    private static function marcarCambio(int $id): void
    {
        Db::query('UPDATE empleados SET updated_at = CURRENT_TIMESTAMP(3) WHERE id = ?', [$id]);
    }

    /**
     * El correo es con lo que se entra a la plataforma: no puede tenerlo otra
     * persona (de esta u otra empresa) ni una cuenta técnica. La base lo exige
     * igual (uk_empleados_email, EMAIL_EN_USO); aquí se explica mejor.
     */
    private static function exigirCorreoLibre(string $email, ?int $empleadoId): void
    {
        $otro = Db::valor(
            'SELECT 1 FROM empleados WHERE email = ? AND id <> COALESCE(?, 0)
             UNION ALL SELECT 1 FROM usuarios WHERE email = ? LIMIT 1',
            [$email, $empleadoId, $email],
        );
        if ($otro !== null) {
            throw new HttpError(409, 'Ese correo ya lo usa otra persona', ['campo' => 'email', 'codigo' => 'EMAIL_EN_USO']);
        }
    }

    /**
     * @param bool $exigirDocumento false solo al editar a quien aún no tiene
     *   documento (p. ej. el dueño, creado al registrar la empresa).
     * @return array{sede_id:int, documento:?string, nombre:string, cargo:?string, telefono:?string, email:?string}
     */
    private static function validar(array $datos, int $empresaId, bool $exigirDocumento = true): array
    {
        $documento = preg_replace('/[\s.]/', '', (string) ($datos['documento'] ?? ''));
        if ($documento === '' && !$exigirDocumento) {
            $documento = null;
        } elseif (!preg_match('/^[A-Za-z0-9-]{3,20}$/', $documento)) {
            throw HttpError::validacion('Documento inválido: 3 a 20 letras o números, sin puntos', 'documento');
        }

        $nombre = trim(preg_replace('/\s+/u', ' ', (string) ($datos['nombre'] ?? '')));
        if (mb_strlen($nombre) < 3 || mb_strlen($nombre) > 120) {
            throw HttpError::validacion('Escribe el nombre completo (3 a 120 caracteres)', 'nombre');
        }

        $cargo = trim(preg_replace('/\s+/u', ' ', (string) ($datos['cargo'] ?? '')));
        if (mb_strlen($cargo) > 60) {
            throw HttpError::validacion('El cargo admite máximo 60 caracteres', 'cargo');
        }

        $sedeId = (int) ($datos['sede_id'] ?? 0);
        $sedeValida = Db::valor(
            'SELECT 1 FROM sedes WHERE id = ? AND empresa_id = ? AND activo = 1 AND deleted_at IS NULL',
            [$sedeId, $empresaId],
        );
        if ($sedeValida === null) {
            throw HttpError::validacion('Selecciona una sede válida', 'sede_id');
        }

        $telefono = trim((string) ($datos['telefono'] ?? ''));
        if (mb_strlen($telefono) > 30) {
            throw HttpError::validacion('El teléfono admite máximo 30 caracteres', 'telefono');
        }
        $email = mb_strtolower(trim((string) ($datos['email'] ?? '')));
        if ($email !== '' && (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 191)) {
            throw HttpError::validacion('Escribe un correo válido', 'email');
        }

        return [
            'sede_id'   => $sedeId,
            'documento' => $documento === null ? null : strtoupper($documento),
            'nombre'    => $nombre,
            'cargo'     => $cargo === '' ? null : $cargo,
            'telefono'  => $telefono === '' ? null : $telefono,
            'email'     => $email === '' ? null : $email,
        ];
    }
}
