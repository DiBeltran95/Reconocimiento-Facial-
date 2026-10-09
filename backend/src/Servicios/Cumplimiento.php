<?php
declare(strict_types=1);

namespace App\Servicios;

use DateTimeImmutable;

/**
 * Compara las marcaciones de un día contra el turno programado.
 *
 * Las marcaciones se emparejan en tramos (entrada → salida). Cada bloque del
 * turno se evalúa contra los tramos que lo cruzan:
 *   - retraso  = llegada − inicio del bloque   (tarde si supera la tolerancia)
 *   - anticipo = fin del bloque − salida       (salida anticipada si supera la tolerancia)
 * Si alguien marca solo al llegar en la mañana y al irse en la tarde, un mismo
 * tramo cubre ambos bloques y se considera cumplido (no se exige marcar almuerzo).
 */
final class Cumplimiento
{
    /** Orden de gravedad para el estado del día (mayor = peor). */
    private const GRAVEDAD = [
        'CUMPLE' => 0, 'PENDIENTE' => 0, 'SIN_SALIDA' => 1, 'SALIDA_ANTICIPADA' => 2,
        'TARDE' => 3, 'SIN_LLEGAR' => 4, 'INCOMPLETO' => 5, 'AUSENTE' => 6,
    ];

    public const ETIQUETAS = [
        'CUMPLE'            => 'Cumple',
        'TARDE'             => 'Llegó tarde',
        'SALIDA_ANTICIPADA' => 'Salió antes',
        'SIN_SALIDA'        => 'Sin salida',
        'SIN_LLEGAR'        => 'Aún no llega',
        'INCOMPLETO'        => 'Incompleto',
        'AUSENTE'           => 'No asistió',
        'PENDIENTE'         => 'Pendiente',
        'LIBRE'             => 'Libre',
        'EXTRA'             => 'Fuera de turno',
    ];

