<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;

/** Cuentas de la app de asistencia: GENERAL (kioscos) y ADMINISTRATIVO. */
final class UsuariosControlador
{
    public static function listar(Request $req): never
    {
        Auth::admin($req);
        $lista = array_map(static fn (array $u) => self::aJson($u), Db::filas(
            'SELECT id, nombre, usuario, rol, activo, created_at FROM asis_usuarios ORDER BY activo DESC, nombre',
        ));
        Response::json(['usuarios' => $lista]);
    }

    public static function crear(Request $req): never
    {
        Auth::admin($req);
        $d = $req->json();
        $usuario = self::validarUsuario($d['usuario'] ?? '');
        $nombre = self::validarNombre($d['nombre'] ?? '');
        $rol = self::validarRol($d['rol'] ?? Auth::GENERAL);
        $password = self::validarPassword($d['password'] ?? '');

        if (Db::valor('SELECT 1 FROM asis_usuarios WHERE usuario = ?', [$usuario]) !== null) {
            throw new HttpError(409, 'Ese nombre de usuario ya existe', ['campo' => 'usuario']);
        }
        Db::query(
            'INSERT INTO asis_usuarios (nombre, usuario, password_hash, rol) VALUES (?, ?, ?, ?)',
            [$nombre, $usuario, Auth::hashPassword($password), $rol],
        );
        $id = (int) Db::pdo()->lastInsertId();
        Response::json(['usuario' => self::aJson(self::buscar($id))], 201);
    }

    /** Cambia nombre, rol, estado o contraseña (campos opcionales). */
    public static function actualizar(Request $req): never
    {
        $yo = Auth::admin($req);
        $actual = self::buscar($req->param('id'));
        $d = $req->json();
        $esYo = $yo['origen'] === Auth::ORIGEN_ASISTENCIA && $yo['id'] === (int) $actual['id'];

        $nombre = array_key_exists('nombre', $d) ? self::validarNombre($d['nombre']) : $actual['nombre'];
        $rol = array_key_exists('rol', $d) ? self::validarRol($d['rol']) : $actual['rol'];
        $activo = array_key_exists('activo', $d) ? ($d['activo'] ? 1 : 0) : (int) $actual['activo'];
        if ($esYo && ($rol !== Auth::ADMINISTRATIVO || $activo !== 1)) {
            throw HttpError::validacion('No puedes quitarte el rol administrativo ni desactivarte a ti mismo');
        }

        Db::query(
            'UPDATE asis_usuarios SET nombre = ?, rol = ?, activo = ? WHERE id = ?',
            [$nombre, $rol, $activo, $actual['id']],
        );
        if (!empty($d['password'])) {
            Db::query(
                'UPDATE asis_usuarios SET password_hash = ? WHERE id = ?',
                [Auth::hashPassword(self::validarPassword($d['password'])), $actual['id']],
            );
        }
        Response::json(['usuario' => self::aJson(self::buscar((int) $actual['id']))]);
    }

    private static function aJson(array $u): array
    {
        return [
            'id'      => (int) $u['id'],
            'nombre'  => $u['nombre'],
            'usuario' => $u['usuario'],
            'rol'     => $u['rol'],
            'activo'  => (int) $u['activo'] === 1,
        ];
    }

    private static function buscar(int $id): array
    {
        return Db::fila('SELECT id, nombre, usuario, rol, activo FROM asis_usuarios WHERE id = ?', [$id])
            ?? throw HttpError::noEncontrado('Usuario');
    }

    private static function validarUsuario(mixed $v): string
    {
        $u = mb_strtolower(trim((string) $v));
        if (!preg_match('/^[a-z0-9._@-]{3,60}$/', $u)) {
            throw HttpError::validacion('Usuario: 3 a 60 caracteres (letras, números, punto, guion o @)', 'usuario');
        }
        return $u;
    }

    private static function validarNombre(mixed $v): string
    {
        $n = trim(preg_replace('/\s+/u', ' ', (string) $v));
        if (mb_strlen($n) < 3 || mb_strlen($n) > 120) {
            throw HttpError::validacion('Escribe el nombre completo', 'nombre');
        }
        return $n;
    }

    private static function validarRol(mixed $v): string
    {
        if ($v !== Auth::GENERAL && $v !== Auth::ADMINISTRATIVO) {
            throw HttpError::validacion('Rol inválido', 'rol');
        }
        return $v;
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
