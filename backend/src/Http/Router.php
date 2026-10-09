<?php
declare(strict_types=1);

namespace App\Http;

/** Enrutador mínimo: método + patrón con parámetros numéricos {id}. */
final class Router
{
    /** @var array<int, array{string, string, callable}> */
    private array $rutas = [];

    public function get(string $patron, callable $accion): void
    {
        $this->agregar('GET', $patron, $accion);
    }

    public function post(string $patron, callable $accion): void
    {
        $this->agregar('POST', $patron, $accion);
    }

    public function put(string $patron, callable $accion): void
    {
        $this->agregar('PUT', $patron, $accion);
    }

    public function delete(string $patron, callable $accion): void
    {
        $this->agregar('DELETE', $patron, $accion);
    }

    private function agregar(string $metodo, string $patron, callable $accion): void
    {
        $regex = '#^' . preg_replace('#\\\\\{(\w+)\\\\\}#', '(?P<$1>\d+)', preg_quote($patron, '#')) . '$#';
        $this->rutas[] = [$metodo, $regex, $accion];
    }

    public function despachar(Request $req): never
    {
        $metodoPermitido = false;
        foreach ($this->rutas as [$metodo, $regex, $accion]) {
            if (!preg_match($regex, $req->ruta, $coincidencias)) {
                continue;
            }
            $metodoPermitido = true;
            if ($metodo !== $req->metodo) {
                continue;
            }
            $req->params = array_filter($coincidencias, 'is_string', ARRAY_FILTER_USE_KEY);
            $accion($req);
            Response::sinContenido(); // por si la acción no respondió
        }
        if ($metodoPermitido) {
            throw new HttpError(405, 'Método no permitido');
        }
        throw new HttpError(404, 'Ruta no encontrada');
    }
}
