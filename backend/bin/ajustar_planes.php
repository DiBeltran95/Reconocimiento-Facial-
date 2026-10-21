<?php
declare(strict_types=1);

/**
 * Ajusta los cupos de las empresas cuyo plan venció o bajó.
 *
 * Cuando un plan vence, la app pasa a operar como Gratis, pero lo que ya
 * existía sigue ahí. Este script llama `sp_ajustar_cupos` para cada empresa y
 * app que quedó por encima de su límite: pausa a las personas que sobran (las
 * más recientes, nunca al administrador) y deja de usar en esa app las sedes
 * elegidas de más (nunca la principal). El administrador luego elige en la
 * app quiénes quedan activos. Programarlo como tarea diaria en alwaysdata
 * (Avanzado → Tareas programadas):
 *
 *   php /home/<cuenta>/<ruta>/backend/bin/ajustar_planes.php
 *
 * Es idempotente: ejecutarlo varias veces no hace daño.
 */

if (PHP_SAPI !== 'cli') {
    exit("Solo se puede ejecutar desde la consola.\n");
}

require __DIR__ . '/../src/bootstrap.php';

use App\Db;

restore_error_handler();
restore_exception_handler();

$excedidas = Db::filas(
    'SELECT empresa_id, aplicativo FROM v_empresa_uso_app
      WHERE (max_personas IS NOT NULL AND personas_usadas > max_personas)
         OR (max_sedes IS NOT NULL AND sedes_usadas > max_sedes)',
);
$pdo = Db::pdo();
foreach ($excedidas as $f) {
    $st = $pdo->prepare('CALL sp_ajustar_cupos(?, ?)');
    $st->execute([(int) $f['empresa_id'], $f['aplicativo']]);
    $st->closeCursor();
}
echo date('c') . ' · cupos ajustados en ' . count($excedidas) . " empresa(s)/app(s)\n";
