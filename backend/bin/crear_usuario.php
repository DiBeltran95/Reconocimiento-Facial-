<?php
declare(strict_types=1);

/**
 * Crea (o restablece) una cuenta de la app de asistencia desde la consola.
 *
 *   php bin/crear_usuario.php <usuario> "<Nombre completo>" <GENERAL|ADMINISTRATIVO>
 *
 * La contraseña se pide por teclado (no queda en el historial de la terminal).
 */

if (PHP_SAPI !== 'cli') {
    exit("Solo se puede ejecutar desde la consola.\n");
}

require __DIR__ . '/../src/bootstrap.php';

use App\Auth\Auth;
use App\Db;

restore_error_handler();
restore_exception_handler();

[$_, $usuario, $nombre, $rol] = array_pad($argv, 4, null);
$usuario = mb_strtolower(trim((string) $usuario));
$rol = strtoupper((string) ($rol ?? 'ADMINISTRATIVO'));

if (!preg_match('/^[a-z0-9._@-]{3,60}$/', $usuario) || trim((string) $nombre) === ''
    || !in_array($rol, [Auth::GENERAL, Auth::ADMINISTRATIVO], true)) {
    fwrite(STDERR, "Uso: php bin/crear_usuario.php <usuario> \"<Nombre completo>\" <GENERAL|ADMINISTRATIVO>\n");
    exit(1);
}

echo 'Contraseña (mínimo 8 caracteres): ';
if (DIRECTORY_SEPARATOR === '/') {
    system('stty -echo');
}
$password = trim((string) fgets(STDIN));
if (DIRECTORY_SEPARATOR === '/') {
    system('stty echo');
}
echo "\n";
if (strlen($password) < 8) {
    fwrite(STDERR, "La contraseña debe tener al menos 8 caracteres.\n");
    exit(1);
}

Db::query(
    'INSERT INTO asis_usuarios (nombre, usuario, password_hash, rol, activo) VALUES (?, ?, ?, ?, 1)
     ON DUPLICATE KEY UPDATE nombre = VALUES(nombre), password_hash = VALUES(password_hash),
                             rol = VALUES(rol), activo = 1',
    [trim((string) $nombre), $usuario, Auth::hashPassword($password), $rol],
);
echo "Listo: «{$usuario}» ({$rol}) puede ingresar a la app y al panel.\n";
