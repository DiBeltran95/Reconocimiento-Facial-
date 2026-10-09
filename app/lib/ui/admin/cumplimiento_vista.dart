import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import 'asistencia_page.dart';
import 'contexto_admin.dart';
import 'selector_sede.dart';

enum _Periodo {
  semana('Esta semana'),
  semanaPasada('Semana pasada'),
  quincena('Últimos 15 días'),
  mes('Este mes'),
  otro('Elegir…');

  const _Periodo(this.etiqueta);
  final String etiqueta;
}

enum _Orden { peor, mejor, nombre }

/// ¿Quién cumple su horario? Resumen del período por persona.
class CumplimientoVista extends StatefulWidget {
  const CumplimientoVista({super.key});

  @override
  State<CumplimientoVista> createState() => _CumplimientoVistaState();
}

class _CumplimientoVistaState extends State<CumplimientoVista> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  _Periodo _periodo = _Periodo.semana;
  late DateTimeRange _rango = _rangoDe(_Periodo.semana);
  ReporteCumplimiento? _reporte;
  String? _error;
  bool _cargando = false;
  _Orden _orden = _Orden.peor;
  int _sedeCargada = -1;

  @override
  void initState() {
    super.initState();
    _ctx.addListener(_alCambiarSede);
    _cargar();
  }

  @override
  void dispose() {
    _ctx.removeListener(_alCambiarSede);
    super.dispose();
  }

  void _alCambiarSede() {
    if (_ctx.sede.id != _sedeCargada) _cargar();
  }

  DateTimeRange _rangoDe(_Periodo p) {
    final hoy = DateUtils.dateOnly(DateTime.now());
    final lunes = Formato.lunes(hoy);
    return switch (p) {
      _Periodo.semana => DateTimeRange(start: lunes, end: hoy),
      _Periodo.semanaPasada => DateTimeRange(
          start: lunes.subtract(const Duration(days: 7)), end: lunes.subtract(const Duration(days: 1))),
      _Periodo.quincena => DateTimeRange(start: hoy.subtract(const Duration(days: 14)), end: hoy),
      _Periodo.mes => DateTimeRange(start: DateTime(hoy.year, hoy.month), end: hoy),
      _Periodo.otro => _rango,
    };
  }

  Future<void> _elegirPeriodo(_Periodo p) async {
    if (p == _Periodo.otro) {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
        lastDate: DateTime.now(),
        initialDateRange: _rango,
        helpText: 'Período (máximo 31 días)',
      );
      if (r == null) return;
      if (r.duration.inDays > 30) {
        if (mounted) avisar(context, 'Elige un período de máximo 31 días', error: true);
        return;
      }
      setState(() {
        _periodo = p;
        _rango = r;
      });
    } else {
      setState(() {
        _periodo = p;
        _rango = _rangoDe(p);
      });
    }
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final sede = _ctx.sede;
    try {
      final r = await _ctx.api.reporteCumplimiento(sedeId: sede.id, desde: _rango.start, hasta: _rango.end);
      if (mounted) {
        setState(() {
          _reporte = r;
          _error = null;
          _sedeCargada = sede.id;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _reporte;
    final filas = [...?r?.empleados.where((e) => e.diasProgramados > 0)];
    final sinTurno = (r?.empleados.length ?? 0) - filas.length;
    filas.sort((a, b) => switch (_orden) {
          _Orden.peor => (a.porcentaje ?? 101).compareTo(b.porcentaje ?? 101),
          _Orden.mejor => (b.porcentaje ?? -1).compareTo(a.porcentaje ?? -1),
          _Orden.nombre => a.nombre.compareTo(b.nombre),
        });

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.xl),
        children: [
          const SelectorSede(),
          const SizedBox(height: Espacio.sm),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _Periodo.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: Espacio.xs),
              itemBuilder: (_, i) {
                final p = _Periodo.values[i];
                return ChoiceChip(label: Text(p.etiqueta), selected: _periodo == p, onSelected: (_) => _elegirPeriodo(p));
              },
            ),
          ),
          Text(
            '${DateFormat("d MMM", 'es_CO').format(_rango.start)} – ${DateFormat("d MMM y", 'es_CO').format(_rango.end)}',
            style: Hud.mono(tam: 12, color: context.sem.textoSuave, espaciado: 0.5),
          ),
          const SizedBox(height: Espacio.md),
          if (_cargando && r == null)
            const Padding(padding: EdgeInsets.all(Espacio.xl), child: Center(child: CircularProgressIndicator()))
          else if (_error != null && r == null)
            EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudo cargar', mensaje: _error, accion: _cargar)
          else if (r != null) ...[
            if (_cargando) const LinearProgressIndicator(),
            _Resumen(reporte: r),
            const SizedBox(height: Espacio.md),
            const _Leyenda(),
            const SizedBox(height: Espacio.md),
            Row(
              children: [
                Etiqueta('Personal con turno · ${filas.length}'),
                const Spacer(),
                PopupMenuButton<_Orden>(
                  tooltip: 'Ordenar',
                  initialValue: _orden,
                  onSelected: (o) => setState(() => _orden = o),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _Orden.peor, child: Text('Menor cumplimiento primero')),
                    PopupMenuItem(value: _Orden.mejor, child: Text('Mayor cumplimiento primero')),
                    PopupMenuItem(value: _Orden.nombre, child: Text('Por nombre')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(Espacio.sm),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.sort_rounded, size: 20), SizedBox(width: 4), Text('Ordenar')]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espacio.xs),
            if (filas.isEmpty)
              const EstadoVacio(
                icono: Icons.schedule_rounded,
                titulo: 'Nadie tiene horario en este período',
                mensaje: 'Asigna rotaciones en la pestaña Horarios para medir el cumplimiento.',
              )
            else
              for (final f in filas)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espacio.xs),
                  child: _FilaPersona(fila: f, alTocar: () => _detalle(f)),
                ),
            if (sinTurno > 0)
              Padding(
                padding: const EdgeInsets.only(top: Espacio.sm),
                child: Text(
                  '$sinTurno persona(s) sin horario en este período no se evalúan.',
                  style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _detalle(FilaCumplimiento f) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _DetallePersona(fila: f),
    );
  }
}

