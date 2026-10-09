import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../admin/acceso_admin.dart';
import '../admin/contexto_admin.dart';
import '../comun/widgets.dart';
import 'widgets_horario.dart';

/// Asigna una rotación semanal (p. ej. Turno A → Turno B → …) a uno o varios
/// empleados, desde una semana concreta. Cada lunes rota automáticamente.
class AsignarRotacionPage extends StatefulWidget {
  const AsignarRotacionPage({super.key, this.empleados, this.secuenciaInicial = const []});

  /// Si viene, la rotación es solo para estas personas (desde su ficha).
  final List<Empleado>? empleados;
  final List<int> secuenciaInicial;

  @override
  State<AsignarRotacionPage> createState() => _AsignarRotacionPageState();
}

class _AsignarRotacionPageState extends State<AsignarRotacionPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  late final List<int> _secuencia = [...widget.secuenciaInicial];
  DateTime _desde = Formato.lunes(DateTime.now());
  List<Empleado>? _personal;
  final Set<int> _elegidos = {};
  String _busqueda = '';
  bool _guardando = false;
  String? _error;

  bool get _fijos => widget.empleados != null;

  @override
  void initState() {
    super.initState();
    _ctx.cargarHorarios();
    if (_fijos) {
      _elegidos.addAll(widget.empleados!.map((e) => e.id));
    } else {
      _cargarPersonal();
    }
  }

  Future<void> _cargarPersonal() async {
    try {
      final l = await _ctx.api.empleados(sedeId: _ctx.sede.id);
      if (mounted) setState(() => _personal = l);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _agregarTurno() async {
    final horarios = await _ctx.cargarHorarios();
    if (!mounted) return;
    final id = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Espacio.md, 0, Espacio.md, Espacio.lg),
          children: [
            Text('Turno para la semana ${_secuencia.length + 1}', style: c.textos.titleLarge),
            const SizedBox(height: Espacio.md),
            for (final h in horarios)
              Card(
                child: ListTile(
                  onTap: () => Navigator.pop(c, h.id),
                  title: Text(h.nombre),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: BarraTurno(bloques: h.listaBloques, color: colorTurno(c, h.id), alto: 18, marcas: false),
                  ),
                  trailing: Text(Formato.bloques(h.bloques), style: c.textos.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
    if (id != null) setState(() => _secuencia.add(id));
  }

  Future<void> _elegirSemana() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _desde,
      firstDate: DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Semana en que inicia (se toma el lunes)',
    );
    if (f != null) setState(() => _desde = Formato.lunes(f));
  }

  Future<void> _guardar() async {
    if (_secuencia.isEmpty) {
      setState(() => _error = 'Agrega al menos un turno a la secuencia');
      return;
    }
    if (_elegidos.isEmpty) {
      setState(() => _error = 'Selecciona al menos un empleado');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _ctx.api.asignarRotacion(empleados: _elegidos.toList(), secuencia: _secuencia, desde: _desde);
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context.watch<ContextoAdmin>();
    final pasado = _desde.isBefore(Formato.lunes(DateTime.now()));
    return Scaffold(
      appBar: AppBar(title: const Text('Asignar rotación')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, 120),
        children: [
          const Etiqueta('1 · Orden de los turnos'),
          const SizedBox(height: Espacio.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Espacio.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_secuencia.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Espacio.sm),
                      child: Text(
                        'Agrega los turnos en el orden en que rotan. Con uno solo, la persona tiene siempre el mismo horario.',
                        style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
                      ),
                    ),
                  for (var i = 0; i < _secuencia.length; i++)
                    _FilaSecuencia(
                      indice: i,
                      horario: ctx.horario(_secuencia[i]),
                      alSubir: i > 0 ? () => setState(() => _secuencia.insert(i - 1, _secuencia.removeAt(i))) : null,
                      alBajar: i < _secuencia.length - 1
                          ? () => setState(() => _secuencia.insert(i + 1, _secuencia.removeAt(i)))
                          : null,
                      alQuitar: () => setState(() => _secuencia.removeAt(i)),
                    ),
                  if (_secuencia.length < 8)
                    TextButton.icon(
                      onPressed: _agregarTurno,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(_secuencia.isEmpty ? 'Agregar turno' : 'Agregar semana ${_secuencia.length + 1}'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Espacio.lg),
          const Etiqueta('2 · Semana de inicio'),
          const SizedBox(height: Espacio.sm),
          Card(
            child: ListTile(
              leading: Icon(Icons.event_rounded, color: context.colores.primary),
              title: Text('Semana del ${Formato.semana(_desde)}'),
              subtitle: Text(pasado
                  ? 'Es una semana pasada: recalcula el cumplimiento desde esa fecha.'
                  : 'Esa semana usa el turno 1 de la secuencia.'),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: _elegirSemana,
            ),
          ),
          if (_secuencia.isNotEmpty) ...[
            const SizedBox(height: Espacio.md),
            _VistaPrevia(desde: _desde, secuencia: _secuencia, ctx: ctx),
          ],
          const SizedBox(height: Espacio.lg),
          Etiqueta(_fijos ? '3 · Para' : '3 · Personal (${_elegidos.length})'),
          const SizedBox(height: Espacio.sm),
          if (_fijos)
            Wrap(
              spacing: Espacio.xs,
              children: [for (final e in widget.empleados!) Chip(avatar: const Icon(Icons.person_rounded, size: 18), label: Text(e.nombre))],
            )
          else
            _SelectorPersonal(
              personal: _personal,
              elegidos: _elegidos,
              busqueda: _busqueda,
              alBuscar: (v) => setState(() => _busqueda = v),
              alCambiar: () => setState(() {}),
            ),
          if (_error != null) ...[
            const SizedBox(height: Espacio.md),
            MensajeError(_error!),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(Espacio.md),
        child: FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Icon(Icons.check_rounded),
          label: Text(_elegidos.length <= 1 ? 'Asignar rotación' : 'Asignar a ${_elegidos.length} personas'),
        ),
      ),
    );
  }
}

class _FilaSecuencia extends StatelessWidget {
  const _FilaSecuencia({required this.indice, required this.horario, this.alSubir, this.alBajar, required this.alQuitar});
  final int indice;
  final Horario? horario;
  final VoidCallback? alSubir;
  final VoidCallback? alBajar;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final color = horario == null ? context.sem.textoSuave : colorTurno(context, horario!.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color), color: color.withValues(alpha: 0.12)),
            child: Text('S${indice + 1}', style: Hud.mono(tam: 11, color: color, peso: FontWeight.w700, espaciado: 0)),
          ),
          const SizedBox(width: Espacio.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(horario?.nombre ?? 'Turno archivado', style: context.textos.titleMedium),
                if (horario != null)
                  Text(Formato.bloques(horario!.bloques), style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave)),
              ],
            ),
          ),
          IconButton(tooltip: 'Subir', onPressed: alSubir, icon: const Icon(Icons.arrow_upward_rounded)),
          IconButton(tooltip: 'Bajar', onPressed: alBajar, icon: const Icon(Icons.arrow_downward_rounded)),
          IconButton(tooltip: 'Quitar', onPressed: alQuitar, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }
}

