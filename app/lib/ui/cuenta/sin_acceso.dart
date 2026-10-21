import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../data/api.dart';

/// Explica por qué una cuenta con la contraseña correcta no puede usar esta
/// app (empresa sin la app, cuenta sin rol, empresa suspendida…) y qué hacer.
///
/// Es una vista propia y no un mensaje de error: la persona no se equivocó,
/// y decirle «error» la haría reintentar en vano.
class PanelSinAcceso extends StatelessWidget {
  const PanelSinAcceso({super.key, required this.error, required this.alUsarOtraCuenta});

  final ApiError error;
  final VoidCallback alUsarOtraCuenta;

  ({IconData icono, String titulo, String texto}) get _contenido => switch (error.codigo) {
        'APP_NO_HABILITADA' => (
            icono: Icons.apps_outage_rounded,
            titulo: 'Tu empresa aún no usa Presente',
            texto: 'Tu cuenta está bien, pero esta app no está habilitada para tu empresa. '
                'El administrador puede solicitar que la activen. Si tu empresa usa Ventario, '
                'puedes seguir entrando allá con este mismo correo.',
          ),
        'SIN_ACCESO_APP' => (
            icono: Icons.person_off_outlined,
            titulo: 'Tu cuenta no tiene acceso a esta app',
            texto: 'Tu empresa usa Presente, pero a tu cuenta no le han dado un rol aquí. '
                'Pídele al administrador de tu empresa que te lo asigne desde «Equipo».',
          ),
        'EMPRESA_SUSPENDIDA' => (
            icono: Icons.pause_circle_outline_rounded,
            titulo: 'Tu empresa está suspendida',
            texto: 'Mientras esté suspendida nadie de la empresa puede entrar. '
                'El administrador de tu empresa puede comunicarse con el equipo de la plataforma.',
          ),
        'CUENTA_DESACTIVADA' => (
            icono: Icons.lock_person_outlined,
            titulo: 'Tu cuenta está desactivada',
            texto: 'El administrador de tu empresa desactivó esta cuenta. Si es un error, pídele que la reactive.',
          ),
        _ => (
            icono: Icons.domain_disabled_outlined,
            titulo: 'Tu empresa ya no está en la plataforma',
            texto: 'Esta cuenta pertenecía a una empresa que fue eliminada.',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final c = _contenido;
    final sem = context.sem;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sem.alertaFondo,
                border: Border.all(color: sem.alerta.withValues(alpha: 0.5)),
              ),
              child: Icon(c.icono, color: sem.alerta, size: 28),
            ),
          ),
          const SizedBox(height: Espacio.md),
          Text(c.titulo, style: context.textos.titleLarge),
          const SizedBox(height: Espacio.xs),
          Text(c.texto, style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave)),
          const SizedBox(height: Espacio.lg),
          OutlinedButton.icon(
            onPressed: alUsarOtraCuenta,
            icon: const Icon(Icons.switch_account_outlined),
            label: const Text('Usar otra cuenta'),
          ),
        ],
      ),
    );
  }
}
