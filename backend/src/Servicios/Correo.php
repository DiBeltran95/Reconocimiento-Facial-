<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Config;
use App\Http\HttpError;

/**
 * Correo saliente (recuperar la contraseña).
 *
 * Con `correo.smtp` configurado se envía por SMTP autenticado (p. ej. Gmail con
 * contraseña de aplicación): es lo que hace falta para remitir como una cuenta
 * de Gmail, porque un `mail()` desde el hosting con remitente @gmail.com no
 * pasa los controles DMARC y termina en spam o rechazado. Sin `smtp` se usa
 * `mail()` de PHP (sirve con un remitente del propio dominio del hosting).
 *
 * Con `correo.habilitado` en false (desarrollo), el mensaje va al log de
 * errores para poder probar el flujo completo.
 */
final class Correo
{
    public static function enviar(string $para, string $asunto, string $texto): void
    {
        if (!Config::get('correo.habilitado', false)) {
            if (Config::get('debug')) {
                error_log("[asistencia] Correo NO enviado (correo.habilitado=false) a $para: $asunto\n$texto");
                return;
            }
            throw new HttpError(503, 'El envío de correos no está configurado', ['codigo' => 'CORREO_NO_DISPONIBLE']);
        }
        $remitente = (string) Config::get('correo.remitente', 'no-responder@localhost');
        $smtp = Config::get('correo.smtp');

        try {
            if (is_array($smtp) && ($smtp['host'] ?? '') !== '') {
                self::porSmtp($smtp, $remitente, $para, $asunto, $texto);
                return;
            }
        } catch (\Throwable $e) {
            // Nunca se registra la contraseña: solo el motivo del fallo.
            error_log('[asistencia] Falló el envío SMTP: ' . $e->getMessage());
            throw new HttpError(503, 'No se pudo enviar el correo. Intenta de nuevo en unos minutos.', ['codigo' => 'CORREO_NO_DISPONIBLE']);
        }

        $cabeceras = implode("\r\n", [
            'From: ' . $remitente,
            'MIME-Version: 1.0',
            'Content-Type: text/plain; charset=UTF-8',
            'Content-Transfer-Encoding: 8bit',
        ]);
        if (!@mail($para, self::encabezadoUtf8($asunto), $texto, $cabeceras)) {
            throw new HttpError(503, 'No se pudo enviar el correo. Intenta de nuevo en unos minutos.', ['codigo' => 'CORREO_NO_DISPONIBLE']);
        }
    }

    /**
     * SMTP mínimo: SSL directo (puerto 465) o STARTTLS (587), AUTH LOGIN y un
     * mensaje de texto. Suficiente para un código de verificación; evita
     * depender de una librería externa en un hosting sin Composer.
     *
     * @param array{host:string, puerto?:int, usuario?:string, clave?:string} $cfg
     */
    private static function porSmtp(array $cfg, string $remitente, string $para, string $asunto, string $texto): void
    {
        $host = (string) $cfg['host'];
        $puerto = (int) ($cfg['puerto'] ?? 465);
        $usuario = (string) ($cfg['usuario'] ?? '');
        // Google entrega la contraseña de aplicación con espacios; no forman parte de ella.
        $clave = str_replace(' ', '', (string) ($cfg['clave'] ?? ''));

        $contexto = stream_context_create(['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'peer_name' => $host]]);
        $destino = ($puerto === 465 ? 'ssl://' : 'tcp://') . $host . ':' . $puerto;
        $s = @stream_socket_client($destino, $errno, $errstr, 20, STREAM_CLIENT_CONNECT, $contexto);
        if ($s === false) {
            throw new \RuntimeException("No se pudo conectar a $host:$puerto ($errstr)");
        }
        stream_set_timeout($s, 20);

        try {
            $local = gethostname() ?: 'localhost';
            self::esperar($s, 220);
            self::orden($s, "EHLO $local", 250);
            if ($puerto !== 465) {
                self::orden($s, 'STARTTLS', 220);
                if (!stream_socket_enable_crypto($s, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
                    throw new \RuntimeException('No se pudo iniciar TLS');
                }
                self::orden($s, "EHLO $local", 250);
            }
            if ($usuario !== '') {
                self::orden($s, 'AUTH LOGIN', 334);
                self::orden($s, base64_encode($usuario), 334);
                self::orden($s, base64_encode($clave), 235, 'autenticación');
            }
            $desde = self::direccion($remitente) ?: $usuario;
            self::orden($s, "MAIL FROM:<$desde>", 250);
            self::orden($s, 'RCPT TO:<' . self::direccion($para) . '>', [250, 251]);
            self::orden($s, 'DATA', 354);

            $cabeceras = [
                'Date: ' . date(DATE_RFC2822),
                'From: ' . $remitente,
                'To: <' . self::direccion($para) . '>',
                'Subject: ' . self::encabezadoUtf8($asunto),
                'Message-ID: <' . bin2hex(random_bytes(12)) . '@' . (explode('@', $desde)[1] ?? 'localhost') . '>',
                'MIME-Version: 1.0',
                'Content-Type: text/plain; charset=UTF-8',
                'Content-Transfer-Encoding: base64',
            ];
            $cuerpo = rtrim(chunk_split(base64_encode($texto), 76, "\r\n"));
            self::escribir($s, implode("\r\n", $cabeceras) . "\r\n\r\n" . $cuerpo . "\r\n.");
            self::esperar($s, 250);
            @fwrite($s, "QUIT\r\n");
        } finally {
            fclose($s);
        }
    }

    /** @param int|int[] $codigos */
    private static function orden($s, string $linea, int|array $codigos, string $que = ''): void
    {
        self::escribir($s, $linea);
        self::esperar($s, $codigos, $que);
    }

    private static function escribir($s, string $linea): void
    {
        if (@fwrite($s, $linea . "\r\n") === false) {
            throw new \RuntimeException('Se cortó la conexión con el servidor de correo');
        }
    }

    /** Lee la respuesta (posiblemente de varias líneas) y exige uno de los códigos. */
    private static function esperar($s, int|array $codigos, string $que = ''): void
    {
        $respuesta = '';
        while (($linea = fgets($s, 1024)) !== false) {
            $respuesta .= $linea;
            if (strlen($linea) < 4 || $linea[3] === ' ') {
                break;
            }
        }
        $codigo = (int) substr($respuesta, 0, 3);
        if (!in_array($codigo, (array) $codigos, true)) {
            $detalle = $que !== '' ? " en $que" : '';
            throw new \RuntimeException("Respuesta SMTP inesperada$detalle: " . trim($respuesta));
        }
    }

    /** «Presente <a@b.co>» → «a@b.co». */
    private static function direccion(string $texto): string
    {
        return preg_match('/<([^>]+)>/', $texto, $m) ? trim($m[1]) : trim($texto);
    }

    private static function encabezadoUtf8(string $texto): string
    {
        return '=?UTF-8?B?' . base64_encode($texto) . '?=';
    }
}
