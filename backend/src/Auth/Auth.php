<?php
declare(strict_types=1);

namespace App\Auth;

use App\Config;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Servicios\Horarios;
use App\Servicios\Tiempo;

/**
 * Credenciales en la plataforma multiempresa:
 *
 *  - Personas (JWT en `Authorization: Bearer …`). Una sola tabla `usuarios`
 *    para Inventario y Control de Personal; en esta app cuenta `rol_asistencia`:
 *      ADMIN          → todo dentro de su empresa (sedes, personal, horarios,
 *                       reportes, cuentas, teléfonos). También en Ventario.
 *      GERENTE        → personal, horarios y reportes de SUS sedes (las mismas
 *                       que en Ventario).
 *      TALENTO_HUMANO → personal, rostros, horarios, reportes y teléfonos de
 *                       marcación de todas las sedes; no cuentas, sedes ni plan.
 *      OPERARIO       → una cuenta para todas las sedes: solo vincula los
 *                       teléfonos de marcación. Nunca entra al panel.
 *    Solo cuentan las sedes ELEGIDAS para Presente. Inactivar la cuenta la saca
 *    de las dos apps; una cuenta en pausa por el plan no entra a esta.
 *
 *    Hacia la app: ADMIN, GERENTE y TALENTO_HUMANO se presentan como
 *    ADMINISTRATIVO (con `sedes` acotando al gerente) y OPERARIO como GENERAL.
 *    `rol_asistencia` va aparte para afinar permisos.
 *
 *  - Superadministrador de la plataforma (`es_superadmin`): sin empresa; solo
 *    entra al panel de plataforma (`Auth::superadmin`).
 *
 *  - Dispositivo (kiosco): token opaco en `X-Dispositivo`; en la BD solo su
 *    SHA-256. Pertenece a una sede, y por ella a una empresa.
 */
final class Auth
{
    public const GENERAL = 'GENERAL';
    public const ADMINISTRATIVO = 'ADMINISTRATIVO';

    public const ROL_ADMIN = 'ADMIN';
    public const ROL_GERENTE = 'GERENTE';
    /** Personal, rostros, turnos, reportes y teléfonos de marcación, en todas las sedes. */
    public const ROL_TALENTO_HUMANO = 'TALENTO_HUMANO';
    /**
     * Cuenta de los teléfonos de marcación: UNA para todas las sedes. Solo
     * vincula teléfonos; nunca entra al panel (en la app es «GENERAL»).
     */
    public const ROL_OPERARIO = 'OPERARIO';
    public const ROLES_ASISTENCIA = [self::ROL_ADMIN, self::ROL_GERENTE, self::ROL_TALENTO_HUMANO, self::ROL_OPERARIO];

    /**
     * Cualquier persona autenticada de una empresa (GENERAL o ADMINISTRATIVO).
     * @return array{id:int, uuid:string, nombre:string, email:string, rol:string,
     *               rol_asistencia:string, rol_inventario:?string, empresa_id:int, sedes:array<int>}
     *   `sedes` son SIEMPRE ids de la empresa: todas para el ADMIN, las suyas
     *   para el GERENTE. Nunca «todas las de la base».
     */
    public static function persona(Request $req): array
    {
        $datos = self::token($req);
        if (!empty($datos['sa'])) {
            throw new HttpError(403, 'El superadministrador entra solo al panel de plataforma');
        }
        // Se revalida en cada petición: si desactivan la cuenta o la empresa,
        // la sesión muere ya, no cuando venza el token.
        $persona = self::cargar((int) $datos['sub']);
        if ($persona === null) {
            throw HttpError::noAutorizado('Tu usuario ya no tiene acceso');
        }
        return $persona;
    }

    /** ADMIN o GERENTE (administrativos). El gerente queda acotado a sus sedes. */
    public static function admin(Request $req): array
    {
        $persona = self::persona($req);
        if ($persona['rol'] !== self::ADMINISTRATIVO) {
            throw new HttpError(403, 'Esta opción es solo para usuarios administrativos');
        }
        return $persona;
    }

    /** Solo el ADMIN de la empresa (sedes, cuentas, turnos, datos de la empresa). */
    public static function adminEmpresa(Request $req): array
    {
        $persona = self::persona($req);
        if ($persona['rol_asistencia'] !== self::ROL_ADMIN) {
            throw new HttpError(403, 'Esta opción es solo para el administrador de la empresa');
        }
        return $persona;
    }

    /** Superadministrador de la plataforma. */
    public static function superadmin(Request $req): array
    {
        $datos = self::token($req);
        $u = Db::fila(
            'SELECT id, nombre, email FROM usuarios
              WHERE id = ? AND es_superadmin = 1 AND activo = 1 AND deleted_at IS NULL',
            [(int) $datos['sub']],
        );
        if ($u === null || empty($datos['sa'])) {
            throw new HttpError(403, 'Solo para el equipo de la plataforma');
        }
        return ['id' => (int) $u['id'], 'nombre' => (string) $u['nombre'], 'email' => (string) $u['email']];
    }

