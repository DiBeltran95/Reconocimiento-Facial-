<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Db;
use App\Http\HttpError;
use DateTimeImmutable;

/**
 * Resuelve qué turno le corresponde a cada empleado en cada día:
 *   1. Si hay un ajuste para ESA semana (asis_semanas) → manda el ajuste.
 *   2. Si no, la rotación vigente (asis_rotaciones con `desde` ≤ semana):
 *      turno = secuencia[(semanas transcurridas) mod largo].
 *   3. El día solo es laboral si su bit está en `dias` del turno.
 */
final class Horarios
{
    /** Bits de los días: ISO-8601 N (1 = lunes … 7 = domingo) → bit. */
    public const BIT_DIA = [1 => 1, 2 => 2, 3 => 4, 4 => 8, 5 => 16, 6 => 32, 7 => 64];
    public const MAX_BLOQUES = 4;

    private static ?array $cache = null;

    /** Todos los turnos (también inactivos: el historial debe poder resolverse). */
    public static function todos(): array
    {
        if (self::$cache === null) {
            self::$cache = [];
            foreach (Db::filas('SELECT id, nombre, bloques, dias, tolerancia_min, activo FROM asis_horarios') as $h) {
                self::$cache[(int) $h['id']] = self::aJson($h);
            }
        }
        return self::$cache;
    }

    public static function limpiarCache(): void
    {
        self::$cache = null;
    }

    public static function aJson(array $h): array
    {
        return [
            'id'             => (int) $h['id'],
            'nombre'         => $h['nombre'],
            'bloques'        => $h['bloques'],
            'dias'           => (int) $h['dias'],
            'tolerancia_min' => (int) $h['tolerancia_min'],
            'activo'         => (int) $h['activo'] === 1,
            'minutos_dia'    => array_sum(array_map(static fn ($b) => $b[1] - $b[0], self::minutos($h['bloques']))),
        ];
    }

    /** Lunes de la semana de una fecha (Y-m-d). */
    public static function lunes(string $fecha): string
    {
        $d = new DateTimeImmutable($fecha);
        return $d->modify('-' . ((int) $d->format('N') - 1) . ' days')->format('Y-m-d');
    }

    /** '08:30-12:00,14:00-18:00' → [[510, 720], [840, 1080]] (minutos desde medianoche). */
    public static function minutos(string $bloques): array
    {
        $res = [];
        foreach (array_filter(explode(',', $bloques)) as $b) {
            [$i, $f] = explode('-', $b);
            $res[] = [self::aMinutos($i), self::aMinutos($f)];
        }
        return $res;
    }

    private static function aMinutos(string $hhmm): int
    {
        [$h, $m] = array_map('intval', explode(':', $hhmm));
        return $h * 60 + $m;
    }

    /**
     * Valida y normaliza los bloques. Acepta texto '08:30-12:00,14:00-18:00'
     * o lista [{inicio:'08:30', fin:'12:00'}, …]. Devuelve el texto ordenado.
     */
    public static function normalizarBloques(mixed $entrada): string
    {
        $lista = [];
        if (is_string($entrada)) {
            foreach (array_filter(array_map('trim', explode(',', $entrada))) as $b) {
                $partes = array_map('trim', explode('-', $b));
                $lista[] = [$partes[0] ?? '', $partes[1] ?? ''];
            }
        } elseif (is_array($entrada)) {
            foreach ($entrada as $b) {
                $lista[] = [trim((string) ($b['inicio'] ?? '')), trim((string) ($b['fin'] ?? ''))];
            }
        }
        if ($lista === [] || count($lista) > self::MAX_BLOQUES) {
            throw HttpError::validacion('El turno debe tener entre 1 y ' . self::MAX_BLOQUES . ' bloques de horario', 'bloques');
        }
        $minutos = [];
        foreach ($lista as [$i, $f]) {
            if (!preg_match('/^([01]?\d|2[0-3]):[0-5]\d$/', $i) || !preg_match('/^([01]?\d|2[0-3]):[0-5]\d$/', $f)) {
                throw HttpError::validacion('Usa horas en formato 24 h, p. ej. 08:30 o 14:00', 'bloques');
            }
            $mi = self::aMinutos($i);
            $mf = self::aMinutos($f);
            if ($mf <= $mi) {
                throw HttpError::validacion("El bloque $i–$f debe terminar después de empezar", 'bloques');
            }
            $minutos[] = [$mi, $mf];
        }
        usort($minutos, static fn ($a, $b) => $a[0] <=> $b[0]);
        for ($k = 1, $n = count($minutos); $k < $n; $k++) {
            if ($minutos[$k][0] < $minutos[$k - 1][1]) {
                throw HttpError::validacion('Los bloques del turno no pueden cruzarse', 'bloques');
            }
        }
        return implode(',', array_map(
            static fn ($b) => sprintf('%02d:%02d-%02d:%02d', intdiv($b[0], 60), $b[0] % 60, intdiv($b[1], 60), $b[1] % 60),
            $minutos,
        ));
    }

