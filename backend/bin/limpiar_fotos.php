<?php
declare(strict_types=1);

/**
 * Borra las fotos del rostro de las personas eliminadas.
 *
 * Cuando alguien elimina su cuenta (o su empresa) desde Ventario, la base
 * anonimiza la ficha de asistencia (documento «ELIM<id>»), pero las fotos son
 * archivos de ESTE servidor y Ventario no puede tocarlos. Este script las borra.
 * Programarlo como tarea diaria en alwaysdata (Avanzado → Tareas programadas):
 *
 *   php /home/<cuenta>/<ruta>/backend/bin/limpiar_fotos.php
 *
 * Es idempotente: ejecutarlo varias veces no hace daño.
 */

if (PHP_SAPI !== 'cli') {
    exit("Solo se puede ejecutar desde la consola.\n");
}

require __DIR__ . '/../src/bootstrap.php';

use App\Db;
use App\Servicios\Fotos;

restore_error_handler();
restore_exception_handler();

$borradas = 0;
foreach (Db::filas("SELECT id FROM empleados WHERE documento LIKE 'ELIM%'") as $fila) {
    $id = (int) $fila['id'];
    if (Fotos::listar($id) !== []) {
        Fotos::borrarTodas($id);
        $borradas++;
    }
}
echo date('c') . " · fotos borradas de $borradas persona(s) eliminada(s)\n";