    private static function token(Request $req): array
    {
        $token = $req->bearer();
        $datos = $token !== null ? Jwt::verificar($token, (string) Config::get('jwt_secret')) : null;
        if ($datos === null || !isset($datos['sub'])) {
            throw HttpError::noAutorizado();
        }
        return $datos;
    }

    /**
     * Busca y valida credenciales. Devuelve la persona o null si la contraseña
     * no coincide. Con la contraseña correcta sí se explica por qué no entra
     * (cuenta inactiva, empresa suspendida, app no habilitada, sin rol aquí):
     * es la misma persona y saberlo le ahorra una llamada.
     *
     * @return array|null  persona, o ['superadmin' => true, 'id' => …] para el panel de plataforma
     */
    public static function autenticar(string $email, string $password): ?array
    {
        $u = Db::fila(
            'SELECT id, password_hash, es_superadmin FROM usuarios WHERE email = ? AND deleted_at IS NULL LIMIT 1',
            [$email],
        );
        if ($u === null || !self::verificarPassword($password, (string) $u['password_hash'])) {
            return null;
        }
        if ((int) $u['es_superadmin'] === 1) {
            return ['superadmin' => true, 'id' => (int) $u['id']];
        }
        return self::cargar((int) $u['id'], true);
    }

    /**
     * Cuenta + empresa + permisos. Con `$explicar`, lanza el motivo exacto por
     * el que no puede entrar; sin él (cada petición), solo devuelve null.
     */
    private static function cargar(int $id, bool $explicar = false): ?array
    {
        $u = Db::fila(
            "SELECT u.id, u.uuid, u.nombre, u.email, u.rol AS rol_inventario, u.rol_asistencia,
                    u.activo, u.pausa_asistencia, u.empresa_id, e.estado AS empresa_estado, e.deleted_at AS empresa_borrada,
                    e.zona_horaria, ea.activo AS app_habilitada
               FROM usuarios u
               LEFT JOIN empresas e ON e.id = u.empresa_id
               LEFT JOIN empresa_aplicativos ea ON ea.empresa_id = u.empresa_id AND ea.aplicativo = 'ASISTENCIA'
              WHERE u.id = ? AND u.deleted_at IS NULL AND u.es_superadmin = 0",
            [$id],
        );
        $motivo = match (true) {
            $u === null                         => ['Tu usuario ya no existe', 'USUARIO_INEXISTENTE'],
            (int) $u['activo'] !== 1            => ['Tu usuario está inactivo', 'CUENTA_DESACTIVADA'],
            $u['empresa_id'] === null || $u['empresa_borrada'] !== null
                                                => ['Tu empresa ya no está registrada en la plataforma', 'EMPRESA_INEXISTENTE'],
            $u['empresa_estado'] !== 'ACTIVA'   => ['Tu empresa está suspendida. Comunícate con el equipo de la plataforma.', 'EMPRESA_SUSPENDIDA'],
            (int) ($u['app_habilitada'] ?? 0) !== 1
                                                => ['Tu empresa no tiene habilitado Control de Personal', 'APP_NO_HABILITADA'],
            $u['rol_asistencia'] === null       => ['Tu cuenta no tiene acceso a Presente. Pídeselo al administrador de tu empresa.', 'SIN_ACCESO_APP'],
            (int) $u['pausa_asistencia'] === 1  => ['Tu cuenta está en pausa en Presente porque el plan de tu empresa no alcanza para todos. Pídele al administrador que te active.', 'SIN_ACCESO_APP'],
            default                             => null,
        };
        if ($motivo !== null) {
            if ($explicar) {
                throw new HttpError(403, $motivo[0], ['codigo' => $motivo[1]]);
            }
            return null;
        }

        $empresaId = (int) $u['empresa_id'];
        Tiempo::usarZona((string) $u['zona_horaria']);
        Horarios::usarEmpresa($empresaId);
        $rolAsis = (string) $u['rol_asistencia'];
        return [
            'id'             => (int) $u['id'],
            'uuid'           => (string) $u['uuid'],
            'nombre'         => (string) $u['nombre'],
            'email'          => (string) $u['email'],
            'rol'            => $rolAsis === self::ROL_OPERARIO ? self::GENERAL : self::ADMINISTRATIVO,
            'rol_asistencia' => $rolAsis,
            'rol_inventario' => $u['rol_inventario'],
            'empresa_id'     => $empresaId,
            'sedes'          => self::sedesDe((int) $u['id'], $empresaId, $rolAsis),
        ];
    }

