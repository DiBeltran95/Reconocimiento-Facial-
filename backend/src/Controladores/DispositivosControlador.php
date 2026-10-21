<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Tiempo;

/**
 * Teléfonos de marcación (kioscos).
 *
 * Una sola cuenta OPERARIO sirve para todas las sedes y para muchos teléfonos,
 * casi siempre del mismo modelo. Cada teléfono se distingue por su INSTALACIÓN
 * (`instalacion_uuid`, que la app genera y guarda al instalarse) y por un
 * CÓDIGO corto visible en su pantalla: así el administrador sabe qué aparato
 * físico es cuál y desvincula uno sin tocar a los demás.
 *
 * El token del teléfono no caduca: deja de valer si lo desvinculan, si se
 * inactiva la cuenta que lo vinculó o si su sede sale del plan de Presente.
 */
final class DispositivosControlador
{
    /** Sin 0/O ni 1/I: el código se lee en voz alta y en pantallas pequeñas. */
    private const ALFABETO = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

    public static function listar(Request $req): never
    {
        $admin = Auth::admin($req);
        if ($admin['sedes'] === []) {
            Response::json(['dispositivos' => []]);
        }
        $filas = Db::filas(
            'SELECT d.id, d.nombre, d.codigo, d.sede_id, s.nombre AS sede, d.ultimo_sync, d.vinculado_en,
                    v.nombre AS vinculado_por
               FROM asis_dispositivos d
               JOIN sedes s ON s.id = d.sede_id
               LEFT JOIN usuarios v ON v.id = d.vinculado_por
              WHERE d.activo = 1 AND d.sede_id IN (' . Db::enLista($admin['sedes']) . ')
              ORDER BY s.nombre, d.nombre',
            $admin['sedes'],
        );
        $lista = array_map(static fn (array $d) => [
            'id'            => (int) $d['id'],
            'nombre'        => $d['nombre'],
            'codigo'        => $d['codigo'],
            'sede_id'       => (int) $d['sede_id'],
            'sede'          => $d['sede'],
            'ultimo_sync'   => Tiempo::utcSqlAIsoLocal($d['ultimo_sync']),
            'vinculado_en'  => Tiempo::utcSqlAIsoLocal($d['vinculado_en']),
            'vinculado_por' => $d['vinculado_por'],
        ], $filas);

        Response::json(['dispositivos' => $lista]);
    }

    /**
     * Vincula ESTE teléfono a una sede. Lo usa el OPERARIO (la forma normal) y
     * también el administrador, el gerente o talento humano.
     *
     * Cuerpo: {sede_id, instalacion_uuid?, nombre?}. Con `instalacion_uuid`, un
     * teléfono que ya estaba vinculado se reutiliza (otra sede, token nuevo) en
     * vez de duplicarse. Sin nombre: «<Sede> · Teléfono N». El token en claro
     * solo se entrega aquí.
     */
    public static function crear(Request $req): never
    {
        $persona = Auth::persona($req);
        $datos = $req->json();
        $sedeId = (int) ($datos['sede_id'] ?? 0);
        $nombre = trim(preg_replace('/\s+/u', ' ', (string) ($datos['nombre'] ?? '')));
        $instalacion = strtolower(trim((string) ($datos['instalacion_uuid'] ?? '')));

        if ($instalacion !== '' && !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $instalacion)) {
            throw HttpError::validacion('Identificador de instalación inválido', 'instalacion_uuid');
        }
        if (mb_strlen($nombre) > 60) {
            throw HttpError::validacion('El nombre puede tener hasta 60 caracteres', 'nombre');
        }
        $sede = Db::fila(
            'SELECT id, nombre, codigo FROM sedes WHERE id = ? AND empresa_id = ? AND activo = 1 AND deleted_at IS NULL',
            [$sedeId, $persona['empresa_id']],
        );
        if ($sede === null || !Auth::sedeElegida($sedeId)) {
            throw HttpError::validacion('Selecciona una sede de Presente', 'sede_id');
        }
        Auth::exigirSede($persona, $sedeId);

        $token = bin2hex(random_bytes(32));
        $previo = $instalacion === ''
            ? null
            : Db::fila('SELECT id, codigo, nombre, sede_id FROM asis_dispositivos WHERE instalacion_uuid = ?', [$instalacion]);

