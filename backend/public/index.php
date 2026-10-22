<?php
declare(strict_types=1);

/**
 * Control de Personal · API
 * Front controller: todas las rutas /api/* pasan por aquí.
 */

use App\Controladores\CuentaControlador as Cuenta;
use App\Controladores\DispositivosControlador as Dispositivos;
use App\Controladores\EmpleadosControlador as Empleados;
use App\Controladores\HorariosControlador as Horarios;
use App\Controladores\KioscoControlador as Kiosco;
use App\Controladores\NovedadesControlador as Novedades;
use App\Controladores\PlataformaControlador as Plataforma;
use App\Controladores\ReportesControlador as Reportes;
use App\Controladores\SedesControlador as Sedes;
use App\Controladores\SistemaControlador as Sistema;
use App\Controladores\UsuariosControlador as Usuarios;
use App\Http\Request;
use App\Http\Router;

require __DIR__ . '/../src/bootstrap.php';

$r = new Router();

// Público
$r->get('/api/salud', [Sistema::class, 'salud']);
$r->post('/api/auth/login', [Sistema::class, 'login']);
$r->post('/api/cuenta/registro', [Cuenta::class, 'registro']);
$r->post('/api/cuenta/recuperar', [Cuenta::class, 'recuperar']);
$r->post('/api/cuenta/restablecer', [Cuenta::class, 'restablecer']);

// Cualquier persona autenticada (GENERAL o ADMINISTRATIVO)
$r->get('/api/auth/yo', [Sistema::class, 'yo']);
$r->post('/api/auth/renovar', [Sistema::class, 'renovar']);
$r->get('/api/sedes', [Sistema::class, 'sedes']);
$r->post('/api/dispositivos', [Dispositivos::class, 'crear']);
$r->get('/api/cuenta/empresa', [Cuenta::class, 'empresa']);
$r->delete('/api/cuenta', [Cuenta::class, 'eliminar']);

// Solo el administrador de la empresa ----------------------------------------
$r->put('/api/cuenta/empresa', [Cuenta::class, 'editarEmpresa']);
$r->post('/api/sedes', [Sedes::class, 'crear']);
$r->put('/api/sedes/{id}', [Sedes::class, 'actualizar']);
$r->post('/api/sedes/{id}/elegir', [Sedes::class, 'elegir']);

// Superadministrador de la plataforma ----------------------------------------
$r->get('/api/plataforma/resumen', [Plataforma::class, 'resumen']);
$r->get('/api/plataforma/empresas', [Plataforma::class, 'empresas']);
$r->put('/api/plataforma/empresas/{id}', [Plataforma::class, 'actualizarEmpresa']);
$r->get('/api/plataforma/planes', [Plataforma::class, 'planes']);
$r->post('/api/plataforma/planes', [Plataforma::class, 'crearPlan']);
$r->put('/api/plataforma/planes/{id}', [Plataforma::class, 'actualizarPlan']);

// Solo ADMINISTRATIVO -------------------------------------------------------
$r->get('/api/dispositivos', [Dispositivos::class, 'listar']);
$r->delete('/api/dispositivos/{id}', [Dispositivos::class, 'revocar']);
$r->put('/api/dispositivos/{id}', [Dispositivos::class, 'renombrar']);

$r->get('/api/empleados', [Empleados::class, 'listar']);
$r->post('/api/empleados', [Empleados::class, 'crear']);
$r->get('/api/empleados/{id}', [Empleados::class, 'ver']);
$r->put('/api/empleados/{id}', [Empleados::class, 'actualizar']);
$r->delete('/api/empleados/{id}', [Empleados::class, 'desactivar']);
$r->post('/api/empleados/{id}/pausa', [Empleados::class, 'pausar']);
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
$r->get('/api/usuarios/candidatos', [Usuarios::class, 'candidatos']);
$r->post('/api/usuarios', [Usuarios::class, 'crear']);
$r->put('/api/usuarios/{id}', [Usuarios::class, 'actualizar']);
$r->post('/api/usuarios/{id}/pausa', [Usuarios::class, 'pausar']);
$r->delete('/api/usuarios/{id}', [Usuarios::class, 'quitar']);

$r->get('/api/novedades', [Novedades::class, 'listar']);
$r->post('/api/novedades/{id}/resolver', [Novedades::class, 'resolver']);
$r->get('/api/novedades/{id}/soportes', [Novedades::class, 'soportes']);
$r->get('/api/novedades/{id}/soportes/{sid}', [Novedades::class, 'soporte']);

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
