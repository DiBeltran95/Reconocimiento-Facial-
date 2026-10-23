<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Db;
use App\Http\HttpError;
use DateTimeImmutable;

/** Reportes de asistencia y cumplimiento de horario. */
final class Reportes
{
    /** Desfase (seg) a partir del cual se sospecha un reloj adelantado en el kiosco. */
    private const TOLERANCIA_RELOJ = 120;

    public static function dia(int $sedeId, string $fecha): array
    {
        $sede = Db::fila('SELECT id, nombre, codigo FROM sedes WHERE id = ?', [$sedeId]);
        if ($sede === null) {
            throw HttpError::noEncontrado('Sede');
        }

        [$inicio, $fin] = Tiempo::rangoDiaUtc($fecha);
        $hoy = Tiempo::hoyLocal();
        $esPasado = $fecha < $hoy;

        $marcas = Db::filas(
            'SELECT empleado_id, tipo, hora_dispositivo, hora_servidor
               FROM asis_marcaciones
              WHERE sede_id = ? AND hora_dispositivo >= ? AND hora_dispositivo < ?
              ORDER BY hora_dispositivo, id',
            [$sedeId, $inicio, $fin],
        );
        $porEmpleado = [];
        foreach ($marcas as $m) {
            $porEmpleado[(int) $m['empleado_id']][] = $m;
        }

        // Plantilla del día: activos de la sede vinculados antes de que acabara
        // ese día + cualquiera que haya marcado allí (aunque hoy esté inactivo).
        $params = [$sedeId, $fin];
        $extra = '';
        if ($porEmpleado !== []) {
            $ids = array_keys($porEmpleado);
            $extra = ' OR id IN (' . Db::enLista($ids) . ')';
            $params = array_merge($params, $ids);
        }
        $empleados = Db::filas(
            "SELECT id, documento, nombre, cargo
               FROM empleados
              WHERE (sede_id = ? AND activo = 1 AND created_at < ?)$extra
              ORDER BY nombre",
            $params,
        );
        $turnos = Horarios::delDia(array_map(static fn ($e) => (int) $e['id'], $empleados), $fecha);

        $resumen = [
            'total' => 0, 'presentes' => 0, 'ausentes' => 0, 'en_sede' => 0, 'sin_salida' => 0, 'libres' => 0,
            'alertas' => 0, 'con_turno' => 0, 'cumplen' => 0, 'tarde' => 0, 'incumplen' => 0,
        ];
        $filas = [];
        foreach ($empleados as $e) {
            $id = (int) $e['id'];
            $fila = self::calcularEmpleado($e, $porEmpleado[$id] ?? [], $esPasado, $turnos[$id] ?? null, $fecha);
            $resumen['total']++;
            match ($fila['estado']) {
                'AUSENTE'    => $resumen['ausentes']++,
                'LIBRE'      => $resumen['libres']++,
                'EN_SEDE'    => $resumen['en_sede']++,
                'SIN_SALIDA' => $resumen['sin_salida']++,
                default      => null,
            };
            if (!in_array($fila['estado'], ['AUSENTE', 'LIBRE'], true)) {
                $resumen['presentes']++;
            }
            if ($fila['alertas'] !== []) {
                $resumen['alertas']++;
            }
            $c = $fila['cumplimiento']['estado'];
            if ($fila['turno'] !== null) {
                $resumen['con_turno']++;
                match (true) {
                    $c === 'CUMPLE'                        => $resumen['cumplen']++,
                    $c === 'TARDE' || $c === 'SIN_LLEGAR'  => $resumen['tarde']++,
                    $c === 'PENDIENTE'                     => null,
                    default                                => $resumen['incumplen']++,
                };
            }
            $filas[] = $fila;
        }

        return [
            'fecha'     => $fecha,
            'es_hoy'    => $fecha === $hoy,
            'zona'      => Tiempo::zona()->getName(),
            'sede'      => ['id' => (int) $sede['id'], 'nombre' => $sede['nombre'], 'codigo' => $sede['codigo']],
            'resumen'   => $resumen,
            'empleados' => $filas,
        ];
    }