    /**
     * @param ?array $turno   Turno del día (null = no trabaja)
     * @param array  $marcas  [['tipo' => 'ENTRADA'|'SALIDA', 'hora_dispositivo' => UTC 'Y-m-d H:i:s'], …] en orden
     * @param string $fecha   Día local Y-m-d
     */
    public static function evaluar(?array $turno, array $marcas, string $fecha): array
    {
        $hoy = Tiempo::hoyLocal();
        $esHoy = $fecha === $hoy;
        $ahora = $esHoy ? self::minutoLocal(gmdate('Y-m-d H:i:s'), $fecha) : null;

        if ($turno === null) {
            return [
                'estado'         => $marcas === [] ? 'LIBRE' : 'EXTRA',
                'programado_min' => 0,
                'retraso_min'    => 0,
                'anticipo_min'   => 0,
                'parcial'        => false,
                'bloques'        => [],
            ];
        }

        $tramos = self::tramos($marcas, $fecha, $ahora);
        $tolerancia = (int) $turno['tolerancia_min'];
        $bloques = [];
        $retraso = 0;
        $anticipo = 0;
        $programado = 0;
        $estado = 'CUMPLE';
        $evaluados = 0;
        $faltas = 0;
        $pendientes = 0;

        foreach (Horarios::minutos($turno['bloques']) as [$ini, $fin]) {
            $programado += $fin - $ini;
            $cruzan = array_values(array_filter(
                $tramos,
                static fn (array $t) => $t['ini'] < $fin && ($t['fin'] ?? PHP_INT_MAX) > $ini,
            ));
            $b = ['inicio' => self::hhmm($ini), 'fin' => self::hhmm($fin), 'llegada' => null, 'salida' => null,
                  'retraso_min' => 0, 'anticipo_min' => 0, 'estado' => 'OK'];

            if ($cruzan === []) {
                if ($ahora !== null && $ahora < $fin) {
                    // Hoy y el bloque no ha terminado: aún puede llegar.
                    $b['estado'] = $ahora <= $ini + $tolerancia ? 'PENDIENTE' : 'SIN_LLEGAR';
                    if ($b['estado'] === 'SIN_LLEGAR') {
                        $b['retraso_min'] = $ahora - $ini;
                        $retraso += $b['retraso_min'];
                        $estado = self::peor($estado, 'SIN_LLEGAR');
                        $evaluados++;
                    } else {
                        $pendientes++;
                    }
                } else {
                    $b['estado'] = 'FALTA';
                    $faltas++;
                    $evaluados++;
                }
                $bloques[] = $b;
                continue;
            }

            $evaluados++;
            $llegada = min(array_column($cruzan, 'ini'));
            $abierto = false;
            $salida = null;
            foreach ($cruzan as $t) {
                if ($t['fin'] === null) {
                    $abierto = true;
                } else {
                    $salida = max($salida ?? 0, $t['fin']);
                }
            }
            $b['llegada'] = self::hhmm($llegada);
            $b['retraso_min'] = max(0, $llegada - $ini);
            if ($b['retraso_min'] > $tolerancia) {
                $b['estado'] = 'TARDE';
                $retraso += $b['retraso_min'];
                $estado = self::peor($estado, 'TARDE');
            }

            if ($abierto) {
                if ($ahora === null) {
                    $b['estado'] = $b['estado'] === 'OK' ? 'SIN_SALIDA' : $b['estado'];
                    $estado = self::peor($estado, 'SIN_SALIDA');
                } elseif ($ahora < $fin) {
                    $b['estado'] = $b['estado'] === 'OK' ? 'EN_CURSO' : $b['estado'];
                }
            } elseif ($salida !== null) {
                $b['salida'] = self::hhmm($salida);
                $b['anticipo_min'] = max(0, $fin - $salida);
                if ($b['anticipo_min'] > $tolerancia) {
                    $b['estado'] = $b['estado'] === 'TARDE' ? 'TARDE_ANTICIPADA' : 'ANTICIPADA';
                    $anticipo += $b['anticipo_min'];
                    $estado = self::peor($estado, 'SALIDA_ANTICIPADA');
                }
            }
            $bloques[] = $b;
        }

        if ($evaluados === 0) {
            $estado = 'PENDIENTE';
        } elseif ($faltas === $evaluados && $marcas === []) {
            $estado = 'AUSENTE';
        } elseif ($faltas > 0) {
            $estado = self::peor($estado, 'INCOMPLETO');
        }

        return [
            'estado'         => $estado,
            'programado_min' => $programado,
            'retraso_min'    => $retraso,
            'anticipo_min'   => $anticipo,
            'parcial'        => $pendientes > 0,
            'bloques'        => $bloques,
        ];
    }

    /** Empareja marcaciones en tramos [ini, fin] en minutos locales del día. */
    private static function tramos(array $marcas, string $fecha, ?int $ahora): array
    {
        $tramos = [];
        $abierto = null;
        foreach ($marcas as $m) {
            $min = self::minutoLocal($m['hora_dispositivo'], $fecha);
            if ($m['tipo'] === 'ENTRADA') {
                $abierto ??= $min; // entradas repetidas: vale la primera
            } elseif ($abierto !== null) {
                $tramos[] = ['ini' => $abierto, 'fin' => $min];
                $abierto = null;
            } else {
                $tramos[] = ['ini' => $min, 'fin' => $min]; // salida sin entrada
            }
        }
        if ($abierto !== null) {
            // Sigue adentro: hoy el tramo está en curso; en días pasados, sin salida.
            $tramos[] = ['ini' => $abierto, 'fin' => null];
        }
        return $tramos;
    }

    private static function minutoLocal(string $utcSql, string $fecha): int
    {
        $local = (new DateTimeImmutable($utcSql, Tiempo::utc()))->setTimezone(Tiempo::zona());
        $medianoche = new DateTimeImmutable("$fecha 00:00:00", Tiempo::zona());
        return intdiv($local->getTimestamp() - $medianoche->getTimestamp(), 60);
    }

    private static function hhmm(int $min): string
    {
        return sprintf('%02d:%02d', intdiv($min, 60), $min % 60);
    }

    private static function peor(string $a, string $b): string
    {
        return (self::GRAVEDAD[$b] ?? 0) > (self::GRAVEDAD[$a] ?? 0) ? $b : $a;
    }
}
