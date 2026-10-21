<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Ids;

/**
 * Sedes de la empresa. Son las MISMAS de Inventario (tabla `sedes`): crear una
 * aquí la crea allá, y viceversa. Solo el administrador de la empresa las
 * gestiona; el cupo del plan lo exige la base (LIMITE_PLAN → 409).
 *
 * El listado está en SistemaControlador::sedes (GET /api/sedes).
 */
final class SedesControlador
{
    public static function crear(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        $d = self::validar($req->json(), true);
        $uuid = Ids::uuid();
        Db::query(
            'INSERT INTO sedes (uuid, empresa_id, nombre, codigo, direccion, telefono) VALUES (?, ?, ?, ?, ?, ?)',
            [$uuid, $admin['empresa_id'], $d['nombre'], $d['codigo'], $d['direccion'], $d['telefono']],
        );
        Response::json(['sede' => self::aJson(self::buscar((int) Db::pdo()->lastInsertId(), $admin))], 201);
    }

    public static function actualizar(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        $sede = self::buscar($req->param('id'), $admin);
        $d = self::validar($req->json() + [
            'nombre' => $sede['nombre'],
            'codigo' => $sede['codigo'],
        ], false);

        $activo = array_key_exists('activo', $req->json()) ? ((bool) $req->json()['activo'] ? 1 : 0) : (int) $sede['activo'];
        if ($activo === 0 && (int) $sede['es_principal'] === 1) {
            throw HttpError::validacion('La sede principal no se puede desactivar', 'activo');
        }
        if ($activo === 0) {
            // Un kiosco amarrado a una sede inactiva quedaría marcando en el vacío.
            $kioscos = (int) Db::valor('SELECT COUNT(*) FROM asis_dispositivos WHERE sede_id = ? AND activo = 1', [$sede['id']]);
            if ($kioscos > 0) {
                throw HttpError::validacion("Desvincula primero los $kioscos kiosco(s) de esta sede", 'activo');
            }
        }

        Db::query(
            'UPDATE sedes SET nombre = ?, codigo = ?, direccion = ?, telefono = ?, activo = ? WHERE id = ?',
            [$d['nombre'], $d['codigo'], $d['direccion'] ?? $sede['direccion'], $d['telefono'] ?? $sede['telefono'], $activo, $sede['id']],
        );
        Response::json(['sede' => self::aJson(self::buscar((int) $sede['id'], $admin))]);
    }

    public static function aJson(array $s): array
    {
        return [
            'id'           => (int) $s['id'],
            'uuid'         => $s['uuid'] ?? null,
            'nombre'       => $s['nombre'],
            'codigo'       => $s['codigo'],
            'direccion'    => $s['direccion'] ?? null,
            'telefono'     => $s['telefono'] ?? null,
            'es_principal' => (bool) ($s['es_principal'] ?? false),
            'activo'       => (bool) ($s['activo'] ?? true),
        ];
    }

    private static function buscar(int $id, array $admin): array
    {
        return Db::fila(
            'SELECT id, uuid, nombre, codigo, direccion, telefono, es_principal, activo
               FROM sedes WHERE id = ? AND empresa_id = ? AND deleted_at IS NULL',
            [$id, $admin['empresa_id']],
        ) ?? throw HttpError::noEncontrado('Sede');
    }

    private static function validar(array $d, bool $nueva): array
    {
        $nombre = trim(preg_replace('/\s+/u', ' ', (string) ($d['nombre'] ?? '')));
        if (mb_strlen($nombre) < 2 || mb_strlen($nombre) > 120) {
            throw HttpError::validacion('Ponle un nombre a la sede (2 a 120 caracteres)', 'nombre');
        }
        $codigo = strtoupper(trim((string) ($d['codigo'] ?? '')));
        if ($codigo === '' && $nueva) {
            $codigo = self::codigoSugerido($nombre);
        }
        if (!preg_match('/^[A-Z0-9]{2,10}$/', $codigo)) {
            throw HttpError::validacion('El código lleva de 2 a 10 letras o números', 'codigo');
        }
        $texto = static function (mixed $v, int $max): ?string {
            $t = trim((string) ($v ?? ''));
            return $t === '' ? null : mb_substr($t, 0, $max);
        };
        return [
            'nombre'    => $nombre,
            'codigo'    => $codigo,
            'direccion' => $texto($d['direccion'] ?? null, 200),
            'telefono'  => $texto($d['telefono'] ?? null, 30),
        ];
    }

    /** «Sede Norte» → «NOR». La misma regla que el backend de Inventario. */
    public static function codigoSugerido(string $nombre): string
    {
        $ascii = iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $nombre) ?: $nombre;
        $limpio = preg_replace('/[^A-Z0-9]/', '', preg_replace('/\bSEDE\b/', '', strtoupper($ascii)));
        return str_pad(substr($limpio ?: 'PRI', 0, 3), 2, '0');
    }
}
