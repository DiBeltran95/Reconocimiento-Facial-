<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Correo;
use App\Servicios\Ids;
use App\Servicios\Plan;

/**
 * Cuentas de acceso a Presente.
 *
 * El EMPLEADO es uno solo para las dos apps (su ficha en asis_empleados, con
 * documento, teléfono y correo). Aquí se le da acceso a PRESENTE con un rol de
 * Presente: GERENTE (sus sedes), TALENTO_HUMANO (todas las sedes) u OPERARIO.
 * Su rol en Ventario no se toca: lo decide Ventario. La única regla común es
 * que el administrador (dueño) lo es en las dos (ck_usuarios_roles).
 *
 *   · Si el empleado ya tiene cuenta (de Ventario), solo se le agrega Presente:
 *     entra con el mismo correo y contraseña.
 *   · Si no tiene, se crea con contraseña al azar y se le avisa por correo que
 *     cree la suya con «¿Olvidaste tu contraseña?».
 *   · El OPERARIO es una cuenta técnica (los teléfonos de marcación), sin
 *     empleado: no ocupa cupo de personas.
 *
 * Las sedes de la cuenta (usuario_sedes) son las mismas en las dos apps: si
 * la persona ya trabaja en Ventario, sus sedes se gestionan allá. Solo el
 * administrador gestiona las cuentas.
 */
final class UsuariosControlador
{
    /** Roles que se dan desde Presente (el administrador es el dueño, no se asigna). */
    private const ROLES_ASIGNABLES = [Auth::ROL_GERENTE, Auth::ROL_TALENTO_HUMANO, Auth::ROL_OPERARIO];

    private const SELECT = "SELECT u.id, u.uuid, u.nombre, u.documento, u.email, u.telefono, u.rol, u.rol_asistencia,
                                   u.activo, u.pausa_asistencia, u.created_at,
                                   (SELECT e.id FROM asis_empleados e WHERE e.usuario_id = u.id LIMIT 1) AS empleado_id,
                                   (SELECT GROUP_CONCAT(us.sede_id ORDER BY us.sede_id) FROM usuario_sedes us
                                     WHERE us.usuario_id = u.id) AS sedes
                              FROM usuarios u";

    /** Cuentas con acceso a Presente. */
    public static function listar(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        $filas = Db::filas(
            self::SELECT . ' WHERE u.empresa_id = ? AND u.deleted_at IS NULL AND u.rol_asistencia IS NOT NULL
                              ORDER BY u.activo DESC, u.nombre',
            [$admin['empresa_id']],
        );
        Response::json([
            'usuarios'    => array_map([self::class, 'aJson'], $filas),
            'aplicativos' => Plan::aplicativos($admin['empresa_id']),
            'plan'        => Plan::deEmpresa($admin['empresa_id']),
            'planes'      => Plan::planes($admin['empresa_id']),
        ]);
    }

    /**
     * Empleados (registrados en cualquiera de las dos apps) que aún no tienen
     * acceso a Presente: para darles una cuenta sin volver a escribir sus datos.
     */
    public static function candidatos(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        if ($admin['sedes'] === []) {
            Response::json(['empleados' => []]);
        }
        $where = ['e.empresa_id = ?', 'e.activo = 1', '(e.usuario_id IS NULL OR u.rol_asistencia IS NULL)',
                  'e.sede_id IN (' . Db::enLista($admin['sedes']) . ')'];
        $params = [$admin['empresa_id'], ...$admin['sedes']];
        $q = trim((string) $req->query('q', ''));
        if ($q !== '') {
            $where[] = '(e.nombre LIKE ? OR e.documento LIKE ?)';
            array_push($params, "%$q%", "%$q%");
        }
        $filas = Db::filas(
            'SELECT e.id, e.documento, e.nombre, e.cargo, e.telefono, COALESCE(e.email, u.email) AS email, e.sede_id,
                    s.nombre AS sede, (u.id IS NOT NULL) AS con_cuenta
               FROM asis_empleados e
               JOIN sedes s ON s.id = e.sede_id
               LEFT JOIN usuarios u ON u.id = e.usuario_id AND u.deleted_at IS NULL
              WHERE ' . implode(' AND ', $where) . '
              ORDER BY e.nombre LIMIT 200',
            $params,
        );
        Response::json(['empleados' => array_map(static fn (array $f) => [
            'id'         => (int) $f['id'],
            'documento'  => $f['documento'],
            'nombre'     => $f['nombre'],
            'cargo'      => $f['cargo'],
            'telefono'   => $f['telefono'],
            'email'      => $f['email'],
            'sede_id'    => (int) $f['sede_id'],
            'sede'       => $f['sede'],
            // Ya entra a Ventario: con el mismo correo y contraseña entrará aquí.
            'con_cuenta' => (bool) $f['con_cuenta'],
        ], $filas)]);
    }