    /** '3,5' → [3, 5] */
    public static function secuencia(string $texto): array
    {
        return array_values(array_map('intval', array_filter(explode(',', $texto), 'strlen')));
    }

    /**
     * Turno de cada SEMANA para varios empleados.
     * @param int[] $empleados
     * @param string[] $semanas lunes Y-m-d
     * @return array<int, array<string, array{horario:?array, ajustada:bool}>>
     */
    public static function porSemana(array $empleados, array $semanas): array
    {
        if ($empleados === [] || $semanas === []) {
            return [];
        }
        $turnos = self::todos();
        $rotaciones = [];
        foreach (Db::filas(
            'SELECT empleado_id, desde, secuencia FROM asis_rotaciones
              WHERE empleado_id IN (' . Db::enLista($empleados) . ') ORDER BY desde',
            $empleados,
        ) as $r) {
            $rotaciones[(int) $r['empleado_id']][] = $r;
        }
        $ajustes = [];
        $params = array_merge($empleados, [min($semanas), max($semanas)]);
        foreach (Db::filas(
            'SELECT empleado_id, semana, horario_id FROM asis_semanas
              WHERE empleado_id IN (' . Db::enLista($empleados) . ') AND semana BETWEEN ? AND ?',
            $params,
        ) as $a) {
            $ajustes[(int) $a['empleado_id']][$a['semana']] = $a['horario_id'] === null ? null : (int) $a['horario_id'];
        }

        $res = [];
        foreach ($empleados as $id) {
            foreach ($semanas as $semana) {
                if (isset($ajustes[$id]) && array_key_exists($semana, $ajustes[$id])) {
                    $hid = $ajustes[$id][$semana];
                    $res[$id][$semana] = ['horario' => $hid === null ? null : ($turnos[$hid] ?? null), 'ajustada' => true];
                    continue;
                }
                $vigente = null;
                foreach ($rotaciones[$id] ?? [] as $r) {
                    if ($r['desde'] <= $semana) {
                        $vigente = $r;
                    }
                }
                $horario = null;
                if ($vigente !== null) {
                    $sec = self::secuencia($vigente['secuencia']);
                    if ($sec !== []) {
                        $transcurridas = intdiv((int) (new DateTimeImmutable($vigente['desde']))->diff(new DateTimeImmutable($semana))->days, 7);
                        $horario = $turnos[$sec[$transcurridas % count($sec)]] ?? null;
                    }
                }
                $res[$id][$semana] = ['horario' => $horario, 'ajustada' => false];
            }
        }
        return $res;
    }

    /**
     * Turno de cada empleado para un DÍA concreto (null = no trabaja ese día).
     * @return array<int, ?array>
     */
    public static function delDia(array $empleados, string $fecha): array
    {
        $semana = self::lunes($fecha);
        $bit = self::BIT_DIA[(int) (new DateTimeImmutable($fecha))->format('N')];
        $res = [];
        foreach (self::porSemana($empleados, [$semana]) as $id => $semanas) {
            $h = $semanas[$semana]['horario'];
            $res[$id] = ($h !== null && ($h['dias'] & $bit)) ? $h : null;
        }
        return $res;
    }
}
