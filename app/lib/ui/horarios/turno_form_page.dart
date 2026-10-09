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

/// Crear / editar un turno: bloques del día, días de la semana y tolerancia.
class TurnoFormPage extends StatefulWidget {
  const TurnoFormPage({super.key, this.horario});
  final Horario? horario;

  @override
  State<TurnoFormPage> createState() => _TurnoFormPageState();
}

class _TurnoFormPageState extends State<TurnoFormPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  late final _nombre = TextEditingController(text: widget.horario?.nombre);
  late List<Bloque> _bloques = widget.horario?.listaBloques ??
      [(inicio: 8 * 60 + 30, fin: 12 * 60), (inicio: 14 * 60, fin: 18 * 60)];
  late int _dias = widget.horario?.dias ?? 63;
  late int _tolerancia = widget.horario?.toleranciaMin ?? 10;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  String? _validar() {
    if (_nombre.text.trim().length < 2) return 'Ponle un nombre al turno';
    if (_bloques.isEmpty) return 'Agrega al menos un bloque de horario';
    if (_dias == 0) return 'Selecciona al menos un día';
    final orden = [..._bloques]..sort((a, b) => a.inicio.compareTo(b.inicio));
    for (var i = 0; i < orden.length; i++) {
      if (orden[i].fin <= orden[i].inicio) {
        return 'El bloque ${hhmm(orden[i].inicio)}–${hhmm(orden[i].fin)} debe terminar después de empezar';
      }
      if (i > 0 && orden[i].inicio < orden[i - 1].fin) return 'Los bloques no pueden cruzarse';
    }
    return null;
  }

  Future<void> _elegirHora(int indice, bool inicio) async {
    final b = _bloques[indice];
    final actual = inicio ? b.inicio : b.fin;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actual ~/ 60, minute: actual % 60),
      helpText: inicio ? 'Hora de inicio' : 'Hora de fin',
      builder: (c, hijo) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: hijo!),
    );
    if (t == null) return;
    final m = t.hour * 60 + t.minute;
    setState(() {
      _bloques = [..._bloques]..[indice] = inicio ? (inicio: m, fin: b.fin) : (inicio: b.inicio, fin: m);
      _error = null;
    });
  }

  void _agregarBloque() {
    final ultimo = _bloques.isEmpty ? 7 * 60 : _bloques.map((b) => b.fin).reduce((a, b) => a > b ? a : b);
    final inicio = (ultimo + 60).clamp(0, 22 * 60);
    setState(() => _bloques = [..._bloques, (inicio: inicio, fin: (inicio + 180).clamp(inicio + 30, 23 * 60 + 59))]);
  }

  Future<void> _guardar() async {
    final error = _validar();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final orden = [..._bloques]..sort((a, b) => a.inicio.compareTo(b.inicio));
      await _ctx.api.guardarHorario(
        id: widget.horario?.id,
        nombre: _nombre.text.trim(),
        bloques: bloquesATexto(orden),
        dias: _dias,
        toleranciaMin: _tolerancia,
      );
      if (mounted) {
        avisar(context, widget.horario == null ? 'Turno creado' : 'Turno actualizado');
        Navigator.pop(context, true);
      }
    } on ApiError catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _archivar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Archivar este turno?'),
        content: const Text(
          'Ya no aparecerá para nuevas asignaciones. Quienes lo tengan en su rotación lo conservan '
          'y el historial de cumplimiento no cambia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Archivar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _ctx.api.archivarHorario(widget.horario!.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorTurno(context, widget.horario?.id ?? _ctx.horarios.length + 1);
    final total = _bloques.fold<int>(0, (s, b) => s + (b.fin - b.inicio).clamp(0, 1440));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.horario == null ? 'Nuevo turno' : 'Editar turno'),
        actions: [
          if (widget.horario != null)
            IconButton(tooltip: 'Archivar turno', onPressed: _archivar, icon: const Icon(Icons.archive_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, 120),
        children: [
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Nombre del turno',
              hintText: 'Ej.: Turno A · Mañana partida',
              prefixIcon: Icon(Icons.label_outline_rounded),
            ),
          ),
          const SizedBox(height: Espacio.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Espacio.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Etiqueta('Bloques del día'),
                      const Spacer(),
                      Text('Total ${Formato.duracion(total)}', style: Hud.mono(tam: 12, color: color, peso: FontWeight.w700, espaciado: 0)),
                    ],
                  ),
                  const SizedBox(height: Espacio.md),
                  BarraTurno(bloques: _bloques, color: color, alto: 30),
                  const SizedBox(height: Espacio.md),
                  for (var i = 0; i < _bloques.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espacio.xs),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text('${i + 1}', style: Hud.mono(tam: 14, color: color, peso: FontWeight.w700)),
                          ),
                          Expanded(child: _BotonHora(etiqueta: 'Desde', minutos: _bloques[i].inicio, alTocar: () => _elegirHora(i, true))),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 18)),
                          Expanded(child: _BotonHora(etiqueta: 'Hasta', minutos: _bloques[i].fin, alTocar: () => _elegirHora(i, false))),
                          IconButton(
                            tooltip: 'Quitar bloque ${i + 1}',
                            onPressed: _bloques.length > 1 ? () => setState(() => _bloques = [..._bloques]..removeAt(i)) : null,
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  if (_bloques.length < 4)
                    TextButton.icon(
                      onPressed: _agregarBloque,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Agregar bloque (p. ej. jornada partida)'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Espacio.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Espacio.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Etiqueta('Días que aplica'),
                  const SizedBox(height: Espacio.sm),
                  SelectorDias(mascara: _dias, alCambiar: (m) => setState(() => _dias = m)),
                  const SizedBox(height: Espacio.xs),
                  Text(DiasSemana.texto(_dias), style: context.textos.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: Espacio.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Espacio.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tolerancia', style: context.textos.titleMedium),
                        Text(
                          'Minutos de gracia antes de contar como tarde o salida anticipada.',
                          style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Menos tolerancia',
                    onPressed: _tolerancia > 0 ? () => setState(() => _tolerancia = (_tolerancia - 5).clamp(0, 60)) : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text('$_tolerancia min', textAlign: TextAlign.center, style: context.textos.titleMedium),
                  ),
                  IconButton.outlined(
                    tooltip: 'Más tolerancia',
                    onPressed: _tolerancia < 60 ? () => setState(() => _tolerancia = (_tolerancia + 5).clamp(0, 60)) : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
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
              : const Icon(Icons.save_outlined),
          label: Text(widget.horario == null ? 'Crear turno' : 'Guardar cambios'),
        ),
      ),
    );
  }
}

class _BotonHora extends StatelessWidget {
  const _BotonHora({required this.etiqueta, required this.minutos, required this.alTocar});
  final String etiqueta;
  final int minutos;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$etiqueta ${hhmm(minutos)}',
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: alTocar,
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Espacio.sm)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(etiqueta.toUpperCase(), style: context.textos.labelSmall?.copyWith(color: context.sem.textoSuave)),
            Text(hhmm(minutos), style: Hud.mono(tam: 17, color: context.colores.onSurface, peso: FontWeight.w700, espaciado: 0)),
          ],
        ),
      ),
    );
  }
}
