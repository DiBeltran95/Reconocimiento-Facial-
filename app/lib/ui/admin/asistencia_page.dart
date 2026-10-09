import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import '../horarios/widgets_horario.dart';
import 'contexto_admin.dart';
import 'cumplimiento_vista.dart';
import 'selector_sede.dart';

/// Pestaña "Asistencia": el día en curso (o uno pasado) y el cumplimiento por período.
class AsistenciaPage extends StatefulWidget {
  const AsistenciaPage({super.key});

  @override
  State<AsistenciaPage> createState() => _AsistenciaPageState();
}

class _AsistenciaPageState extends State<AsistenciaPage> {
  int _modo = 0;

  @override
  Widget build(BuildContext context) {
    return FondoTecnico(
      intensidad: 0.6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.xs),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, icon: Icon(Icons.today_rounded), label: Text('Día')),
                  ButtonSegment(value: 1, icon: Icon(Icons.fact_check_outlined), label: Text('Cumplimiento')),
                ],
                selected: {_modo},
                onSelectionChanged: (s) => setState(() => _modo = s.first),
              ),
            ),
          ),
          Expanded(child: IndexedStack(index: _modo, children: const [VistaDia(), CumplimientoVista()])),
        ],
      ),
    );
  }
}

enum _Filtro {
  todos('Todos'),
  enSede('En la sede'),
  tarde('Tarde'),
  incumplen('Incumplen'),
  ausentes('Ausentes'),
  salieron('Salieron');

  const _Filtro(this.etiqueta);
  final String etiqueta;

  bool acepta(FilaReporte f) => switch (this) {
        todos => true,
        enSede => f.estado == EstadoAsistencia.enSede,
        tarde => f.cumplimiento.estado.esTarde,
        incumplen => f.cumplimiento.estado.incumple,
        ausentes => f.estado == EstadoAsistencia.ausente,
        salieron => f.estado == EstadoAsistencia.salio,
      };
}

/// Reporte del día: quién llegó, a qué hora, si cumplió su turno y quién falta.
class VistaDia extends StatefulWidget {
  const VistaDia({super.key});

  @override
  State<VistaDia> createState() => _VistaDiaState();
}

