<?php
declare(strict_types=1);

namespace App\Http;

final class Response
{
    public static function json(mixed $datos, int $estado = 200, array $headers = []): never
    {
        http_response_code($estado);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        self::seguridad();
        foreach ($headers as $nombre => $valor) {
            header("$nombre: $valor");
        }
        echo json_encode(
            $datos,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE,
        );
        exit;
    }

    /**
     * Responde JSON con ETag: si el cliente ya tiene esa versión → 304 sin cuerpo.
     * Ideal para la sincronización periódica de los kioscos.
     */
    public static function jsonConEtag(array $datos, ?string $ifNoneMatch): never
    {
        $cuerpo = json_encode(
            $datos,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE,
        );
        $etag = '"' . md5((string) $cuerpo) . '"';
        header('ETag: ' . $etag);
        header('Cache-Control: private, no-cache');
        self::seguridad();
        if ($ifNoneMatch !== null && trim($ifNoneMatch) === $etag) {
            http_response_code(304);
            exit;
        }
        http_response_code(200);
        header('Content-Type: application/json; charset=utf-8');
        echo $cuerpo;
        exit;
    }

    public static function sinContenido(): never
    {
        http_response_code(204);
        self::seguridad();
        exit;
    }

    /** Sirve un archivo privado (fotos) con caché del lado del cliente. */
    public static function archivo(string $ruta, string $tipo, ?string $ifNoneMatch): never
    {
        $etag = '"' . filemtime($ruta) . '-' . filesize($ruta) . '"';
        header('ETag: ' . $etag);
        header('Cache-Control: private, max-age=86400');
        self::seguridad();
        if ($ifNoneMatch !== null && trim($ifNoneMatch) === $etag) {
            http_response_code(304);
            exit;
        }
        header('Content-Type: ' . $tipo);
        header('Content-Length: ' . filesize($ruta));
        readfile($ruta);
        exit;
    }

    public static function csv(string $nombreArchivo, array $encabezados, iterable $filas): never
    {
        http_response_code(200);
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="' . $nombreArchivo . '"');
        header('Cache-Control: no-store');
        self::seguridad();
        $salida = fopen('php://output', 'wb');
        fwrite($salida, "\xEF\xBB\xBF"); // BOM: Excel abre bien tildes y eñes
        fputcsv($salida, $encabezados, ';', '"', '');
        foreach ($filas as $fila) {
            fputcsv($salida, $fila, ';', '"', '');
        }
        fclose($salida);
        exit;
    }

    private static function seguridad(): void
    {
        header('X-Content-Type-Options: nosniff');
        header('Referrer-Policy: no-referrer');
    }
}
