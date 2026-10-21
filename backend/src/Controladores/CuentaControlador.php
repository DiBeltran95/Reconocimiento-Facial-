<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Auth\Jwt;
use App\Auth\LimiteIntentos;
use App\Config;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Correo;
use App\Servicios\Fotos;
use App\Servicios\Ids;
use App\Servicios\Plan;

/**
 * Cuenta de la empresa en la plataforma. Mismo contrato que el backend de
 * Inventario (docs/PLATAFORMA.md):
 *
 *   POST   /api/cuenta/registro      empresa + sede principal + dueño (público)
 *   GET    /api/cuenta/empresa       datos, plan, uso y apps habilitadas
 *   PUT    /api/cuenta/empresa       nombre, NIT y teléfono (administrador)
 *   POST   /api/cuenta/recuperar     código por correo para cambiar la contraseña
 *   POST   /api/cuenta/restablecer   contraseña nueva con ese código
 *   DELETE /api/cuenta               elimina la empresa (dueño) o la propia cuenta
 */
final class CuentaControlador
{
    private const VIGENCIA_CODIGO_MIN = 15;
    private const INTENTOS_CODIGO = 5;

    public static function registro(Request $req): never
    {
        $limite = 'registro|' . $req->ip();
        LimiteIntentos::verificar($limite);
        LimiteIntentos::fallo($limite); // cuenta cada intento: crear empresas en serie no es uso normal

        $d = $req->json();
        $empresa = self::texto($d['empresa']['nombre'] ?? null, 2, 120, 'Escribe el nombre de tu empresa', 'empresa.nombre');
        $nit = self::opcional($d['empresa']['nit'] ?? null, 30);
        $telefono = self::opcional($d['empresa']['telefono'] ?? null, 30);
        $sede = self::texto($d['sede']['nombre'] ?? null, 2, 120, 'Ponle nombre a tu primera sede', 'sede.nombre');
        $codigo = strtoupper(trim((string) ($d['sede']['codigo'] ?? '')));
        $codigo = $codigo !== '' ? $codigo : SedesControlador::codigoSugerido($sede);
        if (!preg_match('/^[A-Z0-9]{2,10}$/', $codigo)) {
            throw HttpError::validacion('El código de la sede lleva de 2 a 10 letras o números', 'sede.codigo');
        }
        $nombre = self::texto($d['usuario']['nombre'] ?? null, 2, 120, 'Escribe tu nombre', 'usuario.nombre');
        $email = mb_strtolower(trim((string) ($d['usuario']['email'] ?? '')));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 191) {
            throw HttpError::validacion('Correo no válido', 'usuario.email');
        }
        $password = self::password($d['usuario']['password'] ?? null, 'usuario.password');
        if (($d['acepta_terminos'] ?? false) !== true) {
            throw HttpError::validacion('Debes aceptar los términos y el tratamiento de datos', 'acepta_terminos');
        }

        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            $stmt = Db::query('CALL sp_registrar_empresa(?,?,?,?,?,?,?,?,?,?,?,?)', [
                Ids::uuid(), $empresa, $nit, $telefono,
                Ids::uuid(), $sede, $codigo,
                Ids::uuid(), $nombre, $email, Auth::hashPassword($password), 'ASISTENCIA',
            ]);
            $stmt->fetchAll();
            $stmt->closeCursor();
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }

        // Recién creada, la sesión se abre de una vez.
        $persona = Auth::autenticar($email, $password);
        $ttl = (int) Config::get('jwt_ttl', 43200);
        $token = Jwt::firmar([
            'sub' => $persona['id'], 'emp' => $persona['empresa_id'], 'rol' => $persona['rol'],
            'iat' => time(), 'exp' => time() + $ttl,
        ], (string) Config::get('jwt_secret'));

        Response::json([
            'token'     => $token,
            'expira_en' => $ttl,
            'usuario'   => SistemaControlador::usuarioJson($persona),
            'empresa'   => SistemaControlador::empresaJson($persona['empresa_id']),
            'negocio'   => $empresa,
            'plan'      => Plan::deEmpresa($persona['empresa_id']),
        ], 201);
    }

    public static function empresa(Request $req): never
    {
        $persona = Auth::persona($req);
        Response::json(self::empresaCompleta($persona['empresa_id']));
    }

    public static function editarEmpresa(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        $d = $req->json();
        $cambios = [];
        if (array_key_exists('nombre', $d)) {
            $cambios['nombre'] = self::texto($d['nombre'], 2, 120, 'El nombre lleva de 2 a 120 caracteres', 'nombre');
        }
        foreach (['nit' => 30, 'telefono' => 30] as $campo => $max) {
            if (array_key_exists($campo, $d)) {
                $cambios[$campo] = self::opcional($d[$campo], $max);
            }
        }
        if ($cambios === []) {
            throw HttpError::validacion('No se envió ningún cambio');
        }
        // Los mismos datos viven en la configuración del ticket de Inventario.
        $claves = ['nombre' => 'nombre_negocio', 'nit' => 'nit', 'telefono' => 'telefono'];
        foreach ($cambios as $campo => $valor) {
            Db::query("UPDATE empresas SET $campo = ? WHERE id = ?", [$valor, $admin['empresa_id']]);
            Db::query(
                "INSERT INTO empresa_configuracion (empresa_id, clave, valor, tipo) VALUES (?, ?, ?, 'STRING')
                 ON DUPLICATE KEY UPDATE valor = VALUES(valor)",
                [$admin['empresa_id'], $claves[$campo], (string) ($valor ?? '')],
            );
        }
        Response::json(self::empresaCompleta($admin['empresa_id']));
    }

    /** Siempre responde lo mismo, exista o no el correo. */
    public static function recuperar(Request $req): never
    {
        $email = mb_strtolower(trim((string) ($req->json()['email'] ?? '')));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw HttpError::validacion('Correo no válido', 'email');
        }
        $limite = 'recuperar|' . $req->ip() . '|' . $email;
        LimiteIntentos::verificar($limite);
        LimiteIntentos::fallo($limite);

        $u = Db::fila('SELECT id, nombre FROM usuarios WHERE email = ? AND activo = 1 AND deleted_at IS NULL', [$email]);
        if ($u !== null) {
            $codigo = str_pad((string) random_int(0, 999_999), 6, '0', STR_PAD_LEFT);
            Db::query(
                "INSERT INTO codigos_verificacion (usuario_id, proposito, codigo_hash, expira_en)
                 VALUES (?, 'RECUPERAR_CLAVE', ?, DATE_ADD(UTC_TIMESTAMP(3), INTERVAL ? MINUTE))",
                [$u['id'], hash('sha256', $u['id'] . ':' . $codigo), self::VIGENCIA_CODIGO_MIN],
            );
            Correo::enviar(
                $email,
                "Tu código para cambiar la contraseña: $codigo",
                "Hola, {$u['nombre']}.\n\nTu código es $codigo. Escríbelo en la app para crear una contraseña nueva.\n"
                . 'Vence en ' . self::VIGENCIA_CODIGO_MIN . " minutos.\n\n"
                . "Si no lo pediste, ignora este correo: tu contraseña sigue igual.\n",
            );
        }
        Response::json(['enviado' => true, 'vigencia_minutos' => self::VIGENCIA_CODIGO_MIN]);
    }

    public static function restablecer(Request $req): never
    {
        $d = $req->json();
        $email = mb_strtolower(trim((string) ($d['email'] ?? '')));
        $codigo = trim((string) ($d['codigo'] ?? ''));
        $password = self::password($d['password'] ?? null, 'password');
        $invalido = new HttpError(422, 'El código no es válido o ya venció. Pide uno nuevo.', ['codigo' => 'CODIGO_INVALIDO']);
        if (!preg_match('/^\d{6}$/', $codigo)) {
            throw $invalido;
        }

        $u = Db::fila('SELECT id FROM usuarios WHERE email = ? AND activo = 1 AND deleted_at IS NULL', [$email]);
        if ($u === null) {
            throw $invalido;
        }
        // Solo el último código vale: pedir otro invalida los anteriores.
        $c = Db::fila(
            "SELECT id, codigo_hash, intentos, expira_en, usado_en FROM codigos_verificacion
              WHERE usuario_id = ? AND proposito = 'RECUPERAR_CLAVE' ORDER BY id DESC LIMIT 1",
            [$u['id']],
        );
        $vigente = $c !== null && $c['usado_en'] === null && (int) $c['intentos'] < self::INTENTOS_CODIGO
            && strtotime($c['expira_en'] . ' UTC') >= time();
        if (!$vigente) {
            throw $invalido;
        }
        if (!hash_equals((string) $c['codigo_hash'], hash('sha256', $u['id'] . ':' . $codigo))) {
            Db::query('UPDATE codigos_verificacion SET intentos = intentos + 1 WHERE id = ?', [$c['id']]);
            throw $invalido;
        }
        // Marcar usado solo si nadie lo usó entre tanto: dos usos simultáneos no pasan ambos.
        $usado = Db::query(
            'UPDATE codigos_verificacion SET usado_en = UTC_TIMESTAMP(3) WHERE id = ? AND usado_en IS NULL',
            [$c['id']],
        )->rowCount();
        if ($usado !== 1) {
            throw $invalido;
        }
        Db::query('UPDATE usuarios SET password_hash = ? WHERE id = ?', [Auth::hashPassword($password), $u['id']]);
        // Como al cambiarla a mano: se cierran las sesiones de Inventario.
        Db::query('UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP(3) WHERE usuario_id = ? AND revoked_at IS NULL', [$u['id']]);
        Response::json(['ok' => true]);
    }

    /**
     * Play exige poder borrar la cuenta desde la app, y que el borrado sea
     * real. El dueño elimina la EMPRESA y cualquier otra persona, su propia
     * cuenta: la base anonimiza en el acto cuentas y fichas
     * (sp_anonimizar_empresa / sp_anonimizar_usuario, los mismos que usa
     * Inventario) y aquí se borran las fotos del rostro del disco.
     */
    public static function eliminar(Request $req): never
    {
        $persona = Auth::persona($req);
        $d = $req->json();
        $hash = (string) Db::valor('SELECT password_hash FROM usuarios WHERE id = ?', [$persona['id']]);
        if (!Auth::verificarPassword((string) ($d['password'] ?? ''), $hash)) {
            throw new HttpError(401, 'La contraseña no es correcta', ['codigo' => 'PASSWORD_INCORRECTA']);
        }

        $esDueno = $persona['rol_asistencia'] === Auth::ROL_ADMIN;
        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            if ($esDueno) {
                $nombre = (string) Db::valor('SELECT nombre FROM empresas WHERE id = ?', [$persona['empresa_id']]);
                if (mb_strtolower(trim((string) ($d['confirmacion'] ?? ''))) !== mb_strtolower(trim($nombre))) {
                    throw new HttpError(409, 'Escribe el nombre de la empresa tal como aparece para confirmar', ['codigo' => 'CONFIRMACION_INVALIDA']);
                }
                $empleados = Db::filas('SELECT id FROM asis_empleados WHERE empresa_id = ?', [$persona['empresa_id']]);
                // closeCursor: un CALL deja un resultado de estado pendiente que
                // bloquearía la siguiente consulta («unbuffered queries»).
                Db::query('CALL sp_anonimizar_empresa(?)', [$persona['empresa_id']])->closeCursor();
                $resultado = ['eliminada' => 'empresa'];
            } else {
                $empleados = Db::filas('SELECT id FROM asis_empleados WHERE usuario_id = ?', [$persona['id']]);
                Db::query('CALL sp_anonimizar_usuario(?)', [$persona['id']])->closeCursor();
                $resultado = ['eliminada' => 'cuenta'];
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        // Después del commit: si la transacción fallara, las fotos seguirían ahí.
        foreach ($empleados as $e) {
            Fotos::borrarTodas((int) $e['id']);
        }
        Response::json($resultado);
    }

    // ---------------------------------------------------------------------

    private static function empresaCompleta(int $empresaId): array
    {
        return [
            'empresa'     => Db::fila(
                'SELECT uuid, nombre, nit, telefono, email_contacto, created_at FROM empresas WHERE id = ?',
                [$empresaId],
            ),
            'plan'        => Plan::deEmpresa($empresaId),
            'aplicativos' => Plan::aplicativos($empresaId),
        ];
    }

    private static function texto(mixed $v, int $min, int $max, string $error, string $campo): string
    {
        $t = trim(preg_replace('/\s+/u', ' ', (string) ($v ?? '')));
        if (mb_strlen($t) < $min || mb_strlen($t) > $max) {
            throw HttpError::validacion($error, $campo);
        }
        return $t;
    }

    private static function opcional(mixed $v, int $max): ?string
    {
        $t = trim((string) ($v ?? ''));
        return $t === '' ? null : mb_substr($t, 0, $max);
    }

    private static function password(mixed $v, string $campo): string
    {
        $p = (string) ($v ?? '');
        if (strlen($p) < 8 || strlen($p) > 200) {
            throw HttpError::validacion('La contraseña lleva al menos 8 caracteres', $campo);
        }
        return $p;
    }
}
