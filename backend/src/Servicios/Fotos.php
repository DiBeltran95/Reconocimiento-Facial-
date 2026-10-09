<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Config;
use App\Http\HttpError;

/**
 * Fotos de rostro en disco privado: storage/rostros/{empleado_id}/{n}.jpg
 *
 * La versión de cada foto (`v`) es su fecha de modificación: los kioscos
 * la comparan con la que tienen en caché y solo descargan lo que cambió.
 * El servidor no calcula nada del rostro; ese trabajo lo hace cada teléfono.
 */
final class Fotos
{
    private const TAMANO_MAX = 8 * 1024 * 1024;

    public static function dir(int $empleadoId): string
    {
        return rtrim((string) Config::get('storage'), '/\\') . '/rostros/' . $empleadoId;
    }

    /** @return array<int, array{n:int, v:int}> */
    public static function listar(int $empleadoId): array
    {
        $dir = self::dir($empleadoId);
        if (!is_dir($dir)) {
            return [];
        }
        $fotos = [];
        foreach (glob($dir . '/*.jpg') ?: [] as $archivo) {
            $n = (int) basename($archivo, '.jpg');
            if ($n >= 1) {
                $fotos[] = ['n' => $n, 'v' => (int) filemtime($archivo)];
            }
        }
        usort($fotos, static fn (array $a, array $b) => $a['n'] <=> $b['n']);
        return $fotos;
    }

    public static function ruta(int $empleadoId, int $n): ?string
    {
        $ruta = self::dir($empleadoId) . '/' . $n . '.jpg';
        return is_file($ruta) ? $ruta : null;
    }

    /** Normaliza `$_FILES[campo]` (uno o varios archivos) a una lista plana. */
    public static function subidas(string $campo): array
    {
        $f = $_FILES[$campo] ?? null;
        if (!is_array($f)) {
            return [];
        }
        if (!is_array($f['name'])) {
            return [$f];
        }
        $lista = [];
        foreach (array_keys($f['name']) as $i) {
            $lista[] = [
                'name'     => $f['name'][$i],
                'tmp_name' => $f['tmp_name'][$i],
                'error'    => $f['error'][$i],
                'size'     => $f['size'][$i],
            ];
        }
        return $lista;
    }

    /**
     * Reemplaza TODAS las fotos del empleado por las nuevas (1..max_fotos).
     * Primero valida y escribe temporales; solo entonces borra las anteriores,
     * así un fallo a mitad de camino nunca deja al empleado sin rostro.
     */
    public static function reemplazar(int $empleadoId, array $subidas): array
    {
        $max = (int) Config::get('max_fotos', 3);
        if (count($subidas) === 0) {
            throw HttpError::validacion('Adjunta al menos una foto del rostro', 'fotos');
        }
        if (count($subidas) > $max) {
            throw HttpError::validacion("Máximo $max fotos por empleado", 'fotos');
        }

        $jpegs = array_map(static fn (array $subida) => self::normalizar($subida), $subidas);

        $dir = self::dir($empleadoId);
        if (!is_dir($dir) && !mkdir($dir, 0750, true) && !is_dir($dir)) {
            throw new \RuntimeException("No se pudo crear $dir");
        }

        $temporales = [];
        foreach ($jpegs as $i => $bytes) {
            $tmp = $dir . '/.' . ($i + 1) . '.tmp';
            if (file_put_contents($tmp, $bytes, LOCK_EX) === false) {
                throw new \RuntimeException('No se pudo guardar la foto');
            }
            $temporales[$i + 1] = $tmp;
        }
        foreach (glob($dir . '/*.jpg') ?: [] as $anterior) {
            @unlink($anterior);
        }
        foreach ($temporales as $n => $tmp) {
            rename($tmp, $dir . '/' . $n . '.jpg');
        }
        clearstatcache();
        return self::listar($empleadoId);
    }

    /** Borra las fotos (minimización de datos biométricos al desactivar). */
    public static function borrarTodas(int $empleadoId): void
    {
        $dir = self::dir($empleadoId);
        if (!is_dir($dir)) {
            return;
        }
        foreach (scandir($dir) ?: [] as $nombre) {
            if (is_file($dir . '/' . $nombre)) {
                @unlink($dir . '/' . $nombre);
            }
        }
        @rmdir($dir);
    }

    /** Valida la imagen y la re-codifica como JPEG derecho, sin EXIF y de tamaño acotado. */
    private static function normalizar(array $subida): string
    {
        if (($subida['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK || !is_uploaded_file($subida['tmp_name'])) {
            throw HttpError::validacion('No se recibió la foto correctamente', 'fotos');
        }
        if ((int) $subida['size'] > self::TAMANO_MAX) {
            throw HttpError::validacion('Cada foto debe pesar menos de 8 MB', 'fotos');
        }
        $info = @getimagesize($subida['tmp_name']);
        $tipo = $info['mime'] ?? '';
        if (!in_array($tipo, ['image/jpeg', 'image/png', 'image/webp'], true)) {
            throw HttpError::validacion('Formato no soportado: usa JPG, PNG o WEBP', 'fotos');
        }

        if (!function_exists('imagecreatefromstring')) {
            // Sin GD solo se aceptan JPEG tal cual.
            if ($tipo !== 'image/jpeg') {
                throw HttpError::validacion('El servidor solo acepta JPG (falta la extensión GD)', 'fotos');
            }
            return (string) file_get_contents($subida['tmp_name']);
        }

        $img = @imagecreatefromstring((string) file_get_contents($subida['tmp_name']));
        if ($img === false) {
            throw HttpError::validacion('La imagen está dañada', 'fotos');
        }
        if ($tipo === 'image/jpeg') {
            $img = self::enderezar($img, $subida['tmp_name']);
        }

        $ladoMax = (int) Config::get('foto_lado_max', 800);
        $ancho = imagesx($img);
        $alto = imagesy($img);
        $escala = min(1.0, $ladoMax / max($ancho, $alto));
        if ($escala < 1.0) {
            $img = imagescale($img, (int) round($ancho * $escala), (int) round($alto * $escala), IMG_BICUBIC);
        }

        ob_start();
        imagejpeg($img, null, 88);
        return (string) ob_get_clean();
    }

    private static function enderezar(\GdImage $img, string $ruta): \GdImage
    {
        if (!function_exists('exif_read_data')) {
            return $img;
        }
        $exif = @exif_read_data($ruta);
        $orientacion = is_array($exif) ? (int) ($exif['Orientation'] ?? 1) : 1;
        switch ($orientacion) {
            case 2:
                imageflip($img, IMG_FLIP_HORIZONTAL);
                return $img;
            case 3:
                return imagerotate($img, 180, 0);
            case 6:
                return imagerotate($img, -90, 0);
            case 8:
                return imagerotate($img, 90, 0);
            default:
                return $img;
        }
    }
}