class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({required this.desde, required this.secuencia, required this.ctx});
  final DateTime desde;
  final List<int> secuencia;
  final ContextoAdmin ctx;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Así quedarán las próximas semanas', style: context.textos.titleMedium),
            const SizedBox(height: Espacio.sm),
            for (var i = 0; i < 6; i++)
              Builder(builder: (context) {
                final h = ctx.horario(secuencia[i % secuencia.length]);
                final semana = desde.add(Duration(days: 7 * i));
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(Formato.semana(semana), style: Hud.mono(tam: 12, color: context.colores.onSurface, espaciado: 0)),
                      ),
                      Expanded(
                        child: h == null
                            ? const Text('—')
                            : EtiquetaTurno(nombre: h.nombre, bloques: h.bloques, color: colorTurno(context, h.id)),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SelectorPersonal extends StatelessWidget {
  const _SelectorPersonal({
    required this.personal,
    required this.elegidos,
    required this.busqueda,
    required this.alBuscar,
    required this.alCambiar,
  });

  final List<Empleado>? personal;
  final Set<int> elegidos;
  final String busqueda;
  final ValueChanged<String> alBuscar;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final lista = personal;
    if (lista == null) return const Center(child: Padding(padding: EdgeInsets.all(Espacio.lg), child: CircularProgressIndicator()));
    final q = busqueda.trim().toLowerCase();
    final visibles = lista.where((e) => q.isEmpty || e.nombre.toLowerCase().contains(q) || e.documento.contains(q)).toList();
    final todos = visibles.isNotEmpty && visibles.every((e) => elegidos.contains(e.id));
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Espacio.sm),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar persona', prefixIcon: Icon(Icons.search_rounded), isDense: true),
              onChanged: alBuscar,
            ),
          ),
          CheckboxListTile(
            value: todos,
            title: Text(todos ? 'Quitar selección' : 'Seleccionar todos (${visibles.length})'),
            onChanged: (v) {
              for (final e in visibles) {
                v == true ? elegidos.add(e.id) : elegidos.remove(e.id);
              }
              alCambiar();
            },
          ),
          const Divider(),
          for (final e in visibles)
            CheckboxListTile(
              value: elegidos.contains(e.id),
              title: Text(e.nombre),
              subtitle: Text(e.turnoSemana == null ? 'Sin horario' : 'Esta semana: ${e.turnoSemana!.nombre}'),
              onChanged: (v) {
                v == true ? elegidos.add(e.id) : elegidos.remove(e.id);
                alCambiar();
              },
            ),
        ],
      ),
    );
  }
}
