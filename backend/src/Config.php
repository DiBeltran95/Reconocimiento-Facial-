<?php
declare(strict_types=1);

namespace App;

final class Config
{
    private static array $valores = [];

    public static function cargar(array $valores): void
    {
        self::$valores = $valores;
    }

    /** Lee una clave; admite notación con punto: `db.host`. */
    public static function get(string $clave, mixed $porDefecto = null): mixed
    {
        $actual = self::$valores;
        foreach (explode('.', $clave) as $parte) {
            if (!is_array($actual) || !array_key_exists($parte, $actual)) {
                return $porDefecto;
            }
            $actual = $actual[$parte];
        }
        return $actual;
    }
}