class _VistaDiaState extends State<VistaDia> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  DateTime _fecha = DateTime.now();
  ReporteDia? _reporte;
  String? _error;
  bool _cargando = true;
  _Filtro _filtro = _Filtro.todos;
  String _busqueda = '';
  Timer? _auto;
  int _sedeCargada = -1;

  @override
  void initState() {
    super.initState();
    _ctx.addListener(_alCambiarSede);
    _cargar();
    // Hoy se refresca solo cada minuto (la gente sigue llegando).
    _auto = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_esHoy && mounted) _cargar(silencioso: true);
    });
  }

  @override
  void dispose() {
    _ctx.removeListener(_alCambiarSede);
    _auto?.cancel();
    super.dispose();
  }

  void _alCambiarSede() {
    if (_ctx.sede.id != _sedeCargada) _cargar();
  }

  bool get _esHoy => DateUtils.isSameDay(_fecha, DateTime.now());

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    final sede = _ctx.sede;
    try {
      final r = await _ctx.api.reporteDia(sedeId: sede.id, fecha: Formato.fechaIso(_fecha));
      if (!mounted) return;
      setState(() {
        _reporte = r;
        _error = null;
        _sedeCargada = sede.id;
      });
    } on ApiError catch (e) {
      if (mounted && !silencioso) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _moverDia(int dias) {
    final nueva = _fecha.add(Duration(days: dias));
    if (nueva.isAfter(DateTime.now())) return;
    setState(() => _fecha = nueva);
    _cargar();
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now(),
      helpText: 'Selecciona el día',
    );
    if (f != null) {
      setState(() => _fecha = f);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _reporte;
    final conTurnos = (r?.conTurno ?? 0) > 0;
    final filtros = _Filtro.values.where((f) => conTurnos || (f != _Filtro.tarde && f != _Filtro.incumplen)).toList();
    final filas = r?.filas
            .where(_filtro.acepta)
            .where((f) =>
                _busqueda.isEmpty ||
                f.nombre.toLowerCase().contains(_busqueda) ||
                f.documento.toLowerCase().contains(_busqueda))
            .toList() ??
        const <FilaReporte>[];

    return RefreshIndicator(
      onRefresh: _cargar,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SelectorSede(),
                  const SizedBox(height: Espacio.sm),
                  _NavegadorFecha(
                    fecha: _fecha,
                    esHoy: _esHoy,
                    alAnterior: () => _moverDia(-1),
                    alSiguiente: _esHoy ? null : () => _moverDia(1),
                    alElegir: _elegirFecha,
                  ),
                  const SizedBox(height: Espacio.md),
                  if (r != null) _Resumen(reporte: r),
                  const SizedBox(height: Espacio.md),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre o documento',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: Espacio.sm),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: filtros.length,
                      separatorBuilder: (_, _) => const SizedBox(width: Espacio.xs),
                      itemBuilder: (_, i) {
                        final f = filtros[i];
                        return ChoiceChip(
                          label: Text(f.etiqueta),
                          selected: _filtro == f,
                          onSelected: (_) => setState(() => _filtro = f),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: Espacio.xs),
                ],
              ),
            ),
          ),
          if (_cargando && r == null)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else if (_error != null && r == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EstadoVacio(
                icono: Icons.cloud_off_rounded,
                titulo: 'No se pudo cargar el reporte',
                mensaje: _error,
                accion: _cargar,
              ),
            )
          else if (filas.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EstadoVacio(
                icono: Icons.event_busy_outlined,
                titulo: r?.total == 0 ? 'Sin personal en esta sede' : 'Nada que mostrar',
                mensaje: r?.total == 0 ? 'Registra empleados en la pestaña Personal.' : 'Ningún empleado coincide con el filtro.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Espacio.md, 0, Espacio.md, Espacio.xl),
              sliver: SliverList.separated(
                itemCount: filas.length,
                separatorBuilder: (_, _) => const SizedBox(height: Espacio.xs),
                itemBuilder: (_, i) => _FilaEmpleado(fila: filas[i], alTocar: () => _detalle(filas[i])),
              ),
            ),
        ],
      ),
    );
  }

  void _detalle(FilaReporte f) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DetalleEmpleado(fila: f),
    );
  }
}

class _NavegadorFecha extends StatelessWidget {
  const _NavegadorFecha({
    required this.fecha,
    required this.esHoy,
    required this.alAnterior,
    required this.alSiguiente,
    required this.alElegir,
  });

