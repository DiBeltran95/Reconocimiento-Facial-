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
 * La PERSONA vive una sola vez, en `empleados` (nombre, documento, correo,
 * teléfono, cargo, sede), para las dos apps. La cuenta (`usuarios`) solo dice
 * a qué empleado pertenece (`empleado_id`), su contraseña, sus roles y su
 * alcance; se lee con la vista `v_usuarios`. Aquí se le da acceso a PRESENTE
 * con un rol: GERENTE (sus sedes), TALENTO_HUMANO (todas) u OPERARIO. Su rol
 * en Ventario no se toca; la única regla común es que el administrador
 * (dueño) lo es en las dos (ck_usuarios_roles).
 *
 *   · Si el empleado ya tiene cuenta (de Ventario), solo se le agrega Presente:
 *     entra con el mismo correo y contraseña.
 *   · Si no tiene, se crea con contraseña al azar y se le avisa por correo que
 *     cree la suya con «¿Olvidaste tu contraseña?». Si tuvo una y se dio de
 *     baja, se reactiva la misma (su historial sigue a su nombre).
 *   · El OPERARIO es una cuenta técnica (los teléfonos de marcación), sin
 *     empleado: guarda su propio nombre y correo y no ocupa cupo de personas.
 *
 * La pausa de Presente es la del EMPLEADO (`empleados.en_pausa`): no marca ni
 * entra. Las sedes de la cuenta (usuario_sedes) son las mismas en las dos
 * apps: si la persona ya trabaja en Ventario, se gestionan allá.
 *
 * Ojo: un UPDATE de `empleados` no puede cruzarse con `usuarios` (JOIN o
 * subconsulta): su trigger marca la cuenta como modificada.
 */
final class UsuariosControlador
{
    /** Roles que se dan desde Presente (el administrador es el dueño, no se asigna). */
    private const ROLES_ASIGNABLES = [Auth::ROL_GERENTE, Auth::ROL_TALENTO_HUMANO, Auth::ROL_OPERARIO];

