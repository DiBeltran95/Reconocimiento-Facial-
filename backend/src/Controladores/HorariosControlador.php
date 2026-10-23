<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Db;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Horarios;
use App\Servicios\Tiempo;

/**
 * Turnos, rotaciones semanales y ajustes puntuales (solo administrativos).
 * Los turnos son de la empresa: los crea cualquier administrativo, pero
 * editarlos o archivarlos solo el ADMIN (un turno lo pueden usar sedes que el
 * gerente no gestiona).
 */
final class HorariosControlador
{
    private const MAX_SECUENCIA = 8;
    private const MAX_SEMANAS = 26;

    public static function listar(Request $req): never
    {
        Auth::admin($req);
        $inactivos = $req->query('inactivos') === '1';
        $lista = array_values(array_filter(Horarios::todos(), static fn ($h) => $inactivos || $h['activo']));
        usort($lista, static fn ($a, $b) => strcmp($a['nombre'], $b['nombre']));
        Response::json(['horarios' => $lista]);
    }

    public static function crear(Request $req): never
    {
        $admin = Auth::admin($req);
        $d = self::validar($req->json());
        Db::query(
            'INSERT INTO asis_horarios (empresa_id, nombre, bloques, dias, tolerancia_min) VALUES (?, ?, ?, ?, ?)',
            [$admin['empresa_id'], $d['nombre'], $d['bloques'], $d['dias'], $d['tolerancia_min']],
        );
        $id = (int) Db::pdo()->lastInsertId();
        Horarios::limpiarCache();
        Response::json(['horario' => Horarios::todos()[$id]], 201);
    }

    public static function actualizar(Request $req): never
    {
        Auth::adminEmpresa($req);
        $id = $req->param('id');
        $actual = Horarios::todos()[$id] ?? throw HttpError::noEncontrado('Turno');
        $d = self::validar($req->json() + $actual);
        Db::query(
            'UPDATE asis_horarios SET nombre = ?, bloques = ?, dias = ?, tolerancia_min = ?, activo = 1 WHERE id = ?',
            [$d['nombre'], $d['bloques'], $d['dias'], $d['tolerancia_min'], $id],
        );
        Horarios::limpiarCache();
        Response::json(['horario' => Horarios::todos()[$id]]);
    }

    /** Se archiva (no se borra): el historial de cumplimiento lo sigue usando. */
    public static function archivar(Request $req): never
    {
        $admin = Auth::adminEmpresa($req);
        Db::query('UPDATE asis_horarios SET activo = 0 WHERE id = ? AND empresa_id = ?', [$req->param('id'), $admin['empresa_id']]);
        Horarios::limpiarCache();
        Response::sinContenido();
    }

    /** Rotación vigente y el turno de las próximas semanas de un empleado. */
    public static function planEmpleado(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::empleado($req->param('id'), $admin);
        $cuantas = max(1, min(self::MAX_SEMANAS, (int) $req->query('semanas', '8')));
        $desde = Horarios::lunes(Tiempo::validarFecha($req->query('desde')));

        $semanas = [];
        $d = new \DateTimeImmutable($desde);
        for ($i = 0; $i < $cuantas; $i++) {
            $semanas[] = $d->modify("+$i week")->format('Y-m-d');
        }
        $plan = Horarios::porSemana([$empleado], $semanas)[$empleado] ?? [];

        $rotacion = Db::fila(
            'SELECT desde, secuencia FROM asis_rotaciones WHERE empleado_id = ? AND desde <= ? ORDER BY desde DESC LIMIT 1',
            [$empleado, end($semanas)],
        );
        Response::json([
            'rotacion' => $rotacion === null ? null : [
                'desde'     => $rotacion['desde'],
                'secuencia' => Horarios::secuencia($rotacion['secuencia']),
            ],
            'semanas'  => array_map(static fn ($s) => ['semana' => $s] + $plan[$s], $semanas),
        ]);
    }

    /** Define (o reemplaza) la rotación desde una semana en adelante. */
    public static function guardarRotacion(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::empleado($req->param('id'), $admin);
        $datos = $req->json();
        self::aplicarRotacion([$empleado], self::validarSecuencia($datos['secuencia'] ?? []), self::lunesDe($datos['desde'] ?? null));
        Response::sinContenido();
    }

    /** Misma rotación para varios empleados (p. ej. todo un equipo). */
    public static function asignar(Request $req): never
    {
        $admin = Auth::admin($req);
        $datos = $req->json();
        $ids = array_values(array_unique(array_map('intval', (array) ($datos['empleados'] ?? []))));
        if ($ids === [] || count($ids) > 500) {
            throw HttpError::validacion('Selecciona entre 1 y 500 empleados', 'empleados');
        }
        $encontrados = Db::filas(
            'SELECT id, sede_id FROM empleados WHERE id IN (' . Db::enLista($ids) . ') AND empresa_id = ?',
            [...$ids, $admin['empresa_id']],
        );
        if (count($encontrados) !== count($ids)) {
            throw HttpError::noEncontrado('Empleado');
        }
        foreach ($encontrados as $e) {
            Auth::exigirSede($admin, (int) $e['sede_id']);
        }
        self::aplicarRotacion($ids, self::validarSecuencia($datos['secuencia'] ?? []), self::lunesDe($datos['desde'] ?? null));
        Response::json(['asignados' => count($ids)]);
    }

