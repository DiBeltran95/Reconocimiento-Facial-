<?php
declare(strict_types=1);

namespace App\Auth;

use App\Config;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;

/**
 * Credenciales:
 *  - Personas (JWT en `Authorization: Bearer …`), con dos roles:
 *      GENERAL         → vincula y opera kioscos en cualquier sede.
 *      ADMINISTRATIVO  → todo: personal, horarios, cumplimiento, usuarios.
 *    Las cuentas viven en `asis_usuarios`. Además, los ADMIN / GERENTE de la
 *    tabla existente `usuarios` (solo lectura) entran como ADMINISTRATIVO.
 *  - Dispositivo (kiosco): token opaco en `X-Dispositivo`; en la BD solo su SHA-256.
 */
final class Auth
{
    public const GENERAL = 'GENERAL';
    public const ADMINISTRATIVO = 'ADMINISTRATIVO';

    /** Origen de la cuenta dentro del JWT. */
    public const ORIGEN_ASISTENCIA = 'a';
    public const ORIGEN_INVENTARIO = 'i';

    /**
     * Cualquier persona autenticada (GENERAL o ADMINISTRATIVO).
     * @return array{id:int, nombre:string, rol:string, origen:string, sedes:?array<int>}
     *         `sedes` = null significa "todas las sedes".
     */
    public static function persona(Request $req): array
    {
        $token = $req->bearer();
        $datos = $token !== null ? Jwt::verificar($token, (string) Config::get('jwt_secret')) : null;
        if ($datos === null || !isset($datos['sub'], $datos['org'])) {
            throw HttpError::noAutorizado();
        }
        // Se revalida en cada petición: si desactivan la cuenta, la sesión muere ya.
        $persona = $datos['org'] === self::ORIGEN_ASISTENCIA
            ? self::cuentaAsistencia((int) $datos['sub'])
            : self::cuentaInventario((int) $datos['sub']);
        if ($persona === null) {
            throw HttpError::noAutorizado('Tu usuario ya no tiene acceso');
        }
        return $persona;
    }

    /** Solo administrativos. */
    public static function admin(Request $req): array
    {
        $persona = self::persona($req);
        if ($persona['rol'] !== self::ADMINISTRATIVO) {
            throw new HttpError(403, 'Esta opción es solo para usuarios administrativos');
        }
        return $persona;
    }

    /** Busca y valida credenciales. Devuelve la persona o null. */
    public static function autenticar(string $usuario, string $password): ?array
    {
        $cuenta = Db::fila(
            'SELECT id, password_hash, activo FROM asis_usuarios WHERE usuario = ?',
            [$usuario],
        );
        if ($cuenta !== null) {
            if (!self::verificarPassword($password, (string) $cuenta['password_hash'])) {
                return null;
            }
            if ((int) $cuenta['activo'] !== 1) {
                throw new HttpError(403, 'Tu usuario está inactivo');
            }
            return self::cuentaAsistencia((int) $cuenta['id']);
        }

        // Respaldo: administradores del sistema de inventarios (solo lectura).
        $inv = Db::fila(
            'SELECT id, password_hash, activo, rol FROM usuarios WHERE email = ? AND deleted_at IS NULL LIMIT 1',
            [$usuario],
        );
        if ($inv === null || !self::verificarPassword($password, (string) $inv['password_hash'])) {
            return null;
        }
        if ((int) $inv['activo'] !== 1) {
            throw new HttpError(403, 'Tu usuario está inactivo');
        }
        if (!in_array($inv['rol'], Config::get('roles_admin', []), true)) {
            throw new HttpError(403, 'Tu rol no tiene acceso al control de asistencia');
        }
        return self::cuentaInventario((int) $inv['id']);
    }