Color colorCumplimiento(BuildContext context, EstadoCumplimiento? e) {
  final s = context.sem;
  return switch (e) {
    EstadoCumplimiento.cumple => s.entrada,
    EstadoCumplimiento.tarde || EstadoCumplimiento.sinLlegar || EstadoCumplimiento.sinSalida => s.alerta,
    EstadoCumplimiento.salidaAnticipada || EstadoCumplimiento.incompleto || EstadoCumplimiento.ausente => s.peligro,
    EstadoCumplimiento.extra => s.salida,
    _ => s.borde,
  };
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.reporte});
  final ReporteCumplimiento reporte;

  @override
  Widget build(BuildContext context) {
    final s = context.sem;
    final r = reporte;
    final p = r.porcentaje;
    final color = p == null ? s.textoSuave : (p >= 90 ? s.entrada : p >= 75 ? s.alerta : s.peligro);
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Espacio.md),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  height: 104,
                  child: Semantics(
                    label: 'Cumplimiento general ${p ?? 0} por ciento',
                    excludeSemantics: true,
                    child: CustomPaint(
                      painter: _Anillo(valor: (p ?? 0) / 100, color: color, pista: s.borde),
                      child: Center(
                        child: Text(p == null ? '—' : '$p%', style: Hud.titulo(tam: 26, color: context.colores.onSurface)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Espacio.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Etiqueta('Cumplimiento general', color: color),
                      const SizedBox(height: Espacio.xs),
                      Text(
                        '${r.diasCumplidos} de ${r.diasProgramados} jornadas programadas se cumplieron.',
                        style: context.textos.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Espacio.xs),
        GrillaMetricas(tiles: [
          Metrica(etiqueta: 'Tardanzas', valor: r.tardanzas, total: r.diasProgramados, color: s.alerta, icono: Icons.timer_outlined),
          Metrica(etiqueta: 'Ausencias', valor: r.ausencias, total: r.diasProgramados, color: s.peligro, icono: Icons.person_off_outlined),
          Metrica(etiqueta: 'Salidas antes', valor: r.salidasAnticipadas, total: r.diasProgramados, color: s.salida, icono: Icons.logout_rounded),
          Metrica(etiqueta: 'Cumplidas', valor: r.diasCumplidos, total: r.diasProgramados, color: s.entrada, icono: Icons.verified_rounded),
        ]),
      ],
    );
  }
}

class _Anillo extends CustomPainter {
  _Anillo({required this.valor, required this.color, required this.pista});
  final double valor;
  final Color color;
  final Color pista;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - 6);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, base..color = pista);
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * valor.clamp(0, 1),
      false,
      base
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * valor.clamp(0, 1), false, base..color = color..maskFilter = null);
  }

  @override
  bool shouldRepaint(_Anillo v) => v.valor != valor || v.color != color;
}

class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) {
    final items = [
      (EstadoCumplimiento.cumple, 'Cumple'),
      (EstadoCumplimiento.tarde, 'Tarde / sin salida'),
      (EstadoCumplimiento.ausente, 'Falta / salió antes'),
      (EstadoCumplimiento.libre, 'Libre / pendiente'),
    ];
    return Wrap(
      spacing: Espacio.md,
      runSpacing: Espacio.xs,
      children: [
        for (final (e, t) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Punto(color: colorCumplimiento(context, e), lleno: e != EstadoCumplimiento.libre),
              const SizedBox(width: 6),
              Text(t, style: context.textos.bodySmall),
            ],
          ),
      ],
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.color, this.lleno = true});
  final Color color;
  final bool lleno;
  static const double tam = 12;

  @override
  Widget build(BuildContext context) => Container(
        width: tam,
        height: tam,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: lleno ? color : Colors.transparent,
          border: Border.all(color: color, width: 1.5),
          boxShadow: lleno ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 5)] : null,
        ),
      );
}

