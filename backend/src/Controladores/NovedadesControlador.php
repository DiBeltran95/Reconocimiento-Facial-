<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Tiempo;
use App\Servicios\WhatsApp;

/**
 * Novedades de los empleados (permisos, incapacidades, citas médicas…).
 *
 * Las registra el empleado por WhatsApp (módulo `novedades` de apiwhatsapp) y
 * las resuelven el administrador, talento humano (todas las sedes de
 * Presente) o el gerente (sus sedes). Al aprobar o rechazar, se le avisa al
 * empleado por WhatsApp.
 *
 * El soporte (foto o PDF de la incapacidad) es un dato de salud (Ley 1581):
 * solo lo abren el administrador y talento humano.
 */
final class NovedadesControlador
{
    private const TIPOS = [
        'PERMISO'     => 'Permiso',
        'INCAPACIDAD' => 'Incapacidad médica',
        'CITA_MEDICA' => 'Cita médica',
        'CALAMIDAD'   => 'Calamidad doméstica',
        'VACACIONES'  => 'Vacaciones',
        'LICENCIA'    => 'Licencia',
        'OTRO'        => 'Novedad',
    ];

    /**
     * GET /api/novedades?estado=PENDIENTE|RESUELTAS&sede_id=
     * Pendientes: las más antiguas primero (se atienden en orden). Resueltas:
     * las 100 más recientes.
     */
    public static function listar(Request $req): never
    {
        $admin = Auth::admin($req);
        $sedes = $admin['sedes'];
        if (($sedeId = $req->query('sede_id')) !== null) {
            Auth::exigirSede($admin, (int) $sedeId);
            $sedes = [(int) $sedeId];
        }
        if ($sedes === []) {
            Response::json(['novedades' => [], 'pendientes' => 0, 've_soportes' => self::veSoportes($admin)]);
        }
        $pendientes = $req->query('estado', 'PENDIENTE') === 'PENDIENTE';
        $filas = Db::filas(
            'SELECT n.*, e.nombre AS empleado, e.documento, e.cargo, e.sede_id, s.nombre AS sede,
                    r.nombre AS resuelto_por_nombre,
                    (SELECT COUNT(*) FROM asis_novedad_soportes x WHERE x.novedad_id = n.id) AS soportes
               FROM asis_novedades n
               JOIN asis_empleados e ON e.id = n.empleado_id
               JOIN sedes s ON s.id = e.sede_id
               LEFT JOIN usuarios r ON r.id = n.resuelto_por
              WHERE n.empresa_id = ? AND e.sede_id IN (' . Db::enLista($sedes) . ')
                AND ' . ($pendientes ? "n.estado = 'PENDIENTE'" : "n.estado <> 'PENDIENTE'") . '
              ORDER BY ' . ($pendientes ? 'n.created_at ASC' : 'COALESCE(n.resuelto_en, n.updated_at) DESC') . '
              LIMIT ' . ($pendientes ? 500 : 100),
            [$admin['empresa_id'], ...$sedes],
        );
        $total = (int) Db::valor(
            "SELECT COUNT(*) FROM asis_novedades n JOIN asis_empleados e ON e.id = n.empleado_id
              WHERE n.empresa_id = ? AND n.estado = 'PENDIENTE' AND e.sede_id IN (" . Db::enLista($sedes) . ')',
            [$admin['empresa_id'], ...$sedes],
        );
        Response::json([
            'novedades'   => array_map([self::class, 'aJson'], $filas),
            'pendientes'  => $total,
            've_soportes' => self::veSoportes($admin),
        ]);
    }

    /** GET /api/novedades/{id}/soportes — lista (sin el contenido). */
    public static function soportes(Request $req): never
    {
        $admin = self::exigirSoportes($req);
        $n = self::buscar($req->param('id'), $admin);
        $filas = Db::filas(
            'SELECT id, nombre, mime, tamano FROM asis_novedad_soportes WHERE novedad_id = ? ORDER BY id',
            [$n['id']],
        );
        Response::json(['soportes' => array_map(static fn (array $s) => [
            'id'     => (int) $s['id'],
            'nombre' => $s['nombre'],
            'mime'   => $s['mime'],
            'tamano' => (int) $s['tamano'],
        ], $filas)]);
    }

    /** GET /api/novedades/{id}/soportes/{sid} — el archivo. */
    public static function soporte(Request $req): never
    {
        $admin = self::exigirSoportes($req);
        $n = self::buscar($req->param('id'), $admin);
        $s = Db::fila(
            'SELECT nombre, mime, contenido FROM asis_novedad_soportes WHERE id = ? AND novedad_id = ?',
            [$req->param('sid'), $n['id']],
        ) ?? throw HttpError::noEncontrado('Soporte');
        $mime = preg_match('#^(image/(jpeg|png|webp|heic)|application/pdf)$#', (string) $s['mime']) ? $s['mime'] : 'application/octet-stream';
        http_response_code(200);
        header('Content-Type: ' . $mime);
        header('Content-Length: ' . strlen((string) $s['contenido']));
        header('Content-Disposition: inline; filename="' . preg_replace('/[^\w.\- ]/u', '_', (string) $s['nombre']) . '"');
        header('Cache-Control: private, no-store');
        header('X-Content-Type-Options: nosniff');
        echo $s['contenido'];
        exit;
    }

    /**
     * POST /api/novedades/{id}/resolver  {estado: APROBADA|RECHAZADA, comentario?}
     * Rechazar exige un motivo (se le envía al empleado). Solo se resuelven
     * las pendientes: si otra persona ya la resolvió → 409.
     */
    public static function resolver(Request $req): never
    {
        $admin = Auth::admin($req);
        $n = self::buscar($req->param('id'), $admin);
        $d = $req->json();
        $estado = (string) ($d['estado'] ?? '');
        if (!in_array($estado, ['APROBADA', 'RECHAZADA'], true)) {
            throw HttpError::validacion('Elige aprobar o rechazar', 'estado');
        }
        $comentario = trim(preg_replace('/\s+/u', ' ', (string) ($d['comentario'] ?? '')));
        if ($estado === 'RECHAZADA' && mb_strlen($comentario) < 3) {
            throw HttpError::validacion('Escribe el motivo del rechazo: se le enviará al empleado', 'comentario');
        }
        if (mb_strlen($comentario) > 500) {
            throw HttpError::validacion('El comentario puede tener hasta 500 caracteres', 'comentario');
        }

        $cambio = Db::query(
            "UPDATE asis_novedades
                SET estado = ?, comentario = ?, resuelto_por = ?, resuelto_en = UTC_TIMESTAMP()
              WHERE id = ? AND estado = 'PENDIENTE'",
            [$estado, $comentario !== '' ? $comentario : null, $admin['id'], $n['id']],
        )->rowCount();
        if ($cambio === 0) {
            throw new HttpError(409, 'Otra persona ya resolvió esta solicitud', ['codigo' => 'YA_RESUELTA']);
        }

        $n = self::buscar((int) $n['id'], $admin);
        $avisado = WhatsApp::enviarTexto(
            (string) ($n['telefono_origen'] ?: $n['telefono_empleado']),
            self::mensaje($n),
        );
        Response::json(['novedad' => self::aJson($n), 'avisado' => $avisado]);
    }

    // ---------------------------------------------------------------------

    private static function mensaje(array $n): string
    {
        $tipo = self::TIPOS[$n['tipo']] ?? 'Novedad';
        $nombre = explode(' ', trim((string) $n['empleado']))[0];
        $aprobada = $n['estado'] === 'APROBADA';
        $lineas = [
            "Hola, $nombre.",
            '',
            ($aprobada ? '✅ Tu solicitud fue *APROBADA*' : '❌ Tu solicitud fue *RECHAZADA*') . ' (#' . $n['id'] . ').',
            '',
            "*$tipo* · " . self::periodo($n),
        ];
        if (!empty($n['comentario'])) {
            $lineas[] = ($aprobada ? 'Nota: ' : 'Motivo: ') . $n['comentario'];
        }
        $lineas[] = '';
        $lineas[] = $aprobada
            ? 'No tienes que hacer nada más.'
            : 'Si tienes dudas, habla con talento humano de tu empresa.';
        $lineas[] = '— ' . SistemaControlador::nombreNegocio((int) $n['empresa_id']);
        return implode("\n", $lineas);
    }

    private static function periodo(array $n): string
    {
        $f = static fn (string $d) => date('j/n/Y', strtotime($d));
        if ($n['hora_desde'] !== null) {
            return $f($n['fecha_desde']) . ' de ' . substr((string) $n['hora_desde'], 0, 5) . ' a ' . substr((string) $n['hora_hasta'], 0, 5);
        }
        return $n['fecha_desde'] === $n['fecha_hasta']
            ? $f($n['fecha_desde'])
            : 'del ' . $f($n['fecha_desde']) . ' al ' . $f($n['fecha_hasta']);
    }

    private static function veSoportes(array $persona): bool
    {
        return $persona['rol_asistencia'] === Auth::ROL_ADMIN || Auth::esTalentoHumano($persona);
    }

    private static function exigirSoportes(Request $req): array
    {
        $admin = Auth::admin($req);
        if (!self::veSoportes($admin)) {
            throw new HttpError(403, 'Los soportes son datos de salud: solo los ven el administrador y talento humano');
        }
        return $admin;
    }

    private static function buscar(int $id, array $admin): array
    {
        $n = Db::fila(
            'SELECT n.*, e.nombre AS empleado, e.documento, e.cargo, e.sede_id, e.telefono AS telefono_empleado,
                    s.nombre AS sede, r.nombre AS resuelto_por_nombre,
                    (SELECT COUNT(*) FROM asis_novedad_soportes x WHERE x.novedad_id = n.id) AS soportes
               FROM asis_novedades n
               JOIN asis_empleados e ON e.id = n.empleado_id
               JOIN sedes s ON s.id = e.sede_id
               LEFT JOIN usuarios r ON r.id = n.resuelto_por
              WHERE n.id = ? AND n.empresa_id = ?',
            [$id, $admin['empresa_id']],
        ) ?? throw HttpError::noEncontrado('Solicitud');
        Auth::exigirSede($admin, (int) $n['sede_id']);
        return $n;
    }

    private static function aJson(array $n): array
    {
        return [
            'id'           => (int) $n['id'],
            'tipo'         => $n['tipo'],
            'estado'       => $n['estado'],
            'canal'        => $n['canal'],
            'fecha_desde'  => $n['fecha_desde'],
            'fecha_hasta'  => $n['fecha_hasta'],
            'hora_desde'   => $n['hora_desde'] === null ? null : substr((string) $n['hora_desde'], 0, 5),
            'hora_hasta'   => $n['hora_hasta'] === null ? null : substr((string) $n['hora_hasta'], 0, 5),
            'motivo'       => $n['motivo'],
            'comentario'   => $n['comentario'],
            'soportes'     => (int) $n['soportes'],
            'empleado'     => [
                'id'        => (int) $n['empleado_id'],
                'nombre'    => $n['empleado'],
                'documento' => $n['documento'],
                'cargo'     => $n['cargo'],
            ],
            'sede'         => ['id' => (int) $n['sede_id'], 'nombre' => $n['sede']],
            'resuelto_por' => $n['resuelto_por_nombre'],
            'resuelto_en'  => Tiempo::utcSqlAIsoLocal($n['resuelto_en']),
            'creada'       => Tiempo::utcSqlAIsoLocal($n['created_at']),
        ];
    }
}
