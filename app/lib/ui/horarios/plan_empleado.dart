import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../admin/contexto_admin.dart';
import '../comun/widgets.dart';
import 'asignar_rotacion_page.dart';
import 'widgets_horario.dart';

/// Horario de un empleado: rotación vigente y próximas semanas, con la
/// posibilidad de cambiar UNA semana (vacaciones, reemplazos…).
class TarjetaHorarioEmpleado extends StatefulWidget {
  const TarjetaHorarioEmpleado({super.key, required this.empleado});
  final Empleado empleado;

  @override
  State<TarjetaHorarioEmpleado> createState() => _TarjetaHorarioEmpleadoState();
}

class _TarjetaHorarioEmpleadoState extends State<TarjetaHorarioEmpleado> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  PlanEmpleado? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      await _ctx.cargarHorarios();
      final p = await _ctx.api.planEmpleado(widget.empleado.id, semanas: 6);
      if (mounted) {
        setState(() {
          _plan = p;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _cambiarRotacion() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: _ctx,
        child: AsignarRotacionPage(empleados: [widget.empleado], secuenciaInicial: _plan?.secuencia ?? const []),
      ),
    ));
    if (ok == true) {
      if (mounted) avisar(context, 'Rotación actualizada');
      _cargar();
    }
  }

  Future<void> _ajustarSemana(PlanSemana s) async {
    final horarios = await _ctx.cargarHorarios();
    if (!mounted) return;
    // -1 = sin turno · -2 = volver a la rotación · id = turno
    final eleccion = await showModalBottomSheet<int>(
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
            Text('Solo la semana del ${Formato.semana(s.semana)}', style: c.textos.titleLarge),
            const SizedBox(height: Espacio.xxs),
            Text(
              'El cambio aplica únicamente a esta semana; la rotación sigue igual después.',
              style: c.textos.bodyMedium?.copyWith(color: c.sem.textoSuave),
            ),
            const SizedBox(height: Espacio.md),
            for (final h in horarios)
              Card(
                child: ListTile(
                  onTap: () => Navigator.pop(c, h.id),
                  leading: Icon(
                    s.horario?.id == h.id ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: colorTurno(c, h.id),
                  ),
                  title: Text(h.nombre),
                  subtitle: Text(Formato.bloques(h.bloques)),
                ),
              ),
            Card(
              child: ListTile(
                onTap: () => Navigator.pop(c, -1),
                leading: Icon(Icons.beach_access_outlined, color: c.sem.alerta),
                title: const Text('Sin turno esta semana'),
                subtitle: const Text('Vacaciones, descanso o incapacidad'),
              ),
            ),
            if (s.ajustada)
              Card(
                child: ListTile(
                  onTap: () => Navigator.pop(c, -2),
                  leading: Icon(Icons.undo_rounded, color: c.colores.primary),
                  title: const Text('Volver a la rotación'),
                ),
              ),
          ],
        ),
      ),
    );
    if (eleccion == null) return;
    try {
      await _ctx.api.ajustarSemana(
        widget.empleado.id,
        s.semana,
        horarioId: eleccion > 0 ? eleccion : null,
        quitar: eleccion == -2,
      );
      _cargar();
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final sem = context.sem;
    final esta = Formato.lunes(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.autorenew_rounded, color: context.colores.primary),
                const SizedBox(width: Espacio.sm),
                Expanded(child: Text('Rotación semanal', style: context.textos.titleMedium)),
              ],
            ),
            const SizedBox(height: Espacio.sm),
            if (plan == null && _error == null)
              const LinearProgressIndicator()
            else if (_error != null)
              Text(_error!, style: TextStyle(color: sem.peligro))
            else ...[
              if (!plan!.tieneRotacion)
                Text('Sin horario asignado: no se evalúa su cumplimiento.', style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave))
              else
                Wrap(
                  spacing: Espacio.xs,
                  runSpacing: Espacio.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = 0; i < plan.secuencia.length; i++) ...[
                      if (i > 0) Icon(Icons.arrow_forward_rounded, size: 16, color: sem.textoSuave),
                      Builder(builder: (context) {
                        final h = _ctx.horario(plan.secuencia[i]);
                        final c = colorTurno(context, plan.secuencia[i]);
                        return Pildora(texto: h?.nombre ?? 'Turno ${plan.secuencia[i]}', color: c);
                      }),
                    ],
                    if (plan.desde != null)
                      Text('desde el ${Formato.diaMes(plan.desde!)}', style: context.textos.bodySmall),
                  ],
                ),
              const SizedBox(height: Espacio.md),
              for (final s in plan.semanas)
                InkWell(
                  onTap: () => _ajustarSemana(s),
                  borderRadius: BorderRadius.circular(Redondeo.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Espacio.xs),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 104,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (s.semana == esta) Etiqueta('Esta semana', color: context.colores.primary),
                              Text(Formato.semana(s.semana), style: Hud.mono(tam: 12, color: context.colores.onSurface, espaciado: 0)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: s.horario == null
                              ? Text(s.ajustada ? 'Sin turno (ajustada)' : 'Sin turno', style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave))
                              : EtiquetaTurno(
                                  nombre: s.horario!.nombre,
                                  bloques: s.horario!.bloques,
                                  color: colorTurno(context, s.horario!.id),
                                  estilo: context.textos.bodyMedium,
                                ),
                        ),
                        if (s.ajustada)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.edit_calendar_rounded, size: 18, color: sem.alerta, semanticLabel: 'Semana ajustada'),
                          ),
                        Icon(Icons.chevron_right_rounded, color: sem.textoSuave),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: Espacio.sm),
              FilledButton.tonalIcon(
                onPressed: _cambiarRotacion,
                icon: const Icon(Icons.edit_rounded),
                label: Text(plan.tieneRotacion ? 'Cambiar rotación' : 'Asignar horario'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
