<?php
declare(strict_types=1);

/**
 * Crea (o restablece) la cuenta de SUPERADMINISTRADOR de la plataforma: la que
 * entra al panel /plataforma/ para asignar planes, habilitar apps y suspender
 * empresas. No pertenece a ninguna empresa ni entra a las apps.
 *
 *   php bin/crear_superadmin.php <correo> "<Nombre completo>"
 *
 * La contraseña se pide por teclado (no queda en el historial de la terminal).
 * Las cuentas de las empresas NO se crean aquí: cada empresa se registra sola
 * desde las apps y su administrador crea las demás.
 */

if (PHP_SAPI !== 'cli') {
    exit("Solo se puede ejecutar desde la consola.\n");
}

require __DIR__ . '/../src/bootstrap.php';

use App\Auth\Auth;
use App\Db;
use App\Servicios\Ids;

restore_error_handler();
restore_exception_handler();

[$_, $email, $nombre] = array_pad($argv, 3, null);
$email = mb_strtolower(trim((string) $email));

if (!filter_var($email, FILTER_VALIDATE_EMAIL) || trim((string) $nombre) === '') {
    fwrite(STDERR, "Uso: php bin/crear_superadmin.php <correo> \"<Nombre completo>\"\n");
    exit(1);
}

$existente = Db::fila('SELECT id, es_superadmin FROM usuarios WHERE email = ?', [$email]);
if ($existente !== null && (int) $existente['es_superadmin'] !== 1) {
    fwrite(STDERR, "Ese correo ya es una cuenta de una empresa. Usa otro para el superadministrador.\n");
    exit(1);
}

echo 'Contraseña (mínimo 12 caracteres): ';
if (DIRECTORY_SEPARATOR === '/') {
    system('stty -echo');
}
$password = trim((string) fgets(STDIN));
if (DIRECTORY_SEPARATOR === '/') {
    system('stty echo');
}
echo "\n";
if (strlen($password) < 12) {
    fwrite(STDERR, "La contraseña del superadministrador debe tener al menos 12 caracteres.\n");
    exit(1);
}

if ($existente !== null) {
    Db::query(
        'UPDATE usuarios SET nombre = ?, password_hash = ?, activo = 1, deleted_at = NULL WHERE id = ?',
        [trim((string) $nombre), Auth::hashPassword($password), $existente['id']],
    );
} else {
    Db::query(
        'INSERT INTO usuarios (uuid, empresa_id, nombre, email, password_hash, rol, rol_asistencia, es_superadmin)
         VALUES (?, NULL, ?, ?, ?, NULL, NULL, 1)',
        [Ids::uuid(), trim((string) $nombre), $email, Auth::hashPassword($password)],
    );
}
echo "Listo: «{$email}» puede entrar al panel de plataforma (/plataforma/).\n";
