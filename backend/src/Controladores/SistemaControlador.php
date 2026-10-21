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
use App\Servicios\Plan;
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
            'plataforma'    => (string) Config::get('nombre_plataforma', ''),
        ]);
    }

    /**
     * Correo y contraseña de la cuenta de la plataforma (la misma de Inventario).
     * Acepta `email` o `usuario` (apps anteriores); las cuentas migradas desde
     * `asis_usuarios` guardan su nombre de usuario en la columna del correo.
     */
    public static function login(Request $req): never
    {
        $datos = $req->json();
        $email = mb_strtolower(trim((string) ($datos['email'] ?? $datos['usuario'] ?? '')));
        $password = (string) ($datos['password'] ?? '');
        if ($email === '' || $password === '') {
            throw HttpError::validacion('Escribe tu correo y contraseña');
        }

        $clave = $req->ip() . '|' . $email;
        LimiteIntentos::verificar($clave);

        $persona = Auth::autenticar($email, $password);
        if ($persona === null) {
            LimiteIntentos::fallo($clave);
            usleep(random_int(200_000, 400_000)); // iguala tiempos y frena la fuerza bruta
            throw new HttpError(401, 'Correo o contraseña incorrectos');
        }
        LimiteIntentos::limpiar($clave);

        $ttl = (int) Config::get('jwt_ttl', 43200);
        if (!empty($persona['superadmin'])) {
            // Solo para el panel de plataforma: las rutas de empresa lo rechazan.
            $token = Jwt::firmar(
                ['sub' => $persona['id'], 'sa' => 1, 'iat' => time(), 'exp' => time() + $ttl],
                (string) Config::get('jwt_secret'),
            );
            Response::json(['token' => $token, 'expira_en' => $ttl, 'superadmin' => true]);
        }

        // Desde un kiosco ya vinculado (envía su token), solo entra alguien de
        // SU empresa: el panel del kiosco no puede abrirse con otra cuenta.
        if ($req->header('X-Dispositivo') !== null) {
            $disp = Auth::dispositivo($req);
            if ($disp['empresa_id'] !== $persona['empresa_id']) {
                throw new HttpError(403, 'Este kiosco pertenece a otra empresa. Entra con una cuenta de esa empresa.', [
                    'codigo' => 'OTRA_EMPRESA',
                ]);
            }
        }

        $token = Jwt::firmar([
            'sub' => $persona['id'],
            'emp' => $persona['empresa_id'],
            'rol' => $persona['rol'],
            'iat' => time(),
            'exp' => time() + $ttl,
        ], (string) Config::get('jwt_secret'));

        Response::json([
            'token'     => $token,
            'expira_en' => $ttl,
            'usuario'   => self::usuarioJson($persona),
            'empresa'   => self::empresaJson($persona['empresa_id']),
            'negocio'   => self::nombreNegocio($persona['empresa_id']),
        ]);
    }

    public static function yo(Request $req): never
    {
        $persona = Auth::persona($req);
        Response::json([
            'usuario' => self::usuarioJson($persona),
            'empresa' => self::empresaJson($persona['empresa_id']),
            'negocio' => self::nombreNegocio($persona['empresa_id']),
            'plan'    => Plan::deEmpresa($persona['empresa_id']),
            'planes'  => Plan::planes($persona['empresa_id']),
        ]);
    }

    /**
     * Sedes visibles para la persona: las ELEGIDAS para Presente (todas, o las
     * del gerente). Con ?todas=1 el administrador ve TODAS las de la empresa
     * —también las que solo usa Ventario y las inactivas— con `elegida`, para
     * elegir cuáles usa Presente.
     */
    public static function sedes(Request $req): never
    {
        $persona = Auth::persona($req);
        $todas = $req->query('todas') === '1' && $persona['rol_asistencia'] === Auth::ROL_ADMIN;
        if ($todas) {
            $filas = Db::filas(
                "SELECT s.id, s.uuid, s.nombre, s.codigo, s.direccion, s.telefono, s.es_principal, s.activo,
                        EXISTS (SELECT 1 FROM sede_aplicativos sa
                                 WHERE sa.sede_id = s.id AND sa.aplicativo = 'ASISTENCIA') AS elegida,
                        EXISTS (SELECT 1 FROM sede_aplicativos sa
                                 WHERE sa.sede_id = s.id AND sa.aplicativo = 'INVENTARIO') AS elegida_ventario
                   FROM sedes s
                  WHERE s.empresa_id = ? AND s.deleted_at IS NULL
                  ORDER BY s.es_principal DESC, s.nombre",
                [$persona['empresa_id']],
            );
            Response::json(['sedes' => array_map([SedesControlador::class, 'aJson'], $filas)]);
        }
        if ($persona['sedes'] === []) {
            Response::json(['sedes' => []]);
        }
        $filas = Db::filas(
            'SELECT id, uuid, nombre, codigo, direccion, telefono, es_principal, activo, 1 AS elegida
               FROM sedes
              WHERE empresa_id = ? AND deleted_at IS NULL AND id IN (' . Db::enLista($persona['sedes']) . ')
              ORDER BY es_principal DESC, nombre',
            [$persona['empresa_id'], ...$persona['sedes']],
        );
        // Los teléfonos y los formularios solo ofrecen las activas.
        $sedes = [];
        foreach ($filas as $s) {
            if ((int) $s['activo'] === 1) {
                $sedes[] = SedesControlador::aJson($s);
            }
        }
        Response::json(['sedes' => $sedes]);
    }

    public static function usuarioJson(array $persona): array
    {
        return [
            'id'             => $persona['id'],
            'nombre'         => $persona['nombre'],
            'email'          => $persona['email'],
            'rol'            => $persona['rol'],
            'rol_asistencia' => $persona['rol_asistencia'],
            'rol_inventario' => $persona['rol_inventario'],
        ];
    }

    public static function empresaJson(int $empresaId): ?array
    {
        $e = Db::fila('SELECT uuid, nombre FROM empresas WHERE id = ?', [$empresaId]);
        return $e === null ? null : ['uuid' => $e['uuid'], 'nombre' => $e['nombre']];
    }

    public static function nombreNegocio(int $empresaId): string
    {
        return (string) (Db::valor('SELECT nombre FROM empresas WHERE id = ?', [$empresaId]) ?? '');
    }
}
