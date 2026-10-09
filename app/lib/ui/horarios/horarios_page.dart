import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../admin/contexto_admin.dart';
import '../comun/widgets.dart';
import 'asignar_rotacion_page.dart';
import 'turno_form_page.dart';
import 'widgets_horario.dart';

/// Pestaña "Horarios": catálogo de turnos y asignación de rotaciones.
class HorariosPage extends StatefulWidget {
  const HorariosPage({super.key});

  @override
  State<HorariosPage> createState() => _HorariosPageState();
}

class _HorariosPageState extends State<HorariosPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      await _ctx.cargarHorarios(forzar: true);
      _error = null;
    } on ApiError catch (e) {
      _error = e.mensaje;
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrirTurno([Horario? h]) async {
    final cambio = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(value: _ctx, child: TurnoFormPage(horario: h)),
    ));
    if (cambio == true) _cargar();
  }

  Future<void> _asignar() async {
    if (_ctx.horarios.isEmpty) {
      avisar(context, 'Primero crea al menos un turno', error: true);
      return;
    }
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(value: _ctx, child: const AsignarRotacionPage()),
    ));
    if (ok == true && mounted) avisar(context, 'Rotación asignada');
  }

  @override
  Widget build(BuildContext context) {
    final horarios = context.watch<ContextoAdmin>().horarios;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirTurno(),
        icon: const Icon(Icons.more_time_rounded),
        label: const Text('Nuevo turno'),
      ),
      body: FondoTecnico(
        intensidad: 0.6,
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, 96),
            children: [
              _TarjetaRotacion(alAsignar: _asignar),
              const SizedBox(height: Espacio.lg),
              Row(
                children: [
                  const Etiqueta('Turnos'),
                  const Spacer(),
                  Text('${horarios.length}', style: context.textos.labelLarge?.copyWith(color: context.sem.textoSuave)),
                ],
              ),
              const SizedBox(height: Espacio.sm),
              if (_cargando && horarios.isEmpty)
                const Padding(padding: EdgeInsets.all(Espacio.xl), child: Center(child: CircularProgressIndicator()))
              else if (_error != null && horarios.isEmpty)
                EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudo cargar', mensaje: _error, accion: _cargar)
              else if (horarios.isEmpty)
                EstadoVacio(
                  icono: Icons.schedule_rounded,
                  titulo: 'Crea tu primer turno',
                  mensaje: 'Ejemplo: "Turno A" de 08:30 a 12:00 y de 14:00 a 18:00, lunes a sábado.',
                  accion: () => _abrirTurno(),
                  etiquetaAccion: 'Nuevo turno',
                )
              else
                for (final h in horarios)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.xs),
                    child: _TarjetaTurno(horario: h, alTocar: () => _abrirTurno(h)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaRotacion extends StatelessWidget {
  const _TarjetaRotacion({required this.alAsignar});
  final VoidCallback alAsignar;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Container(
      padding: const EdgeInsets.all(Espacio.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Redondeo.lg),
        border: Border.all(color: context.colores.primary.withValues(alpha: 0.5)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [sem.degradado[0].withValues(alpha: 0.16), sem.degradado[1].withValues(alpha: 0.06)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.autorenew_rounded, color: context.colores.primary),
              const SizedBox(width: Espacio.xs),
              Text('Rotación semanal', style: context.textos.titleMedium),
            ],
          ),
          const SizedBox(height: Espacio.xs),
          Text(
            'Define el orden de los turnos (p. ej. Turno A y luego Turno B) y desde qué semana empieza. '
            'Cada lunes el personal pasa automáticamente al siguiente turno.',
            style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
          ),
          const SizedBox(height: Espacio.md),
          FilledButton.icon(
            onPressed: alAsignar,
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Asignar rotación a personal'),
          ),
        ],
      ),
    );
  }
}

class _TarjetaTurno extends StatelessWidget {
  const _TarjetaTurno({required this.horario, required this.alTocar});
  final Horario horario;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final color = colorTurno(context, horario.id);
    return Card(
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(Redondeo.lg),
        child: Padding(
          padding: const EdgeInsets.all(Espacio.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(width: 4, height: 22, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: Espacio.sm),
                  Expanded(child: Text(horario.nombre, style: context.textos.titleMedium)),
                  Text(Formato.duracion(horario.minutosDia), style: Hud.mono(tam: 13, color: color, peso: FontWeight.w700, espaciado: 0)),
                ],
              ),
              const SizedBox(height: Espacio.xs),
              Text(Formato.bloques(horario.bloques), style: Hud.mono(tam: 13, color: context.colores.onSurface, espaciado: 0.3)),
              const SizedBox(height: Espacio.sm),
              BarraTurno(bloques: horario.listaBloques, color: color),
              const SizedBox(height: Espacio.xs),
              Row(
                children: [
                  Icon(Icons.event_repeat_rounded, size: 16, color: context.sem.textoSuave),
                  const SizedBox(width: 4),
                  Text(DiasSemana.texto(horario.dias), style: context.textos.bodySmall),
                  const Spacer(),
                  Icon(Icons.timer_outlined, size: 16, color: context.sem.textoSuave),
                  const SizedBox(width: 4),
                  Text('Tolerancia ${horario.toleranciaMin} min', style: context.textos.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
