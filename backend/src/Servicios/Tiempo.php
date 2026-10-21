<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Config;
use App\Db;
use App\Http\HttpError;
use DateTimeImmutable;
use DateTimeZone;

/**
 * La BD guarda UTC; aquí se traduce a/desde la zona horaria de la EMPRESA.
 *
 * Cada empresa tiene la suya (`empresas.zona_horaria`). La fija `Auth` al
 * identificar a la persona o al kiosco; antes de eso (rutas públicas) se usa
 * la zona por defecto de la configuración.
 */
final class Tiempo
{
    private static ?DateTimeZone $zona = null;

    public static function usarZona(string $nombre): void
    {
        try {
            self::$zona = new DateTimeZone($nombre !== '' ? $nombre : 'America/Bogota');
        } catch (\Throwable) {
            self::$zona = new DateTimeZone('America/Bogota');
        }
    }

    public static function zona(): DateTimeZone
    {
        if (self::$zona === null) {
            self::usarZona((string) Config::get('zona_por_defecto', 'America/Bogota'));
        }
        return self::$zona;
    }

    public static function utc(): DateTimeZone
    {
        static $utc = null;
        return $utc ??= new DateTimeZone('UTC');
    }

    public static function ahoraUtcIso(): string
    {
        return (new DateTimeImmutable('now', self::utc()))->format('Y-m-d\TH:i:s.v\Z');
    }

    /** ISO-8601 con zona explícita → 'Y-m-d H:i:s' en UTC. Null si no es válida. */
    public static function isoAUtcSql(mixed $iso): ?string
    {
        if (!is_string($iso) || strlen($iso) < 19 || strlen($iso) > 40) {
            return null;
        }
        if (!preg_match('/(Z|[+-]\d{2}:?\d{2})$/i', $iso)) {
            return null; // sin zona sería ambiguo
        }
        try {
            $fecha = new DateTimeImmutable($iso);
        } catch (\Exception) {
            return null;
        }
        return $fecha->setTimezone(self::utc())->format('Y-m-d H:i:s');
    }

    /** 'Y-m-d H:i:s' (UTC) → ISO-8601 en hora local con desfase, p. ej. 2026-10-08T07:58:12-05:00 */
    public static function utcSqlAIsoLocal(?string $sql): ?string
    {
        if ($sql === null) {
            return null;
        }
        return (new DateTimeImmutable($sql, self::utc()))->setTimezone(self::zona())->format('Y-m-d\TH:i:sP');
    }

    public static function utcSqlAIsoUtc(string $sql): string
    {
        return (new DateTimeImmutable($sql, self::utc()))->format('Y-m-d\TH:i:s\Z');
    }

    public static function utcSqlAHoraLocal(?string $sql): string
    {
        if ($sql === null) {
            return '';
        }
        return (new DateTimeImmutable($sql, self::utc()))->setTimezone(self::zona())->format('H:i');
    }

    public static function hoyLocal(): string
    {
        return (new DateTimeImmutable('now', self::zona()))->format('Y-m-d');
    }

    public static function validarFecha(?string $fecha, string $campo = 'fecha'): string
    {
        $fecha ??= self::hoyLocal();
        if (!preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $fecha, $m) || !checkdate((int) $m[2], (int) $m[3], (int) $m[1])) {
            throw HttpError::validacion('Fecha inválida, usa AAAA-MM-DD', $campo);
        }
        return $fecha;
    }

    /** Límites [inicio, fin) del día local expresados en UTC para consultar la BD. */
    public static function rangoDiaUtc(string $fecha): array
    {
        $inicio = new DateTimeImmutable("$fecha 00:00:00", self::zona());
        $fin = $inicio->modify('+1 day');
        return [
            $inicio->setTimezone(self::utc())->format('Y-m-d H:i:s'),
            $fin->setTimezone(self::utc())->format('Y-m-d H:i:s'),
        ];
    }

    /** Día local (Y-m-d) al que pertenece una hora UTC. */
    public static function diaLocal(string $utcSql): string
    {
        return (new DateTimeImmutable($utcSql, self::utc()))->setTimezone(self::zona())->format('Y-m-d');
    }
}