    private static function cuentaAsistencia(int $id): ?array
    {
        $u = Db::fila('SELECT id, nombre, rol FROM asis_usuarios WHERE id = ? AND activo = 1', [$id]);
        if ($u === null) {
            return null;
        }
        return [
            'id'     => (int) $u['id'],
            'nombre' => (string) $u['nombre'],
            'rol'    => (string) $u['rol'],
            'origen' => self::ORIGEN_ASISTENCIA,
            'sedes'  => null,
        ];
    }

    private static function cuentaInventario(int $id): ?array
    {
        $u = Db::fila(
            'SELECT id, nombre, rol FROM usuarios WHERE id = ? AND activo = 1 AND deleted_at IS NULL',
            [$id],
        );
        if ($u === null || !in_array($u['rol'], Config::get('roles_admin', []), true)) {
            return null;
        }
        $sedes = null;
        if ($u['rol'] !== 'ADMIN') {
            $sedes = array_map('intval', array_column(
                Db::filas('SELECT sede_id FROM usuario_sedes WHERE usuario_id = ?', [$u['id']]),
                'sede_id',
            ));
        }
        return [
            'id'     => (int) $u['id'],
            'nombre' => (string) $u['nombre'],
            'rol'    => self::ADMINISTRATIVO,
            'origen' => self::ORIGEN_INVENTARIO,
            'sedes'  => $sedes,
        ];
    }

    /** @return array{id:int, nombre:string, sede_id:int, sede_nombre:string, sede_codigo:string} */
    public static function dispositivo(Request $req): array
    {
        $token = $req->header('X-Dispositivo');
        if ($token === null || strlen($token) < 32) {
            throw HttpError::noAutorizado('Dispositivo no registrado');
        }
        $disp = Db::fila(
            'SELECT d.id, d.nombre, d.sede_id, s.nombre AS sede_nombre, s.codigo AS sede_codigo
               FROM asis_dispositivos d
               JOIN sedes s ON s.id = d.sede_id
              WHERE d.token_hash = ? AND d.activo = 1',
            [hash('sha256', $token)],
        );
        if ($disp === null) {
            throw new HttpError(401, 'Este dispositivo fue desvinculado', ['codigo' => 'DISPOSITIVO_REVOCADO']);
        }
        return [
            'id'          => (int) $disp['id'],
            'nombre'      => (string) $disp['nombre'],
            'sede_id'     => (int) $disp['sede_id'],
            'sede_nombre' => (string) $disp['sede_nombre'],
            'sede_codigo' => (string) $disp['sede_codigo'],
        ];
    }

    /** Acepta kiosco o administrativo (p. ej. para descargar fotos). */
    public static function adminODispositivo(Request $req): array
    {
        if ($req->header('X-Dispositivo') !== null) {
            return ['tipo' => 'dispositivo'] + self::dispositivo($req);
        }
        return ['tipo' => 'admin'] + self::admin($req);
    }

    public static function puedeSede(array $persona, int $sedeId): bool
    {
        return $persona['sedes'] === null || in_array($sedeId, $persona['sedes'], true);
    }

    public static function exigirSede(array $persona, int $sedeId): void
    {
        if (!self::puedeSede($persona, $sedeId)) {
            throw HttpError::prohibido();
        }
    }

    public static function hashPassword(string $plano): string
    {
        return password_hash($plano, defined('PASSWORD_ARGON2ID') ? PASSWORD_ARGON2ID : PASSWORD_DEFAULT);
    }

    /**
     * Verifica argon2id (incluidos los hashes del backend de inventarios) o bcrypt.
     * Si PHP no trae argon2 compilado, usa libsodium (mismo formato PHC).
     */
    public static function verificarPassword(string $plano, string $hash): bool
    {
        if (str_starts_with($hash, '$argon2') && !defined('PASSWORD_ARGON2ID')
            && function_exists('sodium_crypto_pwhash_str_verify')) {
            return sodium_crypto_pwhash_str_verify($hash, $plano);
        }
        return password_verify($plano, $hash);
    }
}