    private const SELECT = "SELECT u.id, u.uuid, u.empleado_id, u.nombre, u.documento, u.email, u.telefono,
                                   u.rol, u.rol_asistencia, u.activo, u.pausa_asistencia, u.created_at,
                                   (SELECT GROUP_CONCAT(us.sede_id ORDER BY us.sede_id) FROM usuario_sedes us
                                     WHERE us.usuario_id = u.id) AS sedes
                              FROM v_usuarios u";

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
        $where = ['e.empresa_id = ?', 'e.activo = 1',
                  '(u.id IS NULL OR u.deleted_at IS NOT NULL OR u.rol_asistencia IS NULL)',
                  'e.sede_id IN (' . Db::enLista($admin['sedes']) . ')'];
        $params = [$admin['empresa_id'], ...$admin['sedes']];
        $q = trim((string) $req->query('q', ''));
        if ($q !== '') {
            $where[] = '(e.nombre LIKE ? OR e.documento LIKE ?)';
            array_push($params, "%$q%", "%$q%");
        }
        $filas = Db::filas(
            'SELECT e.id, e.documento, e.nombre, e.cargo, e.telefono, e.email, e.sede_id,
                    s.nombre AS sede, (u.id IS NOT NULL AND u.deleted_at IS NULL) AS con_cuenta
               FROM empleados e
               JOIN sedes s ON s.id = e.sede_id
               LEFT JOIN usuarios u ON u.empleado_id = e.id
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
     * Con empleado_id: acceso a Presente para ese empleado (`email` solo si su
     * ficha aún no tiene correo). Sin él: solo el OPERARIO (cuenta técnica)
     * con nombre y correo propios.
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
                [$id, $nueva] = self::accesoDeEmpleado($admin, $empleadoId, $rol, $d);
            } else {
                if ($rol !== Auth::ROL_OPERARIO) {
                    throw HttpError::validacion('Elige el empleado al que le das acceso', 'empleado_id');
                }
                $email = self::validarEmail($d['email'] ?? '');
                self::exigirCorreoLibre($email);
                Db::query(
                    'INSERT INTO usuarios (uuid, empresa_id, nombre, email, password_hash, rol, rol_asistencia)
                     VALUES (?, ?, ?, ?, ?, NULL, ?)',
                    [Ids::uuid(), $admin['empresa_id'], self::validarNombre($d['nombre'] ?? ''), $email,
                     self::claveAlAzar(), $rol],
                );
                $id = (int) $pdo->lastInsertId();
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

    /**
     * Da acceso a Presente a un empleado, dentro de la transacción de crear.
     * @return array{0:int, 1:bool}  [id de la cuenta, ¿cuenta nueva (o reactivada)?]
     */
    private static function accesoDeEmpleado(array $admin, int $empleadoId, string $rol, array $d): array
    {
        $ficha = Db::fila(
            'SELECT e.id, e.sede_id, e.email, u.id AS usuario_id, u.rol AS usuario_rol,
                    u.rol_asistencia AS usuario_rol_asistencia, u.deleted_at AS cuenta_borrada
               FROM empleados e
               LEFT JOIN usuarios u ON u.empleado_id = e.id
              WHERE e.id = ? AND e.empresa_id = ? AND e.activo = 1',
            [$empleadoId, $admin['empresa_id']],
        ) ?? throw HttpError::noEncontrado('Empleado');
        Auth::exigirSede($admin, (int) $ficha['sede_id']);

        $viva = $ficha['usuario_id'] !== null && $ficha['cuenta_borrada'] === null;
        if ($viva && $ficha['usuario_rol_asistencia'] !== null) {
            throw new HttpError(409, 'Ese empleado ya tiene acceso a Presente', ['codigo' => 'YA_TIENE_ACCESO']);
        }

        if ($viva) {
            // Ya entra a Ventario: se le agrega Presente con su misma cuenta.
            $id = (int) $ficha['usuario_id'];
            $conVentario = $ficha['usuario_rol'] !== null;
            $sedes = $conVentario ? self::sedesDe($id) : self::validarSedes($d['sedes'] ?? [], $admin);
            self::validarSedesDelRol($rol, $sedes, $conVentario);
            Db::query('UPDATE usuarios SET rol_asistencia = ? WHERE id = ?', [$rol, $id]);
            if (!$conVentario) {
                self::fijarSedes($id, $sedes);
            }
            return [$id, false];
        }

        // Sin cuenta: entra con el correo de su ficha (se completa si no tenía).
        $email = $ficha['email'] ?? self::validarEmail($d['email'] ?? '');
        if ($ficha['email'] === null) {
            self::exigirCorreoLibre($email, (int) $ficha['id']);
            Db::query('UPDATE empleados SET email = ? WHERE id = ? AND empresa_id = ?',
                [$email, $ficha['id'], $admin['empresa_id']]);
        }
        $sedes = self::validarSedes($d['sedes'] ?? [], $admin);
        self::validarSedesDelRol($rol, $sedes);

        if ($ficha['usuario_id'] !== null) {
            // Tuvo cuenta y se dio de baja: se reactiva la misma.
            $id = (int) $ficha['usuario_id'];
            Db::query(
                'UPDATE usuarios SET password_hash = ?, rol = NULL, rol_asistencia = ?, activo = 1,
                        deleted_at = NULL, pausa_inventario = 0
                  WHERE id = ?',
                [self::claveAlAzar(), $rol, $id],
            );
        } else {
            Db::query(
                'INSERT INTO usuarios (uuid, empresa_id, empleado_id, password_hash, rol, rol_asistencia)
                 VALUES (?, ?, ?, ?, NULL, ?)',
                [Ids::uuid(), $admin['empresa_id'], $ficha['id'], self::claveAlAzar(), $rol],
            );
            $id = (int) Db::pdo()->lastInsertId();
        }
        self::fijarSedes($id, $sedes);
        return [$id, true];
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

        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            Db::query('UPDATE usuarios SET rol_asistencia = ?, activo = ? WHERE id = ?', [$rol, $activo, $actual['id']]);
            // El nombre es de la persona (se edita en Personal); solo la cuenta
            // técnica del operario tiene uno propio.
            if (array_key_exists('nombre', $d) && $actual['empleado_id'] === null) {
                Db::query('UPDATE usuarios SET nombre = ? WHERE id = ?', [self::validarNombre($d['nombre']), $actual['id']]);
            }
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
     * Presente; si no, la cuenta se da de baja y el empleado sigue existiendo
     * (si se le vuelve a dar acceso, se reactiva esta misma cuenta).
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
                Db::query('UPDATE usuarios SET rol_asistencia = NULL WHERE id = ?', [$u['id']]);
            } else {
                Db::query('UPDATE usuarios SET deleted_at = UTC_TIMESTAMP(3), activo = 0 WHERE id = ?', [$u['id']]);
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
     * Pausa o reactiva a la PERSONA en Presente (el plan no alcanza para
     * todos): no marca ni entra a Presente. Reactivar exige cupo: LIMITE_PLAN
     * → 409. Al administrador no se le pausa; el operario no es una persona.
     */
    public static function pausar(Request $req): never
    {
        $yo = Auth::adminEmpresa($req);
        $u = self::buscar($req->param('id'), $yo);
        $pausada = (bool) ($req->json()['pausada'] ?? true);
        if ($pausada && $u['rol_asistencia'] === Auth::ROL_ADMIN) {
            throw HttpError::validacion('Al administrador no se le pausa');
        }
        if ($u['empleado_id'] === null) {
            throw HttpError::validacion('La cuenta del operario no ocupa cupo: no se pausa');
        }
        Db::query('UPDATE empleados SET en_pausa = ? WHERE id = ? AND empresa_id = ?',
            [$pausada ? 1 : 0, $u['empleado_id'], $yo['empresa_id']]);
        Response::json(['usuario' => self::aJson(self::buscar((int) $u['id'], $yo))]);
    }

    // ---------------------------------------------------------------------

    /** Contraseña inicial al azar (nadie la conoce): la persona crea la suya. */
    private static function claveAlAzar(): string
    {
        return Auth::hashPassword(bin2hex(random_bytes(24)));
    }

    /**
     * El correo es con lo que se entra a la plataforma: no puede tenerlo otra
     * persona ni una cuenta técnica. La base lo exige igual (EMAIL_EN_USO).
     */
    private static function exigirCorreoLibre(string $email, ?int $empleadoId = null): void
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
            'telefono'         => $u['telefono'],
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

    /** Gerente: al menos una sede. Talento humano y operario: todas (ninguna asignada). */
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