    private static function calcularEmpleado(array $e, array $marcas, bool $esPasado, ?array $turno, string $fecha): array
    {
        $entrada = null;
        $salida = null;
        $abiertaDesde = null;
        $segundos = 0;
        $alertas = [];
        $detalle = [];

        foreach ($marcas as $m) {
            $dispositivo = $m['hora_dispositivo'];
            $desfase = strtotime($m['hora_servidor']) - strtotime($dispositivo);

            if ($m['tipo'] === 'ENTRADA') {
                $entrada ??= $dispositivo;
                $abiertaDesde ??= $dispositivo;
            } else {
                $salida = $dispositivo;
                if ($abiertaDesde !== null) {
                    $segundos += strtotime($dispositivo) - strtotime($abiertaDesde);
                    $abiertaDesde = null;
                }
            }
            // Una marcación legítima siempre llega al servidor DESPUÉS de ocurrir.
            if ($desfase < -self::TOLERANCIA_RELOJ) {
                $alertas['RELOJ_ADELANTADO'] = true;
            }
            $detalle[] = [
                'tipo'          => $m['tipo'],
                'hora'          => Tiempo::utcSqlAIsoLocal($dispositivo),
                'hora_servidor' => Tiempo::utcSqlAIsoLocal($m['hora_servidor']),
                'desfase_seg'   => $desfase,
            ];
        }

        $cumplimiento = Cumplimiento::evaluar($turno, $marcas, $fecha);
        $ultima = $marcas === [] ? null : end($marcas)['tipo'];
        $estado = match (true) {
            $ultima === null && $cumplimiento['estado'] === 'LIBRE' => 'LIBRE',
            $ultima === null                   => 'AUSENTE',
            $ultima === 'ENTRADA' && $esPasado => 'SIN_SALIDA',
            $ultima === 'ENTRADA'              => 'EN_SEDE',
            default                            => 'SALIO',
        };

        return [
            'id'            => (int) $e['id'],
            'documento'     => $e['documento'],
            'nombre'        => $e['nombre'],
            'cargo'         => $e['cargo'],
            'estado'        => $estado,
            'entrada'       => Tiempo::utcSqlAIsoLocal($entrada),
            'salida'        => Tiempo::utcSqlAIsoLocal($salida),
            'minutos'       => intdiv($segundos, 60),
            // Si sigue en la sede hoy, el cliente suma el tiempo en curso desde aquí.
            'abierta_desde' => $estado === 'EN_SEDE' ? Tiempo::utcSqlAIsoLocal($abiertaDesde) : null,
            'alertas'       => array_keys($alertas),
            'marcaciones'   => $detalle,
            'turno'         => $turno === null ? null : [
                'id' => $turno['id'], 'nombre' => $turno['nombre'], 'bloques' => $turno['bloques'],
                'tolerancia_min' => $turno['tolerancia_min'],
            ],
            'cumplimiento'  => $cumplimiento,
        ];
    }

