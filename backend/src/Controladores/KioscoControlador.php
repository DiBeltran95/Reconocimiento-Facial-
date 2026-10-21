<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Fotos;
use App\Servicios\Horarios;
use App\Servicios\Tiempo;

/** Endpoints que consume el kiosco (credencial de dispositivo). */
final class KioscoControlador
{
    private const MAX_LOTE = 500;
    private const MAX_DIAS_ATRAS = 45;
    private const MAX_FUTURO_SEG = 86400;

    /**
     * Plantilla completa de la sede con la versión de cada foto. Responde 304
     * cuando nada cambió, así el sondeo periódico casi no consume datos.
     */
    public static function empleados(Request $req): never
    {
        $disp = Auth::dispositivo($req);
        Db::query('UPDATE asis_dispositivos SET ultimo_sync = UTC_TIMESTAMP() WHERE id = ?', [$disp['id']]);

        // Un empleado ligado a una cuenta inactiva (la desactivaron en
        // cualquiera de las dos apps) deja de bajar: ya no puede marcar.
        $filas = Db::filas(
            'SELECT e.id, e.documento, e.nombre, e.cargo FROM asis_empleados e
               LEFT JOIN usuarios u ON u.id = e.usuario_id
              WHERE e.sede_id = ? AND e.activo = 1
                AND (e.usuario_id IS NULL OR (u.activo = 1 AND u.deleted_at IS NULL))
              ORDER BY e.nombre',
            [$disp['sede_id']],
        );
        // Turno de HOY: el kiosco le dice a cada quien si llegó a tiempo.
        $hoy = Tiempo::hoyLocal();
        $turnos = Horarios::delDia(array_map(static fn ($e) => (int) $e['id'], $filas), $hoy);
        $empleados = array_map(static function (array $e) use ($turnos) {
            $turno = $turnos[(int) $e['id']] ?? null;
            return [
                'id'        => (int) $e['id'],
                'documento' => $e['documento'],
                'nombre'    => $e['nombre'],
                'cargo'     => $e['cargo'],
                'fotos'     => Fotos::listar((int) $e['id']),
                'turno_hoy' => $turno === null ? null : ['bloques' => $turno['bloques'], 'tolerancia_min' => $turno['tolerancia_min']],
            ];
        }, $filas);

        Response::jsonConEtag([
            'fecha'     => $hoy,
            'sede'      => ['id' => $disp['sede_id'], 'nombre' => $disp['sede_nombre'], 'codigo' => $disp['sede_codigo']],
            'empleados' => $empleados,
        ], $req->header('If-None-Match'));
    }

    /**
     * Marcaciones de hoy en la sede: así cada kiosco sabe si a alguien le
     * toca "entrada" o "salida" aunque haya marcado en otro dispositivo.
     */
    public static function marcacionesHoy(Request $req): never
    {
        $disp = Auth::dispositivo($req);
        $fecha = Tiempo::hoyLocal();
        [$inicio, $fin] = Tiempo::rangoDiaUtc($fecha);

        $marcas = array_map(static fn (array $m) => [
            'empleado_id' => (int) $m['empleado_id'],
            'tipo'        => $m['tipo'],
            'hora'        => Tiempo::utcSqlAIsoUtc($m['hora_dispositivo']),
        ], Db::filas(
            'SELECT empleado_id, tipo, hora_dispositivo FROM asis_marcaciones
              WHERE sede_id = ? AND hora_dispositivo >= ? AND hora_dispositivo < ?
              ORDER BY hora_dispositivo',
            [$disp['sede_id'], $inicio, $fin],
        ));

        Response::json(['fecha' => $fecha, 'marcaciones' => $marcas, 'hora_servidor' => Tiempo::ahoraUtcIso()]);
    }

