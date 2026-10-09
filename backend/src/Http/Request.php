<?php
declare(strict_types=1);

namespace App\Http;

final class Request
{
    /** Parámetros de ruta, p. ej. {id}. */
    public array $params = [];

    private ?array $jsonCache = null;

    public function __construct(
        public readonly string $metodo,
        public readonly string $ruta,
    ) {
    }

    public static function desdeGlobales(): self
    {
        $metodo = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $ruta = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

        // Soporta instalaciones en subcarpeta: /asistencia/api/... → /api/...
        $script = (string) ($_SERVER['SCRIPT_NAME'] ?? '');
        $base = str_ends_with($script, '.php') ? rtrim(str_replace('\\', '/', dirname($script)), '/') : '';
        if ($base !== '' && str_starts_with($ruta, $base)) {
            $ruta = substr($ruta, strlen($base)) ?: '/';
        }
        return new self($metodo, '/' . trim($ruta, '/'));
    }

    public function param(string $nombre): int
    {
        return (int) ($this->params[$nombre] ?? 0);
    }

    public function query(string $nombre, ?string $porDefecto = null): ?string
    {
        $valor = $_GET[$nombre] ?? null;
        return is_string($valor) && $valor !== '' ? trim($valor) : $porDefecto;
    }

    /** Cuerpo JSON como arreglo asociativo (vacío si no hay cuerpo). */
    public function json(): array
    {
        if ($this->jsonCache === null) {
            $crudo = file_get_contents('php://input') ?: '';
            if ($crudo === '') {
                $this->jsonCache = [];
            } else {
                $datos = json_decode($crudo, true);
                if (!is_array($datos)) {
                    throw new HttpError(400, 'El cuerpo debe ser JSON válido');
                }
                $this->jsonCache = $datos;
            }
        }
        return $this->jsonCache;
    }

    public function header(string $nombre): ?string
    {
        $clave = 'HTTP_' . strtoupper(str_replace('-', '_', $nombre));
        $valor = $_SERVER[$clave] ?? $_SERVER['REDIRECT_' . $clave] ?? null;
        if ($valor === null && function_exists('getallheaders')) {
            foreach (getallheaders() as $k => $v) {
                if (strcasecmp($k, $nombre) === 0) {
                    $valor = $v;
                    break;
                }
            }
        }
        return is_string($valor) && $valor !== '' ? $valor : null;
    }

    public function bearer(): ?string
    {
        $auth = $this->header('Authorization');
        if ($auth !== null && preg_match('/^Bearer\s+(\S+)$/i', $auth, $m)) {
            return $m[1];
        }
        return null;
    }

    public function ip(): string
    {
        return (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
    }
}