    /**
     * Cambia el turno de UNA semana (reemplazos, vacaciones…).
     * {semana, horario_id: int|null}  ·  {semana, quitar: true} vuelve a la rotación.
     */
    public static function ajustarSemana(Request $req): never
    {
        $admin = Auth::admin($req);
        $empleado = self::empleado($req->param('id'), $admin);
        $datos = $req->json();
        $semana = self::lunesDe($datos['semana'] ?? null);

        if (!empty($datos['quitar'])) {
            Db::query('DELETE FROM asis_semanas WHERE empleado_id = ? AND semana = ?', [$empleado, $semana]);
            Response::sinContenido();
        }
        $horario = $datos['horario_id'] ?? null;
        if ($horario !== null) {
            $horario = (int) $horario;
            if (!(Horarios::todos()[$horario]['activo'] ?? false)) {
                throw HttpError::validacion('Ese turno no existe o está archivado', 'horario_id');
            }
        }
        Db::query(
            'INSERT INTO asis_semanas (empleado_id, semana, horario_id) VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE horario_id = VALUES(horario_id)',
            [$empleado, $semana, $horario],
        );
        Response::sinContenido();
    }

    // ---------------------------------------------------------------------

    private static function aplicarRotacion(array $empleados, string $secuencia, string $desde): void
    {
        $pdo = Db::pdo();
        $pdo->beginTransaction();
        try {
            $borrar = $pdo->prepare('DELETE FROM asis_rotaciones WHERE empleado_id = ? AND desde > ?');
            $guardar = $pdo->prepare(
                'INSERT INTO asis_rotaciones (empleado_id, desde, secuencia) VALUES (?, ?, ?)
                 ON DUPLICATE KEY UPDATE secuencia = VALUES(secuencia)',
            );
            foreach ($empleados as $id) {
                // La nueva rotación manda desde esa semana: se descartan las posteriores.
                $borrar->execute([$id, $desde]);
                $guardar->execute([$id, $desde, $secuencia]);
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
    }

    /** Lista de ids de turnos activos → '3,5'. Lista vacía = sin horario desde esa semana. */
    private static function validarSecuencia(mixed $secuencia): string
    {
        if (!is_array($secuencia) || count($secuencia) > self::MAX_SECUENCIA) {
            throw HttpError::validacion('La rotación admite hasta ' . self::MAX_SECUENCIA . ' semanas', 'secuencia');
        }
        $turnos = Horarios::todos();
        $ids = [];
        foreach ($secuencia as $id) {
            $id = (int) $id;
            if (!($turnos[$id]['activo'] ?? false)) {
                throw HttpError::validacion('Uno de los turnos no existe o está archivado', 'secuencia');
            }
            $ids[] = $id;
        }
        return implode(',', $ids);
    }

    private static function lunesDe(mixed $fecha): string
    {
        return Horarios::lunes(Tiempo::validarFecha(is_string($fecha) && $fecha !== '' ? $fecha : null, 'desde'));
    }

    private static function empleado(int $id, array $admin): int
    {
        $e = Db::fila('SELECT id, sede_id FROM empleados WHERE id = ? AND empresa_id = ?', [$id, $admin['empresa_id']]);
        if ($e === null) {
            throw HttpError::noEncontrado('Empleado');
        }
        Auth::exigirSede($admin, (int) $e['sede_id']);
        return (int) $e['id'];
    }

    private static function validar(array $d): array
    {
        $nombre = trim(preg_replace('/\s+/u', ' ', (string) ($d['nombre'] ?? '')));
        if (mb_strlen($nombre) < 2 || mb_strlen($nombre) > 60) {
            throw HttpError::validacion('Ponle un nombre al turno (2 a 60 caracteres)', 'nombre');
        }
        $dias = (int) ($d['dias'] ?? 63);
        if ($dias < 1 || $dias > 127) {
            throw HttpError::validacion('Selecciona al menos un día de la semana', 'dias');
        }
        $tolerancia = (int) ($d['tolerancia_min'] ?? 10);
        if ($tolerancia < 0 || $tolerancia > 120) {
            throw HttpError::validacion('La tolerancia debe estar entre 0 y 120 minutos', 'tolerancia_min');
        }
        return [
            'nombre'         => $nombre,
            'bloques'        => Horarios::normalizarBloques($d['bloques'] ?? ''),
            'dias'           => $dias,
            'tolerancia_min' => $tolerancia,
        ];
    }
}
