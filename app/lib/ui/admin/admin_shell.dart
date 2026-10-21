import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../horarios/horarios_page.dart';
import 'ajustes_page.dart';
import 'asistencia_page.dart';
import 'contexto_admin.dart';
import 'personal_page.dart';

/// Panel administrativo: cuatro secciones en la barra inferior. Lo usan el
/// administrador, el gerente (sus sedes) y talento humano.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.sedes});

  /// Sedes de Presente visibles para la cuenta (al menos una).
  final List<Sede> sedes;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late final EstadoApp _estado = context.read<EstadoApp>();
  late final ContextoAdmin _ctx =
      ContextoAdmin(api: _estado.api, sedes: widget.sedes, sedeDispositivo: _estado.config?.sede);
  int _indice = 0;

  static const _secciones = [
    (icono: Icons.insights_outlined, activo: Icons.insights_rounded, etiqueta: 'Asistencia'),
    (icono: Icons.groups_outlined, activo: Icons.groups_rounded, etiqueta: 'Personal'),
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

  void _salir() {
    _estado.sesion.cerrar();
  }

  @override
  Widget build(BuildContext context) {
    final sesion = _estado.sesion.sesion;
    return Listener(
      onPointerDown: (_) => _estado.sesion.tocar(),
      child: ChangeNotifierProvider.value(
        value: _ctx,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Volver al inicio',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            titleSpacing: 0,
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
            children: const [AsistenciaPage(), PersonalPage(), HorariosPage(), AjustesPage()],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _indice,
            onDestinationSelected: (i) => setState(() => _indice = i),
            destinations: [
              for (final s in _secciones)
                NavigationDestination(icon: Icon(s.icono), selectedIcon: Icon(s.activo), label: s.etiqueta),
            ],
          ),
        ),
      ),
    );
  }
}