    /**
     * Recibe un lote de marcaciones (en línea o acumuladas offline).
     * Idempotente: reenviar la misma marcación responde "duplicada", nunca la repite.
     *
     * Entrada: {"marcaciones":[{"empleado_id":5,"tipo":"ENTRADA","hora":"2026-10-08T12:58:12Z"}]}
     */
    public static function registrar(Request $req): never
    {
        $disp = Auth::dispositivo($req);
        $lote = $req->json()['marcaciones'] ?? null;
        if (!is_array($lote) || $lote === [] || !array_is_list($lote)) {
            throw HttpError::validacion('Envía la lista "marcaciones"');
        }
        if (count($lote) > self::MAX_LOTE) {
            throw HttpError::validacion('Máximo ' . self::MAX_LOTE . ' marcaciones por envío');
        }

        $ids = array_values(array_unique(array_filter(array_map(
            static fn ($m) => is_array($m) ? (int) ($m['empleado_id'] ?? 0) : 0,
            $lote,
        ))));
        // Solo empleados de la EMPRESA del kiosco: nunca alguien de otra. No se
        // exige que siga activo ni en esta sede: una marca hecha sin red antes
        // de darlo de baja o de cambiarlo de sede es un hecho y no se pierde (el
        // kiosco solo lo tenía si estaba activo aquí cuando sincronizó).
        $existentes = $ids === [] ? [] : array_flip(array_map('intval', array_column(
            Db::filas(
                'SELECT id FROM asis_empleados WHERE id IN (' . Db::enLista($ids) . ') AND empresa_id = ?',
                [...$ids, $disp['empresa_id']],
            ),
            'id',
        )));

        $ahora = time();
        $stmt = Db::pdo()->prepare(
            'INSERT INTO asis_marcaciones (empleado_id, sede_id, tipo, hora_dispositivo, hora_servidor)
             VALUES (?, ?, ?, ?, UTC_TIMESTAMP())
             ON DUPLICATE KEY UPDATE id = id',
        );

        $resultados = [];
        Db::pdo()->beginTransaction();
        try {
            foreach ($lote as $i => $m) {
                $resultados[] = ['i' => $i] + self::registrarUna($stmt, $m, $disp['sede_id'], $existentes, $ahora);
            }
            Db::pdo()->commit();
        } catch (\Throwable $e) {
            Db::pdo()->rollBack();
            throw $e;
        }
        Db::query('UPDATE asis_dispositivos SET ultimo_sync = UTC_TIMESTAMP() WHERE id = ?', [$disp['id']]);

        Response::json(['resultados' => $resultados, 'hora_servidor' => Tiempo::ahoraUtcIso()]);
    }

    private static function registrarUna(\PDOStatement $stmt, mixed $m, int $sedeId, array $existentes, int $ahora): array
    {
        if (!is_array($m)) {
            return ['estado' => 'rechazada', 'motivo' => 'Formato inválido'];
        }
        $empleadoId = (int) ($m['empleado_id'] ?? 0);
        $tipo = $m['tipo'] ?? '';
        $hora = Tiempo::isoAUtcSql($m['hora'] ?? null);

        if (!isset($existentes[$empleadoId])) {
            return ['estado' => 'rechazada', 'motivo' => 'Empleado inexistente'];
        }
        if ($tipo !== 'ENTRADA' && $tipo !== 'SALIDA') {
            return ['estado' => 'rechazada', 'motivo' => 'Tipo inválido'];
        }
        if ($hora === null) {
            return ['estado' => 'rechazada', 'motivo' => 'Hora inválida'];
        }
        $marca = strtotime($hora);
        if ($marca < $ahora - self::MAX_DIAS_ATRAS * 86400 || $marca > $ahora + self::MAX_FUTURO_SEG) {
            return ['estado' => 'rechazada', 'motivo' => 'Hora fuera de rango, revisa el reloj del dispositivo'];
        }

        $stmt->execute([$empleadoId, $sedeId, $tipo, $hora]);
        return ['estado' => $stmt->rowCount() === 1 ? 'ok' : 'duplicada'];
    }
}
