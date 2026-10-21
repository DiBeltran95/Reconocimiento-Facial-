<?php
declare(strict_types=1);

namespace App\Servicios;

use App\Db;
use App\Http\HttpError;

/**
 * Plan, uso y límites de una empresa.
 *
 * Los límites los impone la base (triggers de la migración 004 de Inventario y
 * 002 de aquí): ninguno de los dos backends puede saltárselos. Aquí solo se
 * leen para mostrarlos, y se traduce el error de la base a una respuesta
 * clara — idéntica a la del backend de Inventario (docs/PLATAFORMA.md).
 */
final class Plan
{
    private const LIMITES = [
        'sedes'     => 'Tu plan no admite más sedes',
        'personas'  => 'Tu plan no admite más personas en el equipo',
        'productos' => 'Tu plan no admite más productos',
    ];

    /**
     * { codigo, nombre, vence, vencido, sedes:{usados,maximo,lleno}, personas:{…}, productos:{…} }
     * `maximo` null = sin límite.
     */
    public static function deEmpresa(int $empresaId): ?array
    {
        $f = Db::fila('SELECT * FROM v_empresa_uso WHERE empresa_id = ?', [$empresaId]);
        if ($f === null) {
            return null;
        }
        $recurso = static function (mixed $usados, mixed $maximo): array {
            $u = (int) $usados;
            $m = $maximo === null ? null : (int) $maximo;
            return ['usados' => $u, 'maximo' => $m, 'lleno' => $m !== null && $u >= $m];
        };
        return [
            'codigo'    => $f['plan_codigo'],
            'nombre'    => $f['plan_nombre'],
            'vence'     => $f['plan_vence'],
            'vencido'   => (bool) $f['plan_vencido'],
            'sedes'     => $recurso($f['sedes_usadas'], $f['max_sedes']),
            'personas'  => $recurso($f['personas_usadas'], $f['max_personas']),
            'productos' => $recurso($f['productos_usados'], $f['max_productos']),
        ];
    }

    /** @return array<string> Apps habilitadas: ['ASISTENCIA', 'INVENTARIO']. */
    public static function aplicativos(int $empresaId): array
    {
        return array_column(
            Db::filas(
                'SELECT aplicativo FROM empresa_aplicativos WHERE empresa_id = ? AND activo = 1 ORDER BY aplicativo',
                [$empresaId],
            ),
            'aplicativo',
        );
    }

    /**
     * Traduce los errores de regla que lanza la base (SIGNAL 45000) y las
     * llaves únicas, o null si no es uno de ellos.
     */
    public static function traducir(\Throwable $e): ?HttpError
    {
        if (!$e instanceof \PDOException) {
            return null;
        }
        $estado = (string) ($e->errorInfo[0] ?? $e->getCode());
        $mensaje = (string) ($e->errorInfo[2] ?? $e->getMessage());

        if ($estado === '45000') {
            if (preg_match('/LIMITE_PLAN:(\w+)/', $mensaje, $m)) {
                return new HttpError(409, self::LIMITES[$m[1]] ?? 'Alcanzaste el límite de tu plan', [
                    'codigo'  => 'LIMITE_PLAN',
                    'recurso' => $m[1],
                ]);
            }
            if (str_contains($mensaje, 'EMAIL_EN_USO')) {
                return new HttpError(409, 'Ya hay una cuenta con ese correo', ['codigo' => 'EMAIL_EN_USO', 'campo' => 'email']);
            }
            return new HttpError(409, $mensaje !== '' ? $mensaje : 'Operación no permitida', ['codigo' => 'REGLA_NEGOCIO']);
        }
        if ($estado === '23000' && preg_match("/Duplicate entry '(.*)' for key '(\w+)'/", $mensaje, $m)) {
            $valor = preg_replace('/^\d+-/', '', $m[1]);
            $legible = [
                'uk_sedes_empresa_codigo'        => ["Ya hay una sede con el código \"$valor\"", 'codigo'],
                'uk_usuarios_email'              => ["Ya hay una cuenta con el correo \"$valor\"", 'email'],
                'uk_usuarios_empresa_documento'  => ["Ya hay una persona con el documento \"$valor\"", 'documento'],
                'uk_asis_emp_empresa_documento'  => ["Ya hay un empleado con el documento \"$valor\"", 'documento'],
            ][$m[2]] ?? null;
            if ($legible !== null) {
                return new HttpError(409, $legible[0], ['codigo' => 'DUPLICADO', 'campo' => $legible[1]]);
            }
        }
        return null;
    }
}
