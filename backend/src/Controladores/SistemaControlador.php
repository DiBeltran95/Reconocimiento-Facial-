<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Auth\Jwt;
use App\Auth\LimiteIntentos;
use App\Config;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Tiempo;

final class SistemaControlador
{
    /** Público. Los kioscos lo usan para medir el desfase de su reloj. */
    public static function salud(Request $req): never
    {
        Response::json([
            'ok'            => true,
            'hora_servidor' => Tiempo::ahoraUtcIso(),
            'zona'          => Tiempo::zona()->getName(),
            'negocio'       => self::nombreNegocio(),
        ]);
    }

    /** Acepta `usuario` (cuentas de asistencia) o `email` (administradores de inventario). */
    public static function login(Request $req): never
    {
        $datos = $req->json();
        $usuario = mb_strtolower(trim((string) ($datos['usuario'] ?? $datos['email'] ?? '')));
        $password = (string) ($datos['password'] ?? '');
        if ($usuario === '' || $password === '') {
            throw HttpError::validacion('Escribe tu usuario y contraseña');
        }

        $clave = $req->ip() . '|' . $usuario;
        LimiteIntentos::verificar($clave);

        $persona = Auth::autenticar($usuario, $password);
        if ($persona === null) {
            LimiteIntentos::fallo($clave);
            usleep(random_int(200_000, 400_000)); // iguala tiempos y frena la fuerza bruta
            throw new HttpError(401, 'Usuario o contraseña incorrectos');
        }
        LimiteIntentos::limpiar($clave);

        $ttl = (int) Config::get('jwt_ttl', 43200);
        $token = Jwt::firmar([
            'sub' => $persona['id'],
            'org' => $persona['origen'],
            'rol' => $persona['rol'],
            'iat' => time(),
            'exp' => time() + $ttl,
        ], (string) Config::get('jwt_secret'));

        Response::json([
            'token'     => $token,
            'expira_en' => $ttl,
            'usuario'   => ['id' => $persona['id'], 'nombre' => $persona['nombre'], 'rol' => $persona['rol']],
            'negocio'   => self::nombreNegocio(),
        ]);
    }

    public static function yo(Request $req): never
    {
        $persona = Auth::persona($req);
        Response::json([
            'usuario' => ['id' => $persona['id'], 'nombre' => $persona['nombre'], 'rol' => $persona['rol']],
            'negocio' => self::nombreNegocio(),
        ]);
    }

    /** Sedes visibles para la persona (tabla existente `sedes`, solo lectura). */
    public static function sedes(Request $req): never
    {
        $admin = Auth::persona($req);
        $sql = 'SELECT id, nombre, codigo, direccion, es_principal
                  FROM sedes WHERE activo = 1 AND deleted_at IS NULL';
        $params = [];
        if ($admin['sedes'] !== null) {
            if ($admin['sedes'] === []) {
                Response::json(['sedes' => []]);
            }
            $sql .= ' AND id IN (' . Db::enLista($admin['sedes']) . ')';
            $params = $admin['sedes'];
        }
        $sedes = array_map(static fn (array $s) => [
            'id'           => (int) $s['id'],
            'nombre'       => $s['nombre'],
            'codigo'       => $s['codigo'],
            'direccion'    => $s['direccion'],
            'es_principal' => (bool) $s['es_principal'],
        ], Db::filas($sql . ' ORDER BY es_principal DESC, nombre', $params));

        Response::json(['sedes' => $sedes]);
    }

    public static function nombreNegocio(): string
    {
        try {
            return (string) (Db::valor("SELECT valor FROM configuracion WHERE clave = 'nombre_negocio'") ?? '');
        } catch (\Throwable) {
            return '';
        }
    }
}
