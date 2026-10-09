<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Tiempo;

final class DispositivosControlador
{
    public static function listar(Request $req): never
    {
        $admin = Auth::admin($req);
        $sql = 'SELECT d.id, d.nombre, d.sede_id, s.nombre AS sede, d.ultimo_sync
                  FROM asis_dispositivos d JOIN sedes s ON s.id = d.sede_id
                 WHERE d.activo = 1';
        $params = [];
        if ($admin['sedes'] !== null) {
            if ($admin['sedes'] === []) {
                Response::json(['dispositivos' => []]);
            }
            $sql .= ' AND d.sede_id IN (' . Db::enLista($admin['sedes']) . ')';
            $params = $admin['sedes'];
        }
        $lista = array_map(static fn (array $d) => [
            'id'          => (int) $d['id'],
            'nombre'      => $d['nombre'],
            'sede_id'     => (int) $d['sede_id'],
            'sede'        => $d['sede'],
            'ultimo_sync' => Tiempo::utcSqlAIsoLocal($d['ultimo_sync']),
        ], Db::filas($sql . ' ORDER BY s.nombre, d.nombre', $params));

        Response::json(['dispositivos' => $lista]);
    }

    /**
     * Vincula un kiosco a una sede (usuarios GENERAL o ADMINISTRATIVO).
     * El token en claro solo se entrega aquí.
     */
    public static function crear(Request $req): never
    {
        $admin = Auth::persona($req);
        $datos = $req->json();
        $sedeId = (int) ($datos['sede_id'] ?? 0);
        $nombre = trim(preg_replace('/\s+/u', ' ', (string) ($datos['nombre'] ?? '')));

        if ($nombre === '' || mb_strlen($nombre) > 60) {
            throw HttpError::validacion('Ponle un nombre al dispositivo (máx. 60 caracteres)', 'nombre');
        }
        $sede = Db::fila(
            'SELECT id, nombre, codigo FROM sedes WHERE id = ? AND activo = 1 AND deleted_at IS NULL',
            [$sedeId],
        );
        if ($sede === null) {
            throw HttpError::validacion('Selecciona una sede válida', 'sede_id');
        }
        Auth::exigirSede($admin, $sedeId);

        $token = bin2hex(random_bytes(32));
        Db::query(
            'INSERT INTO asis_dispositivos (sede_id, nombre, token_hash) VALUES (?, ?, ?)',
            [$sedeId, $nombre, hash('sha256', $token)],
        );

        Response::json([
            'id'     => (int) Db::pdo()->lastInsertId(),
            'nombre' => $nombre,
            'token'  => $token,
            'sede'   => ['id' => (int) $sede['id'], 'nombre' => $sede['nombre'], 'codigo' => $sede['codigo']],
        ], 201);
    }

    public static function revocar(Request $req): never
    {
        $admin = Auth::admin($req);
        $disp = Db::fila('SELECT id, sede_id FROM asis_dispositivos WHERE id = ? AND activo = 1', [$req->param('id')]);
        if ($disp === null) {
            throw HttpError::noEncontrado('Dispositivo');
        }
        Auth::exigirSede($admin, (int) $disp['sede_id']);
        Db::query('UPDATE asis_dispositivos SET activo = 0 WHERE id = ?', [$disp['id']]);
        Response::sinContenido();
    }

    /** El kiosco consulta a qué sede pertenece y si sigue vinculado. */
    public static function yo(Request $req): never
    {
        $disp = Auth::dispositivo($req);
        Response::json([
            'dispositivo' => ['id' => $disp['id'], 'nombre' => $disp['nombre']],
            'sede'        => ['id' => $disp['sede_id'], 'nombre' => $disp['sede_nombre'], 'codigo' => $disp['sede_codigo']],
            'negocio'     => SistemaControlador::nombreNegocio(),
        ]);
    }

    /** Un kiosco se desvincula a sí mismo (desde sus ajustes). */
    public static function desvincularme(Request $req): never
    {
        $disp = Auth::dispositivo($req);
        Db::query('UPDATE asis_dispositivos SET activo = 0 WHERE id = ?', [$disp['id']]);
        Response::sinContenido();
    }
}
