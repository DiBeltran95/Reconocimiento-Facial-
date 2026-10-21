<?php
declare(strict_types=1);

namespace App\Servicios;

/** Identificadores públicos. */
final class Ids
{
    /**
     * UUID v7 (RFC 9562): ordenado por tiempo, como los que genera el backend y
     * la app de Inventario. Ordenado, el índice único no se fragmenta.
     */
    public static function uuid(): string
    {
        $ms = (int) floor(microtime(true) * 1000);
        $bytes = pack('J', $ms << 16);                 // 48 bits de tiempo + 16 de relleno
        $bytes = substr($bytes, 0, 6) . random_bytes(10);
        $bytes[6] = chr((ord($bytes[6]) & 0x0F) | 0x70); // versión 7
        $bytes[8] = chr((ord($bytes[8]) & 0x3F) | 0x80); // variante RFC
        $h = bin2hex($bytes);
        return sprintf('%s-%s-%s-%s-%s', substr($h, 0, 8), substr($h, 8, 4), substr($h, 12, 4), substr($h, 16, 4), substr($h, 20));
    }
}
