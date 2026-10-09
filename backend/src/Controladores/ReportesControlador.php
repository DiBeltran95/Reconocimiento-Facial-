<?php
declare(strict_types=1);

namespace App\Controladores;

use App\Auth\Auth;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Servicios\Cumplimiento;
use App\Servicios\Reportes;
use App\Servicios\Tiempo;

final class ReportesControlador
{
    private const MAX_DIAS_RANGO = 62;
    private const MAX_DIAS_CUMPLIMIENTO = 31;

    public static function dia(Request $req): never
    {
        $admin = Auth::admin($req);
        $sedeId = self::sede($req, $admin);
        $fecha = Tiempo::validarFecha($req->query('fecha'));
        Response::json(Reportes::dia($sedeId, $fecha));
    }

    public static function diaCsv(Request $req): never
    {
        $admin = Auth::admin($req);
        $sedeId = self::sede($req, $admin);
        $fecha = Tiempo::validarFecha($req->query('fecha'));
        $reporte = Reportes::dia($sedeId, $fecha);

        Response::csv(
            sprintf('asistencia_%s_%s.csv', $reporte['sede']['codigo'], $fecha),
            Reportes::ENCABEZADOS_CSV,
            array_map([Reportes::class, 'filaCsv'], $reporte['empleados']),
        );
    }

    /** Consolidado para nómina: una fila por empleado y día. */
    public static function rangoCsv(Request $req): never
    {
        $admin = Auth::admin($req);
        $sedeId = self::sede($req, $admin);
        [$desde, $hasta] = self::rango($req, self::MAX_DIAS_RANGO);

        $filas = [];
        $codigo = '';
        for ($d = new \DateTimeImmutable($desde); $d->format('Y-m-d') <= $hasta; $d = $d->modify('+1 day')) {
            $reporte = Reportes::dia($sedeId, $d->format('Y-m-d'));
            $codigo = $reporte['sede']['codigo'];
            foreach ($reporte['empleados'] as $e) {
                $filas[] = array_merge([$reporte['fecha']], Reportes::filaCsv($e));
            }
        }

        Response::csv(
            sprintf('asistencia_%s_%s_a_%s.csv', $codigo, $desde, $hasta),
            array_merge(['Fecha'], Reportes::ENCABEZADOS_CSV),
            $filas,
        );
    }

    /** ¿Quién cumple su horario? Resumen por empleado del período. */
    public static function cumplimiento(Request $req): never
    {
        $admin = Auth::admin($req);
        $sedeId = self::sede($req, $admin);
        [$desde, $hasta] = self::rango($req, self::MAX_DIAS_CUMPLIMIENTO);
        Response::json(Reportes::cumplimiento($sedeId, $desde, $hasta));
    }

    public static function cumplimientoCsv(Request $req): never
    {
        $admin = Auth::admin($req);
        $sedeId = self::sede($req, $admin);
        [$desde, $hasta] = self::rango($req, self::MAX_DIAS_CUMPLIMIENTO);
        $r = Reportes::cumplimiento($sedeId, $desde, $hasta);

        $encabezados = ['Documento', 'Empleado', 'Cargo', '% cumplimiento', 'Días programados', 'Días cumplidos',
            'Tardanzas', 'Min. tarde', 'Salidas anticipadas', 'Min. anticipados', 'Ausencias', 'Incompletos',
            'Horas programadas', 'Horas trabajadas'];
        foreach ($r['dias'] as $f) {
            $encabezados[] = $f;
        }
        $filas = array_map(static fn (array $e) => array_merge([
            $e['documento'], $e['nombre'], (string) $e['cargo'],
            $e['porcentaje'] === null ? '' : $e['porcentaje'] . '%',
            $e['dias_programados'], $e['dias_cumplidos'], $e['tardanzas'], $e['minutos_tarde'],
            $e['salidas_anticipadas'], $e['minutos_anticipados'], $e['ausencias'], $e['incompletos'],
            Reportes::horasTexto($e['minutos_programados']), Reportes::horasTexto($e['minutos_trabajados']),
        ], array_map(
            static fn (array $d) => $d['estado'] === null ? '' : (Cumplimiento::ETIQUETAS[$d['estado']] ?? $d['estado']),
            $e['dias'],
        )), $r['empleados']);

        Response::csv(sprintf('cumplimiento_%s_%s_a_%s.csv', $r['sede']['codigo'] ?? 'sede', $desde, $hasta), $encabezados, $filas);
    }

    private static function sede(Request $req, array $admin): int
    {
        $sedeId = (int) $req->query('sede_id', '0');
        if ($sedeId <= 0) {
            throw HttpError::validacion('Indica la sede', 'sede_id');
        }
        Auth::exigirSede($admin, $sedeId);
        return $sedeId;
    }

    private static function rango(Request $req, int $maximo): array
    {
        $desde = Tiempo::validarFecha($req->query('desde'), 'desde');
        $hasta = Tiempo::validarFecha($req->query('hasta'), 'hasta');
        if ($hasta < $desde) {
            throw HttpError::validacion('La fecha final debe ser posterior a la inicial', 'hasta');
        }
        $dias = (int) (new \DateTimeImmutable($desde))->diff(new \DateTimeImmutable($hasta))->days + 1;
        if ($dias > $maximo) {
            throw HttpError::validacion("El rango máximo es de $maximo días", 'hasta');
        }
        return [$desde, $hasta];
    }
}