    /**
     * Cuerpo: {rol_asistencia, empleado_id?, sedes?, email?, nombre?}
     * Con empleado_id: acceso a Presente para ese empleado. Sin él: solo el
     * OPERARIO (cuenta técnica) con nombre y correo.
     */
    public static function crear(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        $d = $req->json();
        $rol = self::validarRol($d['rol_asistencia'] ?? self::rolLegado($d['rol'] ?? null));
        $empleadoId = (int) ($d['empleado_id'] ?? 0);

        $pdo = Db::pdo();
        $pdo->beginTransaction();
        $nueva = false;
        try {
            if ($empleadoId > 0) {
                $ficha = Db::fila(
                    'SELECT e.id, e.sede_id, e.documento, e.nombre, e.telefono, e.email, e.usuario_id,
                            u.rol AS usuario_rol, u.rol_asistencia AS usuario_rol_asistencia, u.email AS usuario_email
                       FROM asis_empleados e
                       LEFT JOIN usuarios u ON u.id = e.usuario_id AND u.deleted_at IS NULL
                      WHERE e.id = ? AND e.empresa_id = ? AND e.activo = 1',
                    [$empleadoId, $admin['empresa_id']],
                ) ?? throw HttpError::noEncontrado('Empleado');
                Auth::exigirSede($admin, (int) $ficha['sede_id']);

                if ($ficha['usuario_id'] !== null && $ficha['usuario_rol_asistencia'] !== null) {
                    throw new HttpError(409, 'Ese empleado ya tiene acceso a Presente', ['codigo' => 'YA_TIENE_ACCESO']);
                }
                if ($ficha['usuario_id'] !== null && $ficha['usuario_email'] !== null) {
                    // Ya entra a Ventario: se le agrega Presente con su misma cuenta.
                    $id = (int) $ficha['usuario_id'];
                    $sedes = $ficha['usuario_rol'] !== null
                        ? self::sedesDe($id) // las gestiona Ventario
                        : self::validarSedes($d['sedes'] ?? [], $admin);
                    self::validarSedesDelRol($rol, $sedes);
                    Db::query('UPDATE usuarios SET rol_asistencia = ?, pausa_asistencia = 0 WHERE id = ?', [$rol, $id]);
                    if ($ficha['usuario_rol'] === null) {
                        self::fijarSedes($id, $sedes);
                    }
                } else {
                    $email = self::validarEmail($d['email'] ?? $ficha['email'] ?? '');
                    $sedes = self::validarSedes($d['sedes'] ?? [], $admin);
                    self::validarSedesDelRol($rol, $sedes);
                    $id = self::insertarCuenta($admin['empresa_id'], $ficha['nombre'], $ficha['documento'], $email,
                        $ficha['telefono'], $rol, (int) $ficha['id']);
                    self::fijarSedes($id, $sedes);
                    Db::query('UPDATE asis_empleados SET usuario_id = ?, email = COALESCE(email, ?) WHERE id = ?',
                        [$id, $email, $ficha['id']]);
                    $nueva = true;
                }
            } else {
                if ($rol !== Auth::ROL_OPERARIO) {
                    throw HttpError::validacion('Elige el empleado al que le das acceso', 'empleado_id');
                }
                $id = self::insertarCuenta($admin['empresa_id'], self::validarNombre($d['nombre'] ?? ''), null,
                    self::validarEmail($d['email'] ?? ''), null, $rol, null);
                $nueva = true;
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }

        $cuenta = self::buscar($id, $admin);
        $aviso = $nueva ? self::avisarAcceso((string) $cuenta['email'], (string) $cuenta['nombre']) : false;
        Response::json([
            'usuario'          => self::aJson($cuenta),
            'cuenta_existente' => !$nueva,
            'aviso_enviado'    => $aviso,
        ], 201);
    }

    /** Cambia el rol de Presente, las sedes, el estado o (operario) el nombre. */
    public static function actualizar(Request $req): never
    {
        $yo = Auth::adminEmpresa($req);
        $actual = self::buscar($req->param('id'), $yo);
        $d = $req->json();
        $esYo = $yo['id'] === (int) $actual['id'];
        $esAdmin = $actual['rol_asistencia'] === Auth::ROL_ADMIN;

        $rol = $actual['rol_asistencia'];
        if (array_key_exists('rol_asistencia', $d) && $d['rol_asistencia'] !== $rol) {
            if ($esAdmin) {
                throw HttpError::validacion('El administrador lo es en las dos apps: se cambia desde Ventario');
            }
            $rol = self::validarRol($d['rol_asistencia']);
        }
        $activo = array_key_exists('activo', $d) ? ((bool) $d['activo'] ? 1 : 0) : (int) $actual['activo'];
        if ($esYo && $activo !== 1) {
            throw HttpError::validacion('No puedes desactivarte a ti mismo');
        }
        // Con acceso a Ventario, las sedes se gestionan allá.
        $tocaSedes = array_key_exists('sedes', $d) && $actual['rol'] === null && !$esAdmin;
        $sedes = $tocaSedes ? self::validarSedes($d['sedes'], $yo) : self::sedesDe((int) $actual['id']);
        if (!$esAdmin) {
            self::validarSedesDelRol($rol, $sedes, $actual['rol'] !== null);
        }
        $nombre = $actual['nombre'];
        if (array_key_exists('nombre', $d) && $actual['empleado_id'] === null) {
            $nombre = self::validarNombre($d['nombre']);
        }

        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            Db::query('UPDATE usuarios SET nombre = ?, rol_asistencia = ?, activo = ? WHERE id = ?',
                [$nombre, $rol, $activo, $actual['id']]);
            if ($tocaSedes) {
                self::fijarSedes((int) $actual['id'], $sedes);
            }
            if ($activo === 0) {
                // Inactivar la cuenta la saca de las dos apps.
                Db::query('UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP(3) WHERE usuario_id = ? AND revoked_at IS NULL', [$actual['id']]);
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        Response::json(['usuario' => self::aJson(self::buscar((int) $actual['id'], $yo))]);
    }

    /**
     * Quitar el acceso a Presente. Si también entra a Ventario, solo pierde
     * Presente; si no, la cuenta se da de baja y el empleado sigue existiendo.
     */
    public static function quitar(Request $req): never
    {
        $yo = Auth::adminEmpresa($req);
        $u = self::buscar($req->param('id'), $yo);
        if ($u['rol_asistencia'] === Auth::ROL_ADMIN) {
            throw HttpError::validacion('Al administrador no se le quita el acceso');
        }
        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            if ($u['rol'] !== null) {
                Db::query('UPDATE usuarios SET rol_asistencia = NULL, pausa_asistencia = 0 WHERE id = ?', [$u['id']]);
            } else {
                Db::query('UPDATE usuarios SET deleted_at = UTC_TIMESTAMP(3), activo = 0 WHERE id = ?', [$u['id']]);
                Db::query('UPDATE asis_empleados SET usuario_id = NULL WHERE usuario_id = ?', [$u['id']]);
                Db::query('UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP(3) WHERE usuario_id = ? AND revoked_at IS NULL', [$u['id']]);
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        Response::sinContenido();
    }

    /**
     * Pausa o reactiva una cuenta en Presente (el plan no alcanza para todos).
     * Reactivar exige cupo: LIMITE_PLAN → 409. Al administrador no se le pausa.
     */
    public static function pausar(Request $req): never
    {
        $yo = Auth::adminEmpresa($req);
        $u = self::buscar($req->param('id'), $yo);
        $pausada = (bool) ($req->json()['pausada'] ?? true);
        if ($pausada && $u['rol_asistencia'] === Auth::ROL_ADMIN) {
            throw HttpError::validacion('Al administrador no se le pausa');
        }
        Db::query('UPDATE usuarios SET pausa_asistencia = ? WHERE id = ?', [$pausada ? 1 : 0, $u['id']]);
        Response::json(['usuario' => self::aJson(self::buscar((int) $u['id'], $yo))]);
    }

    // ---------------------------------------------------------------------

    /** Inserta la cuenta con contraseña al azar (nadie la conoce). */
    private static function insertarCuenta(int $empresaId, string $nombre, ?string $documento, string $email,
                                           ?string $telefono, string $rol, ?int $fichaId): int
    {
        // El correo es la identidad para entrar: único en TODA la plataforma.
        if (Db::valor('SELECT 1 FROM usuarios WHERE email = ?', [$email]) !== null) {
            throw new HttpError(409, 'Ya hay una cuenta con ese correo', ['campo' => 'email', 'codigo' => 'EMAIL_EN_USO']);
        }
        // Si el empleado ya ocupaba su cupo, el trigger no lo cuenta dos veces.
        Db::query('SET @cupo_vincula_empleado = ?', [$fichaId]);
        try {
            Db::query(
                'INSERT INTO usuarios (uuid, empresa_id, nombre, documento, email, telefono, password_hash, rol, rol_asistencia)
                 VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)',
                [Ids::uuid(), $empresaId, $nombre, $documento, $email, $telefono,
                 Auth::hashPassword(bin2hex(random_bytes(24))), $rol],
            );
        } finally {
            Db::query('SET @cupo_vincula_empleado = NULL');
        }
        return (int) Db::pdo()->lastInsertId();
    }

    /** Aviso de acceso, sin contraseña. Si el correo falla la cuenta queda igual. */
    private static function avisarAcceso(string $email, string $nombre): bool
    {
        try {
            Correo::enviar(
                $email,
                'Ya tienes acceso a Presente',
                "Hola, $nombre.\n\n"
                . "Tu empresa te dio acceso a Presente con este correo.\n\n"
                . "Para entrar por primera vez:\n"
                . "  1. Abre la app Presente y toca «Iniciar sesión».\n"
                . "  2. Toca «¿Olvidaste tu contraseña?» y escribe este correo.\n"
                . "  3. Te llegará un código para crear tu contraseña.\n\n"
                . "Si no esperabas este correo, ignóralo.\n",
            );
            return true;
        } catch (\Throwable $e) {
            error_log('[asistencia] No se pudo enviar el aviso de acceso: ' . $e->getMessage());
            return false;
        }
    }

    private static function aJson(array $u): array
    {
        $sedes = array_values(array_filter(array_map('intval', explode(',', (string) ($u['sedes'] ?? '')))));
        return [
            'id'               => (int) $u['id'],
            'uuid'             => $u['uuid'],
            'nombre'           => $u['nombre'],
            'documento'        => $u['documento'],
            'email'            => $u['email'],
            'telefono'         => $u['telefono'] ?? null,
            'usuario'          => $u['email'],
            'rol'              => $u['rol_asistencia'] === null ? null
                : ($u['rol_asistencia'] === Auth::ROL_OPERARIO ? Auth::GENERAL : Auth::ADMINISTRATIVO),
            'rol_asistencia'   => $u['rol_asistencia'],
            // Si también entra a Ventario (su rol allá lo gestiona Ventario).
            'rol_inventario'   => $u['rol'],
            'empleado_id'      => $u['empleado_id'] === null ? null : (int) $u['empleado_id'],
            'sedes'            => $sedes,
            'activo'           => (int) $u['activo'] === 1,
            'pausa_asistencia' => (int) ($u['pausa_asistencia'] ?? 0) === 1,
        ];
    }

    private static function buscar(int $id, array $admin): array
    {
        return Db::fila(
            self::SELECT . ' WHERE u.id = ? AND u.empresa_id = ? AND u.deleted_at IS NULL',
            [$id, $admin['empresa_id']],
        ) ?? throw HttpError::noEncontrado('Usuario');
    }

    /** @return array<int> */
    private static function sedesDe(int $usuarioId): array
    {
        return array_map('intval', array_column(
            Db::filas('SELECT sede_id FROM usuario_sedes WHERE usuario_id = ? ORDER BY sede_id', [$usuarioId]),
            'sede_id',
        ));
    }

    private static function fijarSedes(int $usuarioId, array $sedes): void
    {
        Db::query('DELETE FROM usuario_sedes WHERE usuario_id = ?', [$usuarioId]);
        foreach ($sedes as $sedeId) {
            Db::query('INSERT INTO usuario_sedes (usuario_id, sede_id) VALUES (?, ?)', [$usuarioId, $sedeId]);
        }
        Db::query('UPDATE usuarios SET updated_at = UTC_TIMESTAMP(3) WHERE id = ?', [$usuarioId]);
    }

    /** Roles de la app anterior → rol de Presente. */
    private static function rolLegado(mixed $rol): mixed
    {
        return match ($rol) {
            Auth::GENERAL => Auth::ROL_OPERARIO,
            'OPERADOR'    => Auth::ROL_OPERARIO,
            default       => $rol,
        };
    }

    private static function validarRol(mixed $v): string
    {
        if (!in_array($v, self::ROLES_ASIGNABLES, true)) {
            throw HttpError::validacion('Elige un rol de Presente: gerente, talento humano u operario', 'rol_asistencia');
        }
        return $v;
    }

    /** @return array<int> sedes de Presente que gestiona el administrador. */
    private static function validarSedes(mixed $v, array $admin): array
    {
        if (!is_array($v)) {
            throw HttpError::validacion('Sedes inválidas', 'sedes');
        }
        $ids = array_values(array_unique(array_map('intval', $v)));
        foreach ($ids as $id) {
            Auth::exigirSede($admin, $id);
        }
        return $ids;
    }

    /**
     * El gerente necesita al menos una sede. Talento humano y operario son de
     * todas las sedes: no se les asignan (salvo las que ya tenga por Ventario).
     */
    private static function validarSedesDelRol(string $rol, array $sedes, bool $conVentario = false): void
    {
        $error = match (true) {
            $rol === Auth::ROL_GERENTE && $sedes === []
                => $conVentario ? 'Para ser gerente necesita sedes: asígnaselas en Ventario' : 'Un gerente necesita al menos una sede',
            $rol !== Auth::ROL_GERENTE && $sedes !== [] && !$conVentario
                => 'Talento humano y operario trabajan en todas las sedes: no se les asignan sedes',
            default => null,
        };
        if ($error !== null) {
            throw HttpError::validacion($error, 'sedes');
        }
    }

    private static function validarEmail(mixed $v): string
    {
        $e = mb_strtolower(trim((string) $v));
        if (!filter_var($e, FILTER_VALIDATE_EMAIL) || strlen($e) > 191) {
            throw HttpError::validacion('Escribe un correo válido: con él entra a la app', 'email');
        }
        return $e;
    }

    private static function validarNombre(mixed $v): string
    {
        $n = trim(preg_replace('/\s+/u', ' ', (string) $v));
        if (mb_strlen($n) < 3 || mb_strlen($n) > 120) {
            throw HttpError::validacion('Escribe el nombre completo', 'nombre');
        }
        return $n;
    }
}
