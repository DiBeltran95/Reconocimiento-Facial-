<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Ids;
use App\Servicios\Plan;

/**
 * Cuentas de la empresa. Una cuenta es UNA persona para las dos apps, con un
 * rol en cada una:
 *   rol_asistencia  ADMIN / GERENTE / OPERADOR  (null = no entra aquí)
 *   rol_inventario  ADMIN / GERENTE / AUXILIAR_INVENTARIO / VENDEDOR (null = no
 *                   entra a Inventario; solo se ofrece si la empresa lo tiene)
 * Las sedes (usuario_sedes) son las mismas en las dos apps. Inactivar una
 * cuenta la saca de las dos. Las reglas son las de Inventario
 * (domain/alcance.js · validarSedesDeRol). Solo el administrador las gestiona.
 */
final class UsuariosControlador
{
    private const ROLES_INVENTARIO = ['ADMIN', 'GERENTE', 'AUXILIAR_INVENTARIO', 'VENDEDOR'];

    public static function listar(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        $filas = Db::filas(
            "SELECT u.id, u.uuid, u.nombre, u.documento, u.email, u.rol, u.rol_asistencia, u.activo, u.created_at,
                    GROUP_CONCAT(us.sede_id ORDER BY us.sede_id) AS sedes
               FROM usuarios u
               LEFT JOIN usuario_sedes us ON us.usuario_id = u.id
              WHERE u.empresa_id = ? AND u.deleted_at IS NULL
              GROUP BY u.id
              ORDER BY u.activo DESC, u.nombre",
            [$admin['empresa_id']],
        );
        Response::json([
            'usuarios'    => array_map([self::class, 'aJson'], $filas),
            'aplicativos' => Plan::aplicativos($admin['empresa_id']),
            'plan'        => Plan::deEmpresa($admin['empresa_id']),
        ]);
    }

