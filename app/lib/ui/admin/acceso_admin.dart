import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../comun/widgets.dart';
import 'admin_shell.dart';
import 'sedes_page.dart' show pedirPrimeraSede;

/// Abre el panel de administración (administrador, gerente o talento humano)
/// con la sesión ya iniciada. Funciona en cualquier teléfono: si además es un
/// punto de marcación, el panel muestra su sincronización y permite
/// desvincularlo. Al salir, el teléfono sigue como estaba.
Future<void> abrirPanel(BuildContext context) async {
  final estado = context.read<EstadoApp>();
  final sesion = estado.sesion.sesion;
  if (sesion == null || !sesion.esAdministrativo) return;

  List<Sede> sedes;
  try {
    sedes = await estado.api.sedes();
    if (sedes.isEmpty) {
      if (!sesion.esAdminEmpresa) {
        throw const ApiError(403, 'Tu cuenta no tiene sedes en Presente. Pídele al administrador que te asigne una.');
      }
      // Sin ninguna sede para Presente no hay nada que administrar: se elige primero.
      if (!context.mounted) return;
      final elegida = await pedirPrimeraSede(context, estado.api);
      if (elegida == null) return;
      sedes = [elegida];
    }
  } on ApiError catch (e) {
    if (context.mounted) avisar(context, e.mensaje, error: true);
    return;
  }
  if (!context.mounted) return;

  final sync = estado.sincronizador;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) {
      final panel = AdminShell(sedes: sedes);
      return sync == null ? panel : ChangeNotifierProvider.value(value: sync, child: panel);
    }),
  );
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
