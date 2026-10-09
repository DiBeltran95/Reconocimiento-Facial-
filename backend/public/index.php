<?php
declare(strict_types=1);

/**
 * Control de Personal · API
 * Front controller: todas las rutas /api/* pasan por aquí.
 */

use App\Controladores\DispositivosControlador as Dispositivos;
use App\Controladores\EmpleadosControlador as Empleados;
use App\Controladores\HorariosControlador as Horarios;
use App\Controladores\KioscoControlador as Kiosco;
use App\Controladores\ReportesControlador as Reportes;
use App\Controladores\SistemaControlador as Sistema;
use App\Controladores\UsuariosControlador as Usuarios;
use App\Http\Request;
use App\Http\Router;

require __DIR__ . '/../src/bootstrap.php';

$r = new Router();

// Público
$r->get('/api/salud', [Sistema::class, 'salud']);
$r->post('/api/auth/login', [Sistema::class, 'login']);

// Cualquier persona autenticada (GENERAL o ADMINISTRATIVO)
$r->get('/api/auth/yo', [Sistema::class, 'yo']);
$r->get('/api/sedes', [Sistema::class, 'sedes']);
$r->post('/api/dispositivos', [Dispositivos::class, 'crear']);

// Solo ADMINISTRATIVO -------------------------------------------------------
$r->get('/api/dispositivos', [Dispositivos::class, 'listar']);
$r->delete('/api/dispositivos/{id}', [Dispositivos::class, 'revocar']);

$r->get('/api/empleados', [Empleados::class, 'listar']);
$r->post('/api/empleados', [Empleados::class, 'crear']);
$r->get('/api/empleados/{id}', [Empleados::class, 'ver']);
$r->put('/api/empleados/{id}', [Empleados::class, 'actualizar']);
$r->delete('/api/empleados/{id}', [Empleados::class, 'desactivar']);
$r->post('/api/empleados/{id}/fotos', [Empleados::class, 'subirFotos']);
$r->delete('/api/empleados/{id}/fotos', [Empleados::class, 'borrarFotos']);
$r->get('/api/empleados/{id}/fotos/{n}', [Empleados::class, 'foto']); // administrativo o kiosco

$r->get('/api/empleados/{id}/horario', [Horarios::class, 'planEmpleado']);
$r->put('/api/empleados/{id}/rotacion', [Horarios::class, 'guardarRotacion']);
$r->put('/api/empleados/{id}/semana', [Horarios::class, 'ajustarSemana']);

$r->get('/api/horarios', [Horarios::class, 'listar']);
$r->post('/api/horarios', [Horarios::class, 'crear']);
$r->post('/api/horarios/asignar', [Horarios::class, 'asignar']);
$r->put('/api/horarios/{id}', [Horarios::class, 'actualizar']);
$r->delete('/api/horarios/{id}', [Horarios::class, 'archivar']);

$r->get('/api/usuarios', [Usuarios::class, 'listar']);
$r->post('/api/usuarios', [Usuarios::class, 'crear']);
$r->put('/api/usuarios/{id}', [Usuarios::class, 'actualizar']);

$r->get('/api/reportes/dia', [Reportes::class, 'dia']);
$r->get('/api/reportes/dia.csv', [Reportes::class, 'diaCsv']);
$r->get('/api/reportes/rango.csv', [Reportes::class, 'rangoCsv']);
$r->get('/api/reportes/cumplimiento', [Reportes::class, 'cumplimiento']);
$r->get('/api/reportes/cumplimiento.csv', [Reportes::class, 'cumplimientoCsv']);

// Kiosco (cabecera X-Dispositivo) --------------------------------------------
$r->get('/api/kiosco/yo', [Dispositivos::class, 'yo']);
$r->delete('/api/kiosco/yo', [Dispositivos::class, 'desvincularme']);
$r->get('/api/kiosco/empleados', [Kiosco::class, 'empleados']);
$r->get('/api/kiosco/marcaciones/hoy', [Kiosco::class, 'marcacionesHoy']);
$r->post('/api/kiosco/marcaciones', [Kiosco::class, 'registrar']);

$r->despachar(Request::desdeGlobales());
