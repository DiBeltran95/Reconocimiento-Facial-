<?php
declare(strict_types=1);

namespace App\Http;

/** Error controlado: se responde al cliente con su estado y mensaje. */
final class HttpError extends \RuntimeException
{
    public function __construct(
        public readonly int $status,
        string $mensaje,
        public readonly array $extra = [],
    ) {
        parent::__construct($mensaje, $status);
    }

    public static function validacion(string $mensaje, ?string $campo = null): self
    {
        return new self(422, $mensaje, $campo !== null ? ['campo' => $campo] : []);
    }

    public static function noEncontrado(string $que = 'Recurso'): self
    {
        return new self(404, "$que no encontrado");
    }

    public static function prohibido(string $mensaje = 'No tienes permiso para esta sede'): self
    {
        return new self(403, $mensaje);
    }

    public static function noAutorizado(string $mensaje = 'Sesión no válida o vencida'): self
    {
        return new self(401, $mensaje);
    }
}
