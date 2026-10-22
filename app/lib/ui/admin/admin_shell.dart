import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../horarios/horarios_page.dart';
import 'ajustes_page.dart';
import 'asistencia_page.dart';
import 'contexto_admin.dart';
import 'novedades_page.dart';
import 'personal_page.dart';

/// Panel administrativo: cinco secciones en la barra inferior. Lo usan el
/// administrador, el gerente (sus sedes) y talento humano.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.sedes, this.esInicio = false});

  /// Sedes de Presente visibles para la cuenta (al menos una).
  final List<Sede> sedes;

  /// Es la pantalla principal (teléfono personal con la sesión recordada):
  /// no hay a dónde volver, solo «Cerrar sesión».
  final bool esInicio;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late final EstadoApp _estado = context.read<EstadoApp>();
  late final ContextoAdmin _ctx =
      ContextoAdmin(api: _estado.api, sedes: widget.sedes, sedeDispositivo: _estado.config?.sede);
  int _indice = 0;

  /// Solicitudes de los empleados que esperan respuesta (globo de la barra).
  int _solicitudes = 0;
  int _visitasSolicitudes = 0;
  static const _indiceSolicitudes = 2;

  static const _secciones = [
    (icono: Icons.insights_outlined, activo: Icons.insights_rounded, etiqueta: 'Asistencia'),
    (icono: Icons.groups_outlined, activo: Icons.groups_rounded, etiqueta: 'Personal'),
    (icono: Icons.inbox_outlined, activo: Icons.inbox_rounded, etiqueta: 'Solicitudes'),
    (icono: Icons.schedule_outlined, activo: Icons.schedule_rounded, etiqueta: 'Horarios'),
    (icono: Icons.tune_outlined, activo: Icons.tune_rounded, etiqueta: 'Ajustes'),
  ];

  @override
  void initState() {
    super.initState();
    _estado.sesion.addListener(_vigilarSesion);
    _ctx.cargarSedes();
  }

  @override
  void dispose() {
    _estado.sesion.removeListener(_vigilarSesion);
    _ctx.dispose();
    super.dispose();
  }

  /// Si la sesión expira por inactividad, se vuelve a la pantalla inicial.
  void _vigilarSesion() {
    if (!_estado.sesion.activa && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _salir() async {
    // La sesión recordada no se vuelve a abrir sin internet: se confirma.
    if (_estado.sesion.recordada) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Cerrar sesión?'),
          content: const Text('Para volver a entrar tendrás que escribir tu correo y contraseña, con internet.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cerrar sesión')),
          ],
        ),
      );
      if (ok != true) return;
    }
    _estado.sesion.cerrar();
  }

  Widget _conGlobo(int i, Widget icono) => i == _indiceSolicitudes && _solicitudes > 0
      ? Badge(label: Text(_solicitudes > 99 ? '99+' : '$_solicitudes'), child: icono)
      : icono;

  @override
  Widget build(BuildContext context) {
    final sesion = _estado.sesion.sesion;
    return Listener(
      onPointerDown: (_) => _estado.sesion.tocar(),
      child: ChangeNotifierProvider.value(
        value: _ctx,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            // En un teléfono de marcación se vuelve a la pantalla de marcar.
            leading: widget.esInicio
                ? null
                : BackButton(onPressed: () => Navigator.of(context).pop()),
            titleSpacing: widget.esInicio ? null : 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PANEL · ${sesion?.nombre.toUpperCase() ?? ''}',
                  style: context.textos.labelSmall?.copyWith(color: context.colores.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(_secciones[_indice].etiqueta),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: _salir,
                icon: const Icon(Icons.lock_outline_rounded, size: 20),
                label: const Text('Cerrar sesión'),
              ),
              const SizedBox(width: Espacio.xs),
            ],
          ),
          body: IndexedStack(
            index: _indice,
            children: [
              const AsistenciaPage(),
              const PersonalPage(),
              NovedadesPage(
                visitas: _visitasSolicitudes,
                alCambiarPendientes: (n) {
                  if (mounted && n != _solicitudes) setState(() => _solicitudes = n);
                },
              ),
              const HorariosPage(),
              const AjustesPage(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _indice,
            onDestinationSelected: (i) => setState(() {
              if (i == _indiceSolicitudes) _visitasSolicitudes++;
              _indice = i;
            }),
            destinations: [
              for (final (i, s) in _secciones.indexed)
                NavigationDestination(
                  icon: _conGlobo(i, Icon(s.icono)),
                  selectedIcon: _conGlobo(i, Icon(s.activo)),
                  label: s.etiqueta,
                  tooltip: i == _indiceSolicitudes && _solicitudes > 0 ? '${s.etiqueta}: $_solicitudes por responder' : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
