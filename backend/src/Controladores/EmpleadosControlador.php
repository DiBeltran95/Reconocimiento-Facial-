<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Fotos;
use App\Servicios\Horarios;
use App\Servicios\Tiempo;

final class EmpleadosControlador
{
    public static function listar(Request $req): never
    {
        $admin = Auth::admin($req);
        $sedeId = (int) $req->query('sede_id', '0');
        $inactivos = $req->query('inactivos') === '1';

        $where = [];
        $params = [];
        if ($sedeId > 0) {
            Auth::exigirSede($admin, $sedeId);
            $where[] = 'sede_id = ?';
            $params[] = $sedeId;
        } elseif ($admin['sedes'] !== null) {
            if ($admin['sedes'] === []) {
                Response::json(['empleados' => []]);
            }
            $where[] = 'sede_id IN (' . Db::enLista($admin['sedes']) . ')';
            array_push($params, ...$admin['sedes']);
        }
        if (!$inactivos) {
            $where[] = 'activo = 1';
        }
        $sql = 'SELECT id, sede_id, documento, nombre, cargo, activo FROM asis_empleados'
            . ($where ? ' WHERE ' . implode(' AND ', $where) : '')
            . ' ORDER BY nombre';

        $filas = Db::filas($sql, $params);
        // Turno de esta semana de cada uno (una sola consulta para todos).
        $semana = Horarios::lunes(Tiempo::hoyLocal());
        $plan = Horarios::porSemana(array_map(static fn ($e) => (int) $e['id'], $filas), [$semana]);
        Response::json(['empleados' => array_map(static fn (array $e) => self::aJson($e) + [
            'turno_semana' => self::turnoCorto($plan[(int) $e['id']][$semana]['horario'] ?? null),
        ], $filas)]);
    }

    public static function ver(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'));
        Auth::exigirSede($admin, (int) $empleado['sede_id']);
        Response::json(['empleado' => self::aJson($empleado)]);
    }

    public static function crear(Request $req): never
    {
        $admin = Auth::admin($req);
        $d = self::validar($req->json());
        Auth::exigirSede($admin, $d['sede_id']);

        $existente = Db::fila(
            'SELECT id, nombre, activo, sede_id FROM asis_empleados WHERE documento = ?',
            [$d['documento']],
        );
        if ($existente !== null && (int) $existente['activo'] === 1) {
            throw new HttpError(409, "Ya existe un empleado con ese documento: {$existente['nombre']}", ['campo' => 'documento']);
        }

        if ($existente !== null) {
            // Reingreso: se reactiva el mismo registro y conserva su historial.
            Db::query(
                'UPDATE asis_empleados SET sede_id = ?, nombre = ?, cargo = ?, activo = 1 WHERE id = ?',
                [$d['sede_id'], $d['nombre'], $d['cargo'], $existente['id']],
            );
            $id = (int) $existente['id'];
            $estado = 200;
        } else {
            Db::query(
                'INSERT INTO asis_empleados (sede_id, documento, nombre, cargo) VALUES (?, ?, ?, ?)',
                [$d['sede_id'], $d['documento'], $d['nombre'], $d['cargo']],
            );
            $id = (int) Db::pdo()->lastInsertId();
            $estado = 201;
        }

        Response::json([
            'empleado'   => self::aJson(self::buscar($id)),
            'reactivado' => $existente !== null,
        ], $estado);
    }

    public static function actualizar(Request $req): never
    {
        $admin = Auth::admin($req);
        $actual = self::buscar($req->param('id'));
        Auth::exigirSede($admin, (int) $actual['sede_id']);

        $d = self::validar($req->json() + [
            'sede_id'   => $actual['sede_id'],
            'documento' => $actual['documento'],
            'nombre'    => $actual['nombre'],
            'cargo'     => $actual['cargo'],
        ]);
        Auth::exigirSede($admin, $d['sede_id']);

        $duplicado = Db::valor(
            'SELECT nombre FROM asis_empleados WHERE documento = ? AND id <> ?',
            [$d['documento'], $actual['id']],
        );
        if ($duplicado !== null) {
            throw new HttpError(409, "Ese documento ya pertenece a: $duplicado", ['campo' => 'documento']);
        }

        Db::query(
            'UPDATE asis_empleados SET sede_id = ?, documento = ?, nombre = ?, cargo = ? WHERE id = ?',
            [$d['sede_id'], $d['documento'], $d['nombre'], $d['cargo'], $actual['id']],
        );
        Response::json(['empleado' => self::aJson(self::buscar((int) $actual['id']))]);
    }

    /** Baja lógica: conserva el historial pero borra sus datos biométricos. */
    public static function desactivar(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'));
        Auth::exigirSede($admin, (int) $empleado['sede_id']);

        Db::query('UPDATE asis_empleados SET activo = 0 WHERE id = ?', [$empleado['id']]);
        Fotos::borrarTodas((int) $empleado['id']);
        Response::sinContenido();
    }