        if ($previo !== null) {
            // El mismo teléfono: se reutiliza su registro y su código. Si cambia
            // de sede (o no tenía nombre propio), toma el automático de la nueva.
            $nombreFinal = $nombre !== ''
                ? $nombre
                : ((int) $previo['sede_id'] === $sedeId ? (string) $previo['nombre'] : self::nombreAutomatico($sede));
            Db::query(
                'UPDATE asis_dispositivos
                    SET sede_id = ?, nombre = ?, token_hash = ?, activo = 1,
                        vinculado_por = ?, vinculado_en = UTC_TIMESTAMP()
                  WHERE id = ?',
                [$sedeId, $nombreFinal, hash('sha256', $token), $persona['id'], $previo['id']],
            );
            $id = (int) $previo['id'];
            $codigo = (string) $previo['codigo'];
        } else {
            $nombreFinal = $nombre !== '' ? $nombre : self::nombreAutomatico($sede);
            $codigo = self::codigoLibre();
            Db::query(
                'INSERT INTO asis_dispositivos (sede_id, nombre, instalacion_uuid, codigo, token_hash, vinculado_por, vinculado_en)
                 VALUES (?, ?, ?, ?, ?, ?, UTC_TIMESTAMP())',
                [$sedeId, $nombreFinal, $instalacion !== '' ? $instalacion : null, $codigo, hash('sha256', $token), $persona['id']],
            );
            $id = (int) Db::pdo()->lastInsertId();
        }

        Response::json([
            'id'     => $id,
            'nombre' => $nombreFinal,
            'codigo' => $codigo,
            'token'  => $token,
            'sede'   => ['id' => (int) $sede['id'], 'nombre' => $sede['nombre'], 'codigo' => $sede['codigo']],
        ], 201);
    }

    /** Renombrar un teléfono («Recepción», «Bodega»…). */
    public static function renombrar(Request $req): never
    {
        $admin = Auth::admin($req);
        $disp = self::delAlcance($admin, (int) $req->param('id'));
        $nombre = trim(preg_replace('/\s+/u', ' ', (string) ($req->json()['nombre'] ?? '')));
        if ($nombre === '' || mb_strlen($nombre) > 60) {
            throw HttpError::validacion('Ponle un nombre al teléfono (máx. 60 caracteres)', 'nombre');
        }
        Db::query('UPDATE asis_dispositivos SET nombre = ? WHERE id = ?', [$nombre, $disp['id']]);
        Response::json(['id' => (int) $disp['id'], 'nombre' => $nombre]);
    }

    public static function revocar(Request $req): never
    {
        $admin = Auth::admin($req);
        $disp = self::delAlcance($admin, (int) $req->param('id'));
        Db::query('UPDATE asis_dispositivos SET activo = 0 WHERE id = ?', [$disp['id']]);
        Response::sinContenido();
    }

    /** El teléfono consulta a qué sede pertenece y si sigue vinculado. */
    public static function yo(Request $req): never
    {
        $disp = Auth::dispositivo($req);
        Response::json([
            'dispositivo' => ['id' => $disp['id'], 'nombre' => $disp['nombre'], 'codigo' => $disp['codigo']],
            'sede'        => ['id' => $disp['sede_id'], 'nombre' => $disp['sede_nombre'], 'codigo' => $disp['sede_codigo']],
            'negocio'     => SistemaControlador::nombreNegocio($disp['empresa_id']),
        ]);
    }

    /**
     * Desvincular ESTE teléfono desde el propio teléfono. Exige además la
     * sesión de un administrador, gerente o talento humano: el operario (y
     * cualquiera que pase por el kiosco) no puede quitarlo.
     */
    public static function desvincularme(Request $req): never
    {
        $admin = Auth::admin($req);
        $disp = Auth::dispositivo($req);
        if ((int) $disp['empresa_id'] !== (int) $admin['empresa_id']) {
            throw HttpError::prohibido();
        }
        Auth::exigirSede($admin, (int) $disp['sede_id']);
        Db::query('UPDATE asis_dispositivos SET activo = 0 WHERE id = ?', [$disp['id']]);
        Response::sinContenido();
    }

    // ---------------------------------------------------------------------

    private static function delAlcance(array $admin, int $id): array
    {
        $disp = Db::fila('SELECT id, sede_id FROM asis_dispositivos WHERE id = ? AND activo = 1', [$id]);
        if ($disp === null) {
            throw HttpError::noEncontrado('Dispositivo');
        }
        Auth::exigirSede($admin, (int) $disp['sede_id']);
        return $disp;
    }

    /** «Sede Centro · Teléfono 3»: el siguiente número libre de esa sede. */
    private static function nombreAutomatico(array $sede): string
    {
        $usados = array_column(Db::filas(
            'SELECT nombre FROM asis_dispositivos WHERE sede_id = ? AND activo = 1',
            [$sede['id']],
        ), 'nombre');
        $base = mb_substr((string) $sede['nombre'], 0, 40) . ' · Teléfono ';
        for ($n = 1; ; $n++) {
            if (!in_array($base . $n, $usados, true)) {
                return $base . $n;
            }
        }
    }

    private static function codigoLibre(): string
    {
        for ($intento = 0; $intento < 20; $intento++) {
            $codigo = '';
            for ($i = 0; $i < 4; $i++) {
                $codigo .= self::ALFABETO[random_int(0, strlen(self::ALFABETO) - 1)];
            }
            if (Db::fila('SELECT 1 AS x FROM asis_dispositivos WHERE codigo = ?', [$codigo]) === null) {
                return $codigo;
            }
        }
        throw new \RuntimeException('No se pudo generar un código de teléfono libre');
    }
}