    /**
     * Cumplimiento consolidado de un período: por empleado, cuántos días
     * cumplió, llegó tarde, salió antes o faltó, y un estado por día.
     */
    public static function cumplimiento(int $sedeId, string $desde, string $hasta): array
    {
        $porEmpleado = [];
        $dias = [];
        $sede = null;
        for ($d = new DateTimeImmutable($desde); $d->format('Y-m-d') <= $hasta; $d = $d->modify('+1 day')) {
            $fecha = $d->format('Y-m-d');
            if ($fecha > Tiempo::hoyLocal()) {
                break;
            }
            $dias[] = $fecha;
            $r = self::dia($sedeId, $fecha);
            $sede = $r['sede'];
            foreach ($r['empleados'] as $f) {
                $acc = &$porEmpleado[$f['id']];
                $acc ??= [
                    'id' => $f['id'], 'documento' => $f['documento'], 'nombre' => $f['nombre'], 'cargo' => $f['cargo'],
                    'dias_programados' => 0, 'dias_cumplidos' => 0, 'tardanzas' => 0, 'minutos_tarde' => 0,
                    'salidas_anticipadas' => 0, 'minutos_anticipados' => 0, 'ausencias' => 0, 'incompletos' => 0,
                    'sin_salida' => 0, 'minutos_programados' => 0, 'minutos_trabajados' => 0, 'dias' => [],
                ];
                $c = $f['cumplimiento'];
                $acc['dias'][$fecha] = $c['estado'];
                $acc['minutos_trabajados'] += $f['minutos'];
                if ($f['turno'] !== null && $c['estado'] !== 'PENDIENTE') {
                    $acc['dias_programados']++;
                    $acc['minutos_programados'] += $c['programado_min'];
                    match ($c['estado']) {
                        'CUMPLE'            => $acc['dias_cumplidos']++,
                        'AUSENTE'           => $acc['ausencias']++,
                        'INCOMPLETO'        => $acc['incompletos']++,
                        'SIN_SALIDA'        => $acc['sin_salida']++,
                        default             => null,
                    };
                    if ($c['retraso_min'] > 0 && in_array($c['estado'], ['TARDE', 'SIN_LLEGAR', 'INCOMPLETO'], true)) {
                        $acc['tardanzas']++;
                        $acc['minutos_tarde'] += $c['retraso_min'];
                    }
                    if ($c['anticipo_min'] > 0) {
                        $acc['salidas_anticipadas']++;
                        $acc['minutos_anticipados'] += $c['anticipo_min'];
                    }
                }
                unset($acc);
            }
        }

        $empleados = array_values(array_map(static function (array $a) use ($dias) {
            $a['porcentaje'] = $a['dias_programados'] > 0 ? round(100 * $a['dias_cumplidos'] / $a['dias_programados']) : null;
            $a['dias'] = array_map(static fn ($f) => ['fecha' => $f, 'estado' => $a['dias'][$f] ?? null], $dias);
            return $a;
        }, $porEmpleado));
        usort($empleados, static fn ($a, $b) => strcmp($a['nombre'], $b['nombre']));

        $programados = array_sum(array_column($empleados, 'dias_programados'));
        $cumplidos = array_sum(array_column($empleados, 'dias_cumplidos'));
        return [
            'desde'     => $desde,
            'hasta'     => $hasta,
            'sede'      => $sede,
            'dias'      => $dias,
            'resumen'   => [
                'porcentaje'          => $programados > 0 ? round(100 * $cumplidos / $programados) : null,
                'dias_programados'    => $programados,
                'dias_cumplidos'      => $cumplidos,
                'tardanzas'           => array_sum(array_column($empleados, 'tardanzas')),
                'ausencias'           => array_sum(array_column($empleados, 'ausencias')),
                'salidas_anticipadas' => array_sum(array_column($empleados, 'salidas_anticipadas')),
            ],
            'empleados' => $empleados,
        ];
    }

    public static function etiquetaEstado(string $estado): string
    {
        return [
            'AUSENTE'    => 'Ausente',
            'EN_SEDE'    => 'En la sede',
            'SALIO'      => 'Salió',
            'SIN_SALIDA' => 'Sin salida registrada',
            'LIBRE'      => 'Libre',
        ][$estado] ?? $estado;
    }

    public static function horasTexto(int $minutos): string
    {
        return $minutos <= 0 ? '' : sprintf('%d:%02d', intdiv($minutos, 60), $minutos % 60);
    }

    /** Fila plana para CSV a partir de una fila del reporte diario. */
    public static function filaCsv(array $f): array
    {
        $hora = static fn (?string $iso) => $iso === null ? '' : substr($iso, 11, 5);
        $marcas = implode(' · ', array_map(
            static fn (array $m) => ($m['tipo'] === 'ENTRADA' ? 'E ' : 'S ') . $hora($m['hora']),
            $f['marcaciones'],
        ));
        $c = $f['cumplimiento'];
        return [
            $f['documento'],
            $f['nombre'],
            (string) $f['cargo'],
            $f['turno'] === null ? 'Sin turno' : $f['turno']['nombre'] . ' (' . str_replace(',', ' y ', $f['turno']['bloques']) . ')',
            self::etiquetaEstado($f['estado']),
            Cumplimiento::ETIQUETAS[$c['estado']] ?? $c['estado'],
            $hora($f['entrada']),
            $hora($f['salida']),
            self::horasTexto($f['minutos']),
            self::horasTexto($c['programado_min']),
            $c['retraso_min'] ?: '',
            $c['anticipo_min'] ?: '',
            $marcas,
            in_array('RELOJ_ADELANTADO', $f['alertas'], true) ? 'Reloj del kiosco adelantado' : '',
        ];
    }

    public const ENCABEZADOS_CSV = [
        'Documento', 'Empleado', 'Cargo', 'Turno', 'Asistencia', 'Cumplimiento', 'Entrada', 'Salida',
        'Horas trabajadas', 'Horas programadas', 'Min. tarde', 'Min. salida anticipada', 'Marcaciones', 'Alertas',
    ];
}
