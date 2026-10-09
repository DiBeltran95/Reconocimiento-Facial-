<?php
/**
 * Copia este archivo como `config.php` (misma carpeta) y completa los valores.
 * `config.php` nunca debe quedar dentro de la carpeta pública.
 */
return [
    'db' => [
        'host' => 'mysql-TU_CUENTA.alwaysdata.net',
        'port' => 3306,
        'name' => 'TU_BASE_DE_DATOS',
        'user' => 'TU_USUARIO',
        'pass' => 'CAMBIAR',
    ],

    // Secreto para firmar las sesiones de administración (JWT HS256).
    // Genera uno con:  php -r "echo bin2hex(random_bytes(32));"
    'jwt_secret' => 'CAMBIAR-por-64-caracteres-aleatorios',
    'jwt_ttl'    => 12 * 3600, // segundos

    // Roles de `usuarios` que pueden administrar la asistencia.
    // ADMIN ve todas las sedes; los demás solo las asignadas en `usuario_sedes`.
    'roles_admin' => ['ADMIN', 'GERENTE'],

    // Carpeta privada donde se guardan las fotos de los rostros.
    'storage' => __DIR__ . '/../storage',

    // Fotos de rostro por empleado (más fotos = mejor reconocimiento).
    'max_fotos' => 3,

    // Lado mayor (px) con el que se normalizan las fotos al subirlas.
    'foto_lado_max' => 800,

    // Zona horaria si `configuracion.zona_horaria` no existe.
    'zona_por_defecto' => 'America/Bogota',

    // Muestra el detalle de errores en las respuestas. Nunca en producción.
    'debug' => false,
];
