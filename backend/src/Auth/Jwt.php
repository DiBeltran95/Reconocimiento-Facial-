<?php
declare(strict_types=1);

namespace App\Auth;

/** JWT HS256 mínimo: sesiones de administración sin tabla en la BD. */
final class Jwt
{
    public static function firmar(array $datos, string $secreto): string
    {
        $cabecera = self::b64(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
        $cuerpo = self::b64(json_encode($datos, JSON_UNESCAPED_UNICODE));
        $firma = self::b64(hash_hmac('sha256', "$cabecera.$cuerpo", $secreto, true));
        return "$cabecera.$cuerpo.$firma";
    }

    /** Devuelve el contenido si la firma es válida y no ha vencido; si no, null. */
    public static function verificar(string $token, string $secreto): ?array
    {
        $partes = explode('.', $token);
        if (count($partes) !== 3) {
            return null;
        }
        [$cabecera, $cuerpo, $firma] = $partes;
        $esperada = self::b64(hash_hmac('sha256', "$cabecera.$cuerpo", $secreto, true));
        if (!hash_equals($esperada, $firma)) {
            return null;
        }
        $alg = json_decode(self::desb64($cabecera), true)['alg'] ?? null;
        $datos = json_decode(self::desb64($cuerpo), true);
        if ($alg !== 'HS256' || !is_array($datos)) {
            return null;
        }
        if (!isset($datos['exp']) || $datos['exp'] < time()) {
            return null;
        }
        return $datos;
    }

    private static function b64(string $bytes): string
    {
        return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
    }

    private static function desb64(string $texto): string
    {
        return (string) base64_decode(strtr($texto, '-_', '+/'), true);
    }
}
