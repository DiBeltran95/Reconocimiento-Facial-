<?php
declare(strict_types=1);

namespace App\Auth;

use App\Config;
use App\Http\HttpError;

/**
 * Freno de fuerza bruta para el login, guardado en archivos temporales
 * (no ocupa la base de datos). Bloquea 15 min tras 8 fallos.
 */
final class LimiteIntentos
{
    private const MAX_FALLOS = 8;
    private const VENTANA_SEG = 900;

    public static function verificar(string $clave): void
    {
        $fallos = self::leer($clave);
        if (count($fallos) >= self::MAX_FALLOS) {
            $espera = (int) ceil((min($fallos) + self::VENTANA_SEG - time()) / 60);
            throw new HttpError(429, "Demasiados intentos. Intenta de nuevo en $espera min.");
        }
    }

    public static function fallo(string $clave): void
    {
        $fallos = self::leer($clave);
        $fallos[] = time();
        @file_put_contents(self::archivo($clave), json_encode($fallos), LOCK_EX);
    }

    public static function limpiar(string $clave): void
    {
        @unlink(self::archivo($clave));
    }

    private static function leer(string $clave): array
    {
        $archivo = self::archivo($clave);
        if (!is_file($archivo)) {
            return [];
        }
        $fallos = json_decode((string) @file_get_contents($archivo), true);
        $limite = time() - self::VENTANA_SEG;
        return array_values(array_filter(
            is_array($fallos) ? $fallos : [],
            static fn ($t) => is_int($t) && $t > $limite,
        ));
    }

    private static function archivo(string $clave): string
    {
        $dir = Config::get('storage') . '/cache';
        if (!is_dir($dir)) {
            @mkdir($dir, 0750, true);
        }
        return $dir . '/login_' . hash('sha256', $clave) . '.json';
    }
}