class _FilaPersona extends StatelessWidget {
  const _FilaPersona({required this.fila, required this.alTocar});
  final FilaCumplimiento fila;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final s = context.sem;
    final p = fila.porcentaje;
    final color = p == null ? s.textoSuave : (p >= 90 ? s.entrada : p >= 75 ? s.alerta : s.peligro);
    final novedades = [
      if (fila.tardanzas > 0) '${fila.tardanzas} tarde (${Formato.duracion(fila.minutosTarde)})',
      if (fila.ausencias > 0) '${fila.ausencias} falta${fila.ausencias == 1 ? '' : 's'}',
      if (fila.salidasAnticipadas > 0) '${fila.salidasAnticipadas} salida${fila.salidasAnticipadas == 1 ? '' : 's'} antes',
      if (fila.incompletos > 0) '${fila.incompletos} incompleto${fila.incompletos == 1 ? '' : 's'}',
    ];
    return Card(
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(Redondeo.lg),
        child: Padding(
          padding: const EdgeInsets.all(Espacio.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AvatarEmpleado(nombre: fila.nombre, tam: 40, anillo: color),
                  const SizedBox(width: Espacio.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fila.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textos.titleMedium),
                        Text(
                          novedades.isEmpty ? 'Sin novedades' : novedades.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textos.bodySmall?.copyWith(color: novedades.isEmpty ? s.entrada : s.textoSuave),
                        ),
                      ],
                    ),
                  ),
                  Text(p == null ? '—' : '$p%', style: Hud.titulo(tam: 22, color: color)),
                ],
              ),
              const SizedBox(height: Espacio.sm),
              Semantics(
                label: 'Días: ${fila.dias.map((d) => d.estado?.etiqueta ?? 'sin datos').join(', ')}',
                excludeSemantics: true,
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final d in fila.dias)
                      Tooltip(
                        message: '${DateFormat("EEE d", 'es_CO').format(d.fecha)}: ${d.estado?.etiqueta ?? '—'}',
                        child: _Punto(
                          color: colorCumplimiento(context, d.estado),
                          lleno: d.estado != null &&
                              d.estado != EstadoCumplimiento.libre &&
                              d.estado != EstadoCumplimiento.pendiente,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetallePersona extends StatelessWidget {
  const _DetallePersona({required this.fila});
  final FilaCumplimiento fila;

  @override
  Widget build(BuildContext context) {
    final s = context.sem;
    Widget dato(String t, String v, [Color? c]) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(t, style: context.textos.bodyMedium)),
              Text(v, style: Hud.mono(tam: 14, color: c ?? context.colores.onSurface, peso: FontWeight.w700, espaciado: 0)),
            ],
          ),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.xl),
        children: [
          Text(fila.nombre, style: context.textos.titleLarge),
          Text([fila.documento, if (fila.cargo != null) fila.cargo!].join(' · '),
              style: context.textos.bodyMedium?.copyWith(color: s.textoSuave)),
          const SizedBox(height: Espacio.md),
          dato('Cumplimiento', fila.porcentaje == null ? '—' : '${fila.porcentaje}%'),
          dato('Jornadas programadas', '${fila.diasProgramados}'),
          dato('Jornadas cumplidas', '${fila.diasCumplidos}', s.entrada),
          dato('Llegadas tarde', '${fila.tardanzas} · ${Formato.duracion(fila.minutosTarde)}', s.alerta),
          dato('Salidas anticipadas', '${fila.salidasAnticipadas} · ${Formato.duracion(fila.minutosAnticipados)}', s.salida),
          dato('Ausencias', '${fila.ausencias}', s.peligro),
          dato('Jornadas incompletas', '${fila.incompletos}', s.peligro),
          dato('Horas programadas', Formato.duracion(fila.minutosProgramados)),
          dato('Horas trabajadas', Formato.duracion(fila.minutosTrabajados)),
          const SizedBox(height: Espacio.lg),
          const Etiqueta('Día a día'),
          const SizedBox(height: Espacio.sm),
          for (final d in fila.dias.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _Punto(color: colorCumplimiento(context, d.estado), lleno: d.estado != null && d.estado != EstadoCumplimiento.libre),
                  const SizedBox(width: Espacio.sm),
                  SizedBox(
                    width: 110,
                    child: Text(Formato.fechaCorta(d.fecha), style: Hud.mono(tam: 12.5, color: context.colores.onSurface, espaciado: 0)),
                  ),
                  Text(d.estado?.etiqueta ?? '—', style: context.textos.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
