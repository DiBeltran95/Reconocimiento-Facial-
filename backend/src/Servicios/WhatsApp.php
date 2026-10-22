<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Config;

/**
 * Mensajes de WhatsApp por la API de la empresa (apiwhatsapp).
 *
 * `POST whatsapp.url` con `{jid, text}` y la cabecera `x-api-key`. La URL y
 * la llave van solo en `config/config.php` del servidor, nunca en el repo.
 *
 * Avisar es un extra: si la API no está configurada o falla, se registra en
 * el log y se devuelve false; la acción que lo pidió ya quedó hecha.
 */
final class WhatsApp
{
    public static function configurado(): bool
    {
        return (string) Config::get('whatsapp.url', '') !== '' && (string) Config::get('whatsapp.api_key', '') !== '';
    }

    public static function enviarTexto(string $telefono, string $texto): bool
    {
        $numero = self::numero($telefono);
        if ($numero === null || !self::configurado()) {
            return false;
        }
        $cuerpo = json_encode(['jid' => $numero, 'text' => $texto], JSON_UNESCAPED_UNICODE);
        $ch = curl_init((string) Config::get('whatsapp.url'));
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $cuerpo,
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'x-api-key: ' . (string) Config::get('whatsapp.api_key'),
            ],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_TIMEOUT        => 10,
        ]);
        $respuesta = curl_exec($ch);
        $estado = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);
        if ($respuesta === false || $estado < 200 || $estado >= 300) {
            // Nunca se registra la llave: solo el motivo.
            error_log("[asistencia] WhatsApp no enviado ($estado): " . ($error !== '' ? $error : mb_substr((string) $respuesta, 0, 200)));
            return false;
        }
        return true;
    }

    /**
     * Número internacional solo con dígitos. Un celular colombiano de 10
     * dígitos (3001234567) recibe el indicativo 57.
     */
    public static function numero(?string $telefono): ?string
    {
        $digitos = preg_replace('/\D/', '', (string) $telefono);
        if ($digitos === null || strlen($digitos) < 10) {
            return null;
        }
        if (strlen($digitos) === 10) {
            $digitos = (string) Config::get('whatsapp.indicativo', '57') . $digitos;
        }
        return $digitos;
    }
}