    /** Reemplaza las fotos del rostro (multipart, campo `fotos[]`). */
    public static function subirFotos(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'));
        Auth::exigirSede($admin, (int) $empleado['sede_id']);
        if ((int) $empleado['activo'] !== 1) {
            throw HttpError::validacion('El empleado está inactivo');
        }

        $subidas = Fotos::subidas('fotos');
        if ($subidas === []) {
            $subidas = Fotos::subidas('foto');
        }
        $fotos = Fotos::reemplazar((int) $empleado['id'], $subidas);
        self::marcarCambio((int) $empleado['id']);

        Response::json(['fotos' => $fotos]);
    }

    public static function borrarFotos(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::buscar($req->param('id'));
        Auth::exigirSede($admin, (int) $empleado['sede_id']);

        Fotos::borrarTodas((int) $empleado['id']);
        self::marcarCambio((int) $empleado['id']);
        Response::sinContenido();
    }

    /** Descarga una foto. Kioscos: solo de su sede. Administradores: de sus sedes. */
    public static function foto(Request $req): never
    {
        $quien = Auth::adminODispositivo($req);
        $empleado = self::buscar($req->param('id'));
        $sedeId = (int) $empleado['sede_id'];

        $permitido = $quien['tipo'] === 'dispositivo'
            ? $quien['sede_id'] === $sedeId
            : Auth::puedeSede($quien, $sedeId);
        if (!$permitido) {
            throw HttpError::prohibido();
        }

        $ruta = Fotos::ruta((int) $empleado['id'], $req->param('n'));
        if ($ruta === null) {
            throw HttpError::noEncontrado('Foto');
        }
        Response::archivo($ruta, 'image/jpeg', $req->header('If-None-Match'));
    }

    // ---------------------------------------------------------------------

    private static function turnoCorto(?array $h): ?array
    {
        return $h === null ? null : ['id' => $h['id'], 'nombre' => $h['nombre'], 'bloques' => $h['bloques']];
    }

    public static function aJson(array $e): array
    {
        return [
            'id'        => (int) $e['id'],
            'sede_id'   => (int) $e['sede_id'],
            'documento' => $e['documento'],
            'nombre'    => $e['nombre'],
            'cargo'     => $e['cargo'],
            'activo'    => (int) $e['activo'] === 1,
            'fotos'     => Fotos::listar((int) $e['id']),
        ];
    }

    private static function buscar(int $id): array
    {
        $empleado = Db::fila(
            'SELECT id, sede_id, documento, nombre, cargo, activo FROM asis_empleados WHERE id = ?',
            [$id],
        );
        if ($empleado === null) {
            throw HttpError::noEncontrado('Empleado');
        }
        return $empleado;
    }

    /** Cambiar `updated_at` avisa a los kioscos que deben volver a sincronizarlo. */
    private static function marcarCambio(int $id): void
    {
        Db::query('UPDATE asis_empleados SET updated_at = CURRENT_TIMESTAMP(3) WHERE id = ?', [$id]);
    }

    /** @return array{sede_id:int, documento:string, nombre:string, cargo:?string} */
    private static function validar(array $datos): array
    {
        $documento = preg_replace('/[\s.]/', '', (string) ($datos['documento'] ?? ''));
        if (!preg_match('/^[A-Za-z0-9-]{3,20}$/', $documento)) {
            throw HttpError::validacion('Documento inválido: 3 a 20 letras o números, sin puntos', 'documento');
        }

        $nombre = trim(preg_replace('/\s+/u', ' ', (string) ($datos['nombre'] ?? '')));
        if (mb_strlen($nombre) < 3 || mb_strlen($nombre) > 120) {
            throw HttpError::validacion('Escribe el nombre completo (3 a 120 caracteres)', 'nombre');
        }

        $cargo = trim(preg_replace('/\s+/u', ' ', (string) ($datos['cargo'] ?? '')));
        if (mb_strlen($cargo) > 60) {
            throw HttpError::validacion('El cargo admite máximo 60 caracteres', 'cargo');
        }

        $sedeId = (int) ($datos['sede_id'] ?? 0);
        $sedeValida = Db::valor(
            'SELECT 1 FROM sedes WHERE id = ? AND activo = 1 AND deleted_at IS NULL',
            [$sedeId],
        );
        if ($sedeValida === null) {
            throw HttpError::validacion('Selecciona una sede válida', 'sede_id');
        }

        return [
            'sede_id'   => $sedeId,
            'documento' => strtoupper($documento),
            'nombre'    => $nombre,
            'cargo'     => $cargo === '' ? null : $cargo,
        ];
    }
}
