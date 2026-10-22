import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../comun/widgets.dart';
import 'admin_shell.dart';
import 'sedes_page.dart' show pedirPrimeraSede;

/// Sedes de Presente que ve la cuenta. Con internet se consultan (y se guardan
/// en el teléfono); sin internet se usan las guardadas, para que el panel abra
/// igual. Si la empresa no tiene ninguna, el administrador elige la primera.
Future<List<Sede>> sedesDelPanel(BuildContext context, EstadoApp estado) async {
  final sesion = estado.sesion.sesion;
  List<Sede> sedes;
  try {
    sedes = await estado.api.sedes();
  } on ApiError catch (e) {
    if (!e.sinConexion) rethrow;
    final guardadas = await estado.sesion.sedesGuardadas();
    if (guardadas.isEmpty) rethrow;
    return guardadas;
  }
  if (sedes.isEmpty) {
    if (!(sesion?.esAdminEmpresa ?? false)) {
      throw const ApiError(403, 'Tu cuenta no tiene sedes en Presente. Pídele al administrador que te asigne una.');
    }
    // Sin ninguna sede para Presente no hay nada que administrar: se elige primero.
    if (!context.mounted) return const [];
    final elegida = await pedirPrimeraSede(context, estado.api);
    if (elegida == null) return const [];
    sedes = [elegida];
  }
  await estado.sesion.guardarSedes(sedes);
  return sedes;
}

/// Abre el panel encima de la pantalla de marcación, en un teléfono
/// vinculado (administrador, gerente o talento humano). Al salir, el teléfono
/// sigue marcando asistencia.
Future<void> abrirPanel(BuildContext context) async {
  final estado = context.read<EstadoApp>();
  final sesion = estado.sesion.sesion;
  if (sesion == null || !sesion.esAdministrativo) return;

  List<Sede> sedes;
  try {
    sedes = await sedesDelPanel(context, estado);
  } on ApiError catch (e) {
    if (context.mounted) avisar(context, e.mensaje, error: true);
    return;
  }
  if (sedes.isEmpty || !context.mounted) return;

  final sync = estado.sincronizador;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) {
      final panel = AdminShell(sedes: sedes);
      return sync == null ? panel : ChangeNotifierProvider.value(value: sync, child: panel);
    }),
  );
}

/// En el teléfono personal (no vinculado) con la sesión recordada, la app abre
/// directamente en el panel, como Ventario. Funciona sin internet con las
/// sedes guardadas; solo «Cerrar sesión» lo saca de aquí.
class PanelPrincipal extends StatefulWidget {
  const PanelPrincipal({super.key});

  @override
  State<PanelPrincipal> createState() => _PanelPrincipalState();
}

class _PanelPrincipalState extends State<PanelPrincipal> {
  late final EstadoApp _estado = context.read<EstadoApp>();
  late Future<List<Sede>> _sedes = _cargar();

  Future<List<Sede>> _cargar() async {
    // Primero lo guardado (abre al instante y sin red); el panel actualiza
    // las sedes por su cuenta cuando hay conexión.
    final guardadas = await _estado.sesion.sedesGuardadas();
    if (guardadas.isNotEmpty) return guardadas;
    if (!mounted) return const [];
    return sedesDelPanel(context, _estado);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Sede>>(
      future: _sedes,
      builder: (context, snap) {
        final sedes = snap.data;
        if (sedes != null && sedes.isNotEmpty) return AdminShell(sedes: sedes, esInicio: true);
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final error = snap.error;
        return Scaffold(
          body: SafeArea(
            child: EstadoVacio(
              icono: error is ApiError && error.sinConexion ? Icons.cloud_off_rounded : Icons.place_outlined,
              titulo: error is ApiError && error.sinConexion ? 'Sin conexión' : 'No hay sedes para mostrar',
              mensaje: error is ApiError
                  ? error.mensaje
                  : 'Conéctate a internet la primera vez para cargar las sedes de tu empresa.',
              accion: () => setState(() => _sedes = _cargar()),
              etiquetaAccion: 'Reintentar',
            ),
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(Espacio.md),
            child: TextButton.icon(
              onPressed: _estado.sesion.cerrar,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cerrar sesión'),
            ),
          ),
        );
      },
    );
  }
}

class MensajeError extends StatelessWidget {
  const MensajeError(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Espacio.sm),
        decoration: BoxDecoration(
          color: sem.peligroFondo,
          borderRadius: BorderRadius.circular(Redondeo.sm),
          border: Border.all(color: sem.peligro.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: sem.peligro, size: 20),
            const SizedBox(width: Espacio.xs),
            Expanded(child: Text(texto, style: context.textos.bodyMedium?.copyWith(color: sem.peligro))),
          ],
        ),
      ),
    );
  }
}