  final DateTime fecha;
  final bool esHoy;
  final VoidCallback alAnterior;
  final VoidCallback? alSiguiente;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Row(
        children: [
          IconButton(onPressed: alAnterior, tooltip: 'Día anterior', icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: InkWell(
              onTap: alElegir,
              borderRadius: BorderRadius.circular(Redondeo.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Espacio.sm),
                child: Column(
                  children: [
                    Etiqueta(esHoy ? 'Hoy' : 'Historial'),
                    const SizedBox(height: 2),
                    Text(Formato.fechaLarga(fecha), style: context.textos.titleMedium, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
          IconButton(onPressed: alSiguiente, tooltip: 'Día siguiente', icon: const Icon(Icons.chevron_right_rounded)),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.reporte});
  final ReporteDia reporte;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final r = reporte;
    final total = r.total == 0 ? 1 : r.total;
    final tiles = r.conTurno > 0
        ? [
            Metrica(etiqueta: 'En la sede', valor: r.enSede, total: total, color: context.colores.primary, icono: Icons.login_rounded),
            Metrica(etiqueta: 'Cumplen', valor: r.cumplen, total: r.conTurno, color: sem.entrada, icono: Icons.verified_rounded),
            Metrica(etiqueta: 'Llegaron tarde', valor: r.tarde, total: r.conTurno, color: sem.alerta, icono: Icons.timer_outlined),
            Metrica(etiqueta: 'Incumplen', valor: r.incumplen, total: r.conTurno, color: sem.peligro, icono: Icons.report_gmailerrorred_rounded),
          ]
        : [
            Metrica(etiqueta: 'En la sede', valor: r.enSede, total: total, color: sem.entrada, icono: Icons.login_rounded),
            Metrica(etiqueta: 'Salieron', valor: r.presentes - r.enSede - r.sinSalida, total: total, color: sem.salida, icono: Icons.logout_rounded),
            Metrica(etiqueta: 'Ausentes', valor: r.ausentes, total: total, color: sem.alerta, icono: Icons.person_off_outlined),
            Metrica(etiqueta: 'Total', valor: r.total, total: total, color: context.colores.primary, icono: Icons.groups_rounded),
          ];
    return GrillaMetricas(tiles: tiles);
  }
}

/// Rejilla responsiva de métricas (2 columnas en teléfono, 4 en tablet).
class GrillaMetricas extends StatelessWidget {
  const GrillaMetricas({super.key, required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columnas = c.maxWidth > 560 ? 4 : 2;
      return GridView.count(
        crossAxisCount: columnas,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Espacio.xs,
        crossAxisSpacing: Espacio.xs,
        childAspectRatio: columnas == 4 ? 1.55 : 1.9,
        children: tiles,
      );
    });
  }
}

class Metrica extends StatelessWidget {
  const Metrica({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.total,
    required this.color,
    required this.icono,
    this.texto,
  });

  final String etiqueta;
  final int valor;
  final int total;
  final Color color;
  final IconData icono;

  /// Texto alternativo al número (p. ej. "86 %").
  final String? texto;

  @override
  Widget build(BuildContext context) {
    final proporcion = total <= 0 ? 0.0 : (valor / total).clamp(0.0, 1.0);
    return Semantics(
      label: '$etiqueta: ${texto ?? valor}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Espacio.sm),
        decoration: BoxDecoration(
          color: context.colores.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Redondeo.lg),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.10), Colors.transparent],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    etiqueta.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textos.labelSmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(texto ?? '$valor', style: Hud.titulo(tam: 30, color: context.colores.onSurface)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: proporcion,
                minHeight: 4,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({String texto, Color color, Color fondo}) estiloEstado(BuildContext context, EstadoAsistencia e) {
  final s = context.sem;
  return switch (e) {
    EstadoAsistencia.enSede => (texto: e.etiqueta, color: s.entrada, fondo: s.entradaFondo),
    EstadoAsistencia.salio => (texto: e.etiqueta, color: s.salida, fondo: s.salidaFondo),
    EstadoAsistencia.sinSalida => (texto: e.etiqueta, color: s.alerta, fondo: s.alertaFondo),
    EstadoAsistencia.ausente => (texto: e.etiqueta, color: s.peligro, fondo: s.peligroFondo),
    EstadoAsistencia.libre => (texto: e.etiqueta, color: s.textoSuave, fondo: context.colores.surfaceContainer),
  };
}

/// Color y texto del cumplimiento (con minutos de retraso / anticipo).
({String texto, Color color, Color fondo}) estiloCumplimiento(BuildContext context, Cumplimiento c) {
  final s = context.sem;
  final e = c.estado;
  final extra = e.esTarde && c.retrasoMin > 0
      ? ' · ${Formato.duracion(c.retrasoMin)}'
      : e == EstadoCumplimiento.salidaAnticipada && c.anticipoMin > 0
          ? ' · ${Formato.duracion(c.anticipoMin)}'
          : '';
  final (color, fondo) = switch (e) {
    EstadoCumplimiento.cumple => (s.entrada, s.entradaFondo),
    EstadoCumplimiento.tarde || EstadoCumplimiento.sinLlegar || EstadoCumplimiento.sinSalida => (s.alerta, s.alertaFondo),
    EstadoCumplimiento.salidaAnticipada || EstadoCumplimiento.incompleto || EstadoCumplimiento.ausente => (s.peligro, s.peligroFondo),
    EstadoCumplimiento.extra => (s.salida, s.salidaFondo),
    _ => (s.textoSuave, context.colores.surfaceContainer),
  };
  return (texto: '${e.etiqueta}$extra', color: color, fondo: fondo);
}

class _FilaEmpleado extends StatelessWidget {
  const _FilaEmpleado({required this.fila, required this.alTocar});
  final FilaReporte fila;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final conTurno = fila.turno != null;
    final est = conTurno ? estiloCumplimiento(context, fila.cumplimiento) : estiloEstado(context, fila.estado);
    final textoHoras = [
      if (fila.entrada != null) 'E ${Formato.hora(fila.entrada!)}',
      if (fila.salida != null) 'S ${Formato.hora(fila.salida!)}',
    ].join('  ·  ');
    return Card(
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(Redondeo.lg),
        child: Padding(
          padding: const EdgeInsets.all(Espacio.sm),
          child: Row(
            children: [
              AvatarEmpleado(
                nombre: fila.nombre,
                tam: 44,
                anillo: fila.estado == EstadoAsistencia.ausente || fila.estado == EstadoAsistencia.libre ? null : est.color,
              ),
              const SizedBox(width: Espacio.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fila.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textos.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      textoHoras.isEmpty ? (fila.cargo ?? fila.documento) : textoHoras,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Hud.mono(tam: 12.5, color: context.sem.textoSuave, espaciado: 0.4),
                    ),
                    if (conTurno) ...[
                      const SizedBox(height: 2),
                      EtiquetaTurno(nombre: fila.turno!.nombre, bloques: fila.turno!.bloques, color: context.colores.primary),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Espacio.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Pildora(texto: est.texto, color: est.color, fondo: est.fondo),
                  if (fila.minutosAhora > 0) ...[
                    const SizedBox(height: 4),
                    Text(Formato.duracion(fila.minutosAhora), style: context.textos.labelMedium),
                  ],
                  if (fila.relojAdelantado)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.warning_amber_rounded, size: 18, color: context.sem.alerta, semanticLabel: 'Alerta de reloj'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetalleEmpleado extends StatelessWidget {
  const _DetalleEmpleado({required this.fila});
  final FilaReporte fila;

  @override
  Widget build(BuildContext context) {
    final est = estiloEstado(context, fila.estado);
    final sem = context.sem;
    final c = fila.cumplimiento;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.xl),
        children: [
          Row(
            children: [
              AvatarEmpleado(nombre: fila.nombre, tam: 56, anillo: est.color),
              const SizedBox(width: Espacio.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fila.nombre, style: context.textos.titleLarge),
                    Text(
                      [fila.documento, if (fila.cargo != null) fila.cargo!].join(' · '),
                      style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Espacio.md),
          Wrap(
            spacing: Espacio.xs,
            runSpacing: Espacio.xs,
            children: [
              Pildora(texto: est.texto, color: est.color, fondo: est.fondo),
              if (fila.turno != null) ...[
                Builder(builder: (context) {
                  final ec = estiloCumplimiento(context, c);
                  return Pildora(texto: ec.texto, color: ec.color, fondo: ec.fondo, icono: Icons.fact_check_outlined);
                }),
              ],
              if (fila.minutosAhora > 0)
                Pildora(texto: 'Trabajado: ${Formato.duracion(fila.minutosAhora)}', color: context.colores.primary, icono: Icons.timer_outlined),
            ],
          ),
          if (fila.turno != null) ...[
            const SizedBox(height: Espacio.lg),
            const Etiqueta('Turno del día'),
            const SizedBox(height: Espacio.sm),
            Text(
              '${fila.turno!.nombre} · ${Formato.bloques(fila.turno!.bloques)} · tolerancia ${fila.turno!.toleranciaMin} min',
              style: context.textos.bodyMedium,
            ),
            const SizedBox(height: Espacio.sm),
            for (final b in c.bloques) _BloqueDetalle(bloque: b),
          ],
          const SizedBox(height: Espacio.lg),
          const Etiqueta('Línea de tiempo'),
          const SizedBox(height: Espacio.sm),
          if (fila.marcaciones.isEmpty)
            Text('No registró marcaciones este día.', style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave))
          else
            for (var i = 0; i < fila.marcaciones.length; i++)
              _Hito(marca: fila.marcaciones[i], ultimo: i == fila.marcaciones.length - 1),
        ],
      ),
    );
  }
}

class _BloqueDetalle extends StatelessWidget {
  const _BloqueDetalle({required this.bloque});
  final BloqueCumplimiento bloque;

  @override
  Widget build(BuildContext context) {
    final s = context.sem;
    final b = bloque;
    final (icono, color, texto) = switch (b.estado) {
      'OK' => (Icons.check_circle_rounded, s.entrada, 'Cumplido'),
      'TARDE' => (Icons.timer_outlined, s.alerta, 'Llegó ${Formato.duracion(b.retrasoMin)} tarde'),
      'ANTICIPADA' => (Icons.logout_rounded, s.peligro, 'Salió ${Formato.duracion(b.anticipoMin)} antes'),
      'TARDE_ANTICIPADA' => (Icons.error_outline_rounded, s.peligro,
          'Tarde ${Formato.duracion(b.retrasoMin)} · salió ${Formato.duracion(b.anticipoMin)} antes'),
      'FALTA' => (Icons.cancel_outlined, s.peligro, 'No se presentó'),
      'SIN_LLEGAR' => (Icons.hourglass_bottom_rounded, s.alerta, 'Aún no llega (${Formato.duracion(b.retrasoMin)})'),
      'SIN_SALIDA' => (Icons.help_outline_rounded, s.alerta, 'No registró salida'),
      'EN_CURSO' => (Icons.play_circle_outline_rounded, context.colores.primary, 'En curso'),
      _ => (Icons.schedule_rounded, s.textoSuave, 'Pendiente'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: Espacio.sm),
          SizedBox(
            width: 104,
            child: Text('${b.inicio}–${b.fin}', style: Hud.mono(tam: 13, color: context.colores.onSurface, espaciado: 0)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto, style: context.textos.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
                if (b.llegada != null || b.salida != null)
                  Text(
                    [if (b.llegada != null) 'llegó ${b.llegada}', if (b.salida != null) 'salió ${b.salida}'].join(' · '),
                    style: context.textos.bodySmall?.copyWith(color: s.textoSuave),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hito extends StatelessWidget {
  const _Hito({required this.marca, required this.ultimo});
  final MarcaReporte marca;
  final bool ultimo;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final entrada = marca.tipo == TipoMarcacion.entrada;
    final color = entrada ? sem.entrada : sem.salida;
    final (nota, colorNota) = _nota(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                  border: Border.all(color: color),
                ),
                child: Icon(entrada ? Icons.login_rounded : Icons.logout_rounded, size: 18, color: color),
              ),
              if (!ultimo) Expanded(child: Container(width: 2, color: sem.borde)),
            ],
          ),
          const SizedBox(width: Espacio.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Espacio.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(marca.tipo.etiqueta, style: context.textos.titleMedium),
                      const Spacer(),
                      Text(
                        Formato.horaConSegundos(marca.hora),
                        style: Hud.mono(tam: 15, color: context.colores.onSurface, peso: FontWeight.w700, espaciado: 0.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Servidor: ${Formato.horaConSegundos(marca.horaServidor)}',
                    style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                  ),
                  if (nota != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(nota, style: context.textos.bodySmall?.copyWith(color: colorNota, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String?, Color) _nota(BuildContext context) {
    final sem = context.sem;
    final d = marca.desfaseSeg;
    if (d < -120) return ('Reloj del kiosco adelantado ${(d.abs() / 60).ceil()} min', sem.peligro);
    if (d > 600) return ('Enviada ${Formato.duracion(d ~/ 60)} después (sin conexión)', sem.textoSuave);
    return (null, sem.textoSuave);
  }
}