    public static function crear(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        $d = $req->json();
        $nombre = self::validarNombre($d['nombre'] ?? '');
        $email = self::validarEmail($d['email'] ?? $d['usuario'] ?? '');
        $password = self::validarPassword($d['password'] ?? '');
        $rolAsis = self::validarRolAsistencia($d['rol_asistencia'] ?? self::rolLegado($d['rol'] ?? null));
        $rolInv = self::validarRolInventario($d['rol_inventario'] ?? null, $admin['empresa_id']);
        $sedes = self::validarSedes($d['sedes'] ?? [], $admin);
        self::validarCombinacion($rolInv, $rolAsis, $sedes);
        $documento = self::validarDocumento($d['documento'] ?? null);

        // El correo es la identidad para entrar: único en TODA la plataforma.
        if (Db::valor('SELECT 1 FROM usuarios WHERE email = ?', [$email]) !== null) {
            throw new HttpError(409, 'Ya hay una cuenta con ese correo', ['campo' => 'email', 'codigo' => 'EMAIL_EN_USO']);
        }

        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            // Si ya marcaba asistencia sin cuenta (mismo documento), la persona
            // ya ocupaba su cupo: el trigger no la cuenta dos veces. La variable
            // es de la conexión: se limpia pase lo que pase.
            $ficha = $documento === null ? null : Db::fila(
                'SELECT id FROM asis_empleados WHERE empresa_id = ? AND documento = ? AND usuario_id IS NULL AND activo = 1',
                [$admin['empresa_id'], $documento],
            );
            Db::query('SET @cupo_vincula_empleado = ?', [$ficha['id'] ?? null]);
            try {
                Db::query(
                    'INSERT INTO usuarios (uuid, empresa_id, nombre, documento, email, password_hash, rol, rol_asistencia)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                    [Ids::uuid(), $admin['empresa_id'], $nombre, $documento, $email, Auth::hashPassword($password), $rolInv, $rolAsis],
                );
            } finally {
                Db::query('SET @cupo_vincula_empleado = NULL');
            }
            $id = (int) $pdo->lastInsertId();
            self::fijarSedes($id, $sedes);
            if ($ficha !== null) {
                Db::query('UPDATE asis_empleados SET usuario_id = ? WHERE id = ?', [$id, $ficha['id']]);
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        Response::json(['usuario' => self::aJson(self::buscar($id, $admin))], 201);
    }

    /** Cambia nombre, roles, sedes, estado o contraseña (campos opcionales). */
    public static function actualizar(Request $req): never
    {
        $yo = Auth::adminEmpresa($req);
        $actual = self::buscar($req->param('id'), $yo);
        $d = $req->json();
        $esYo = $yo['id'] === (int) $actual['id'];

        $nombre = array_key_exists('nombre', $d) ? self::validarNombre($d['nombre']) : $actual['nombre'];
        $rolAsis = array_key_exists('rol_asistencia', $d) || array_key_exists('rol', $d)
            ? self::validarRolAsistencia($d['rol_asistencia'] ?? self::rolLegado($d['rol'] ?? null))
            : $actual['rol_asistencia'];
        $rolInv = array_key_exists('rol_inventario', $d)
            ? self::validarRolInventario($d['rol_inventario'], $yo['empresa_id'])
            : $actual['rol'];
        $activo = array_key_exists('activo', $d) ? ((bool) $d['activo'] ? 1 : 0) : (int) $actual['activo'];
        $sedes = array_key_exists('sedes', $d) ? self::validarSedes($d['sedes'], $yo) : self::sedesDe((int) $actual['id']);
        $documento = array_key_exists('documento', $d) ? self::validarDocumento($d['documento']) : $actual['documento'];

        if ($esYo && ($rolAsis !== Auth::ROL_ADMIN || $activo !== 1)) {
            throw HttpError::validacion('No puedes quitarte el rol de administrador ni desactivarte a ti mismo');
        }
        self::validarCombinacion($rolInv, $rolAsis, $sedes);

        // La empresa no se queda sin administrador activo.
        $eraAdmin = $actual['rol_asistencia'] === Auth::ROL_ADMIN && (int) $actual['activo'] === 1;
        if ($eraAdmin && ($rolAsis !== Auth::ROL_ADMIN || $activo !== 1)) {
            $otros = (int) Db::valor(
                "SELECT COUNT(*) FROM usuarios WHERE empresa_id = ? AND rol_asistencia = 'ADMIN'
                    AND activo = 1 AND deleted_at IS NULL AND id <> ?",
                [$yo['empresa_id'], $actual['id']],
            );
            if ($otros === 0) {
                throw HttpError::validacion('La empresa debe conservar al menos un administrador activo');
            }
        }

        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            Db::query(
                'UPDATE usuarios SET nombre = ?, documento = ?, rol = ?, rol_asistencia = ?, activo = ? WHERE id = ?',
                [$nombre, $documento, $rolInv, $rolAsis, $activo, $actual['id']],
            );
            if (!empty($d['password'])) {
                Db::query('UPDATE usuarios SET password_hash = ? WHERE id = ?', [Auth::hashPassword(self::validarPassword($d['password'])), $actual['id']]);
            }
            self::fijarSedes((int) $actual['id'], $sedes);
            if ($activo === 0 || !empty($d['password'])) {
                // Cierra también sus sesiones de Inventario.
                Db::query('UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP(3) WHERE usuario_id = ? AND revoked_at IS NULL', [$actual['id']]);
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        Response::json(['usuario' => self::aJson(self::buscar((int) $actual['id'], $yo))]);
    }

    // ---------------------------------------------------------------------

    private static function aJson(array $u): array
    {
        $sedes = is_array($u['sedes'] ?? null)
            ? $u['sedes']
            : array_values(array_filter(array_map('intval', explode(',', (string) ($u['sedes'] ?? '')))));
        return [
            'id'             => (int) $u['id'],
            'uuid'           => $u['uuid'],
            'nombre'         => $u['nombre'],
            'documento'      => $u['documento'],
            'email'          => $u['email'],
            // Compatibilidad con la app anterior (GENERAL / ADMINISTRATIVO).
            'usuario'        => $u['email'],
            'rol'            => $u['rol_asistencia'] === null ? null
                : ($u['rol_asistencia'] === Auth::ROL_OPERADOR ? Auth::GENERAL : Auth::ADMINISTRATIVO),
            'rol_asistencia' => $u['rol_asistencia'],
            'rol_inventario' => $u['rol'],
            'sedes'          => $sedes,
            'activo'         => (int) $u['activo'] === 1,
        ];
    }

    private static function buscar(int $id, array $admin): array
    {
        $u = Db::fila(
            'SELECT id, uuid, nombre, documento, email, rol, rol_asistencia, activo
               FROM usuarios WHERE id = ? AND empresa_id = ? AND deleted_at IS NULL',
            [$id, $admin['empresa_id']],
        ) ?? throw HttpError::noEncontrado('Usuario');
        $u['sedes'] = self::sedesDe($id);
        return $u;
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
        // Las sedes viajan con la cuenta a los teléfonos de Inventario.
        Db::query('UPDATE usuarios SET updated_at = UTC_TIMESTAMP(3) WHERE id = ?', [$usuarioId]);
    }

    /** Roles de la app anterior → rol de Control de Personal. */
    private static function rolLegado(mixed $rol): mixed
    {
        return match ($rol) {
            Auth::GENERAL        => Auth::ROL_OPERADOR,
            Auth::ADMINISTRATIVO => Auth::ROL_ADMIN,
            default              => $rol,
        };
    }

    private static function validarRolAsistencia(mixed $v): ?string
    {
        if ($v === null || $v === '') {
            return null;
        }
        if (!in_array($v, Auth::ROLES_ASISTENCIA, true)) {
            throw HttpError::validacion('Rol de Control de Personal inválido', 'rol_asistencia');
        }
        return $v;
    }

    private static function validarRolInventario(mixed $v, int $empresaId): ?string
    {
        if ($v === null || $v === '') {
            return null;
        }
        if (!in_array($v, self::ROLES_INVENTARIO, true)) {
            throw HttpError::validacion('Rol de Inventario inválido', 'rol_inventario');
        }
        if (!in_array('INVENTARIO', Plan::aplicativos($empresaId), true)) {
            throw HttpError::validacion('Tu empresa no tiene habilitada la app de Inventario', 'rol_inventario');
        }
        return $v;
    }

    /** @return array<int> sedes de la empresa (el gerente administra solo las suyas). */
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

    /** Las mismas reglas de Inventario (domain/alcance.js · validarSedesDeRol). */
    private static function validarCombinacion(?string $rolInv, ?string $rolAsis, array $sedes): void
    {
        $error = match (true) {
            $rolInv === null && $rolAsis === null
                => 'Dale acceso a al menos una app (Inventario o Control de Personal)',
            ($rolInv === 'ADMIN' || $rolAsis === 'ADMIN')
                && (($rolInv !== null && $rolInv !== 'ADMIN') || ($rolAsis !== null && $rolAsis !== 'ADMIN'))
                => 'El administrador de la empresa lo es en las dos apps',
            ($rolInv === 'ADMIN' || $rolAsis === 'ADMIN') && $sedes !== []
                => 'El administrador ve todas las sedes: no se le asignan sedes',
            in_array($rolInv, ['VENDEDOR', 'AUXILIAR_INVENTARIO'], true) && count($sedes) !== 1
                => 'Vendedores y auxiliares pertenecen a exactamente una sede',
            ($rolInv === 'GERENTE' || $rolAsis === 'GERENTE') && $sedes === []
                => 'Un gerente necesita al menos una sede',
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
            throw HttpError::validacion('Escribe un correo válido: con él entra a las dos apps', 'email');
        }
        return $e;
    }

    private static function validarDocumento(mixed $v): ?string
    {
        $t = trim((string) ($v ?? ''));
        if ($t === '') {
            return null;
        }
        if (!preg_match('/^[A-Za-z0-9.-]{3,20}$/', $t)) {
            throw HttpError::validacion('Documento de 3 a 20 letras o números', 'documento');
        }
        return $t;
    }

    private static function validarNombre(mixed $v): string
    {
        $n = trim(preg_replace('/\s+/u', ' ', (string) $v));
        if (mb_strlen($n) < 3 || mb_strlen($n) > 120) {
            throw HttpError::validacion('Escribe el nombre completo', 'nombre');
        }
        return $n;
    }

    private static function validarPassword(mixed $v): string
    {
        $p = (string) $v;
        if (strlen($p) < 8) {
            throw HttpError::validacion('La contraseña debe tener al menos 8 caracteres', 'password');
        }
        return $p;
    }
}