    /**
     * Sedes del alcance: solo las ELEGIDAS para Presente (sede_aplicativos),
     * hasta el límite de su plan. El ADMIN, TALENTO_HUMANO y el OPERARIO (los
     * teléfonos de marcación) ven todas esas; el GERENTE, las suyas.
     * @return array<int>
     */
    private static function sedesDe(int $usuarioId, int $empresaId, string $rol): array
    {
        if ($rol === self::ROL_GERENTE) {
            $filas = Db::filas(
                "SELECT us.sede_id FROM usuario_sedes us
                   JOIN sedes s ON s.id = us.sede_id AND s.empresa_id = ? AND s.deleted_at IS NULL
                   JOIN sede_aplicativos sa ON sa.sede_id = s.id AND sa.aplicativo = 'ASISTENCIA'
                  WHERE us.usuario_id = ?",
                [$empresaId, $usuarioId],
            );
        } else {
            $filas = Db::filas(
                "SELECT s.id AS sede_id FROM sedes s
                   JOIN sede_aplicativos sa ON sa.sede_id = s.id AND sa.aplicativo = 'ASISTENCIA'
                  WHERE s.empresa_id = ?",
                [$empresaId],
            );
        }
        return array_map('intval', array_column($filas, 'sede_id'));
    }

    /** ¿La sede está elegida para Presente? */
    public static function sedeElegida(int $sedeId): bool
    {
        return Db::fila(
            "SELECT 1 AS x FROM sede_aplicativos WHERE sede_id = ? AND aplicativo = 'ASISTENCIA'",
            [$sedeId],
        ) !== null;
    }

    /** Talento humano: personal y teléfonos sí; cuentas, sedes y plan no. */
    public static function esTalentoHumano(array $persona): bool
    {
        return $persona['rol_asistencia'] === self::ROL_TALENTO_HUMANO;
    }

    /** @return array{id:int, nombre:string, sede_id:int, sede_nombre:string, sede_codigo:string, empresa_id:int} */
    public static function dispositivo(Request $req): array
    {
        $token = $req->header('X-Dispositivo');
        if ($token === null || strlen($token) < 32) {
            throw HttpError::noAutorizado('Dispositivo no registrado');
        }
        $disp = Db::fila(
            "SELECT d.id, d.nombre, d.codigo, d.sede_id, s.nombre AS sede_nombre, s.codigo AS sede_codigo,
                    s.empresa_id, e.estado AS empresa_estado, e.deleted_at AS empresa_borrada,
                    e.zona_horaria, ea.activo AS app_habilitada,
                    (SELECT 1 FROM sede_aplicativos sa
                      WHERE sa.sede_id = d.sede_id AND sa.aplicativo = 'ASISTENCIA') AS sede_elegida,
                    v.activo AS vinculador_activo, v.deleted_at AS vinculador_borrado, d.vinculado_por
               FROM asis_dispositivos d
               JOIN sedes s ON s.id = d.sede_id
               JOIN empresas e ON e.id = s.empresa_id
               LEFT JOIN empresa_aplicativos ea ON ea.empresa_id = e.id AND ea.aplicativo = 'ASISTENCIA'
               LEFT JOIN usuarios v ON v.id = d.vinculado_por
              WHERE d.token_hash = ? AND d.activo = 1",
            [hash('sha256', $token)],
        );
        // El teléfono de marcación no caduca: solo deja de funcionar si lo
        // desvinculan, si inactivan la cuenta que lo vinculó (p. ej. el
        // operario) o si la sede deja de estar en Presente.
        if ($disp === null
            || ($disp['vinculado_por'] !== null && ((int) $disp['vinculador_activo'] !== 1 || $disp['vinculador_borrado'] !== null))) {
            throw new HttpError(401, 'Este dispositivo fue desvinculado', ['codigo' => 'DISPOSITIVO_REVOCADO']);
        }
        if ($disp['sede_elegida'] === null) {
            throw new HttpError(403, 'Esta sede ya no está en el plan de Presente de tu empresa', ['codigo' => 'SEDE_FUERA_DEL_PLAN']);
        }
        if ($disp['empresa_borrada'] !== null || $disp['empresa_estado'] !== 'ACTIVA') {
            throw new HttpError(403, 'La empresa de este kiosco está suspendida', ['codigo' => 'EMPRESA_SUSPENDIDA']);
        }
        if ((int) ($disp['app_habilitada'] ?? 0) !== 1) {
            throw new HttpError(403, 'La empresa no tiene habilitado Control de Personal', ['codigo' => 'APP_NO_HABILITADA']);
        }
        Tiempo::usarZona((string) $disp['zona_horaria']);
        Horarios::usarEmpresa((int) $disp['empresa_id']);
        return [
            'id'          => (int) $disp['id'],
            'nombre'      => (string) $disp['nombre'],
            'codigo'      => (string) ($disp['codigo'] ?? ''),
            'sede_id'     => (int) $disp['sede_id'],
            'sede_nombre' => (string) $disp['sede_nombre'],
            'sede_codigo' => (string) $disp['sede_codigo'],
            'empresa_id'  => (int) $disp['empresa_id'],
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
        return in_array($sedeId, $persona['sedes'], true);
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
