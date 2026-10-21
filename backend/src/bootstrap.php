<?php
declare(strict_types=1);

namespace App;

spl_autoload_register(static function (string $clase): void {
    if (!str_starts_with($clase, 'App\\')) {
        return;
    }
    $archivo = __DIR__ . '/' . str_replace('\\', '/', substr($clase, 4)) . '.php';
    if (is_file($archivo)) {
        require $archivo;
    }
});

$rutaConfig = __DIR__ . '/../config/config.php';
if (!is_file($rutaConfig)) {
    Http\Response::json(['error' => 'Falta config/config.php (copia config.example.php)'], 500);
}
Config::cargar(require $rutaConfig);

date_default_timezone_set('UTC');
mb_internal_encoding('UTF-8');

set_exception_handler(static function (\Throwable $e): void {
    // Reglas que impone la base (límite del plan, correo repetido…): son
    // respuestas para el usuario, no errores del servidor.
    $e = Servicios\Plan::traducir($e) ?? $e;
    if ($e instanceof Http\HttpError) {
        Http\Response::json(['error' => $e->getMessage()] + $e->extra, $e->status);
    }
    error_log('[asistencia] ' . $e);
    $cuerpo = ['error' => 'Error interno del servidor'];
    if (Config::get('debug')) {
        $cuerpo['detalle'] = $e->getMessage();
        $cuerpo['traza'] = explode("\n", $e->getTraceAsString());
    }
    Http\Response::json($cuerpo, 500);
});

set_error_handler(static function (int $nivel, string $mensaje, string $archivo, int $linea): bool {
    if (!(error_reporting() & $nivel)) {
        return false;
    }
    throw new \ErrorException($mensaje, 0, $nivel, $archivo, $linea);
});
