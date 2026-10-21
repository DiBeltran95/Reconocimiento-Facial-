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

    // Nombre de la plataforma (lo devuelve /api/salud).
    'nombre_plataforma' => 'Krenovapp',

    // Correo saliente (recuperar la contraseña). Con 'smtp' se envía por SMTP
    // autenticado: OBLIGATORIO si el remitente es @gmail.com (Gmail con
    // «contraseña de aplicación»; puerto 465 = SSL, 587 = STARTTLS). Sin
    // 'smtp' se usa mail() del hosting, que solo sirve con un remitente del
    // propio dominio. Con 'habilitado' => false y 'debug' => true, el correo se
    // escribe en el log (solo desarrollo).
    'correo' => [
        'habilitado' => true,
        'remitente'  => 'Presente <tu-cuenta@gmail.com>',
        'smtp' => [
            'host'    => 'smtp.gmail.com',
            'puerto'  => 465,
            'usuario' => 'tu-cuenta@gmail.com',
            'clave'   => 'CONTRASEÑA-DE-APLICACIÓN',
        ],
    ],

    // Carpeta privada donde se guardan las fotos de los rostros.
    'storage' => __DIR__ . '/../storage',

    // Fotos de rostro por empleado (más fotos = mejor reconocimiento).
    'max_fotos' => 3,

    // Lado mayor (px) con el que se normalizan las fotos al subirlas.
    'foto_lado_max' => 800,

    // Zona horaria de las rutas públicas (cada empresa usa la suya).
    'zona_por_defecto' => 'America/Bogota',

    // Muestra el detalle de errores en las respuestas. Nunca en producción.
    'debug' => false,
];
