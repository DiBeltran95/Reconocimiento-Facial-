import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../admin/componentes_kiosco.dart' show Seccion;
import '../comun/widgets.dart';

/// Uso de un recurso del plan: nombre, «2 de 3» y una barra.
///
/// El estado se dice con número y texto («límite alcanzado»), no solo con el
/// color de la barra: así se entiende sin distinguir colores y con lector de
/// pantalla.
class MedidorUso extends StatelessWidget {
  const MedidorUso({super.key, required this.recurso, required this.uso, this.compacto = false});

  final RecursoLimitado recurso;
  final RecursoPlan uso;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final maximo = uso.maximo;
    final fraccion = maximo == null || maximo == 0 ? 0.0 : (uso.usados / maximo).clamp(0.0, 1.0);
    final color = uso.lleno
        ? sem.peligro
        : fraccion >= 0.8
            ? sem.alerta
            : context.colores.primary;
    final cifra = maximo == null ? '${uso.usados}' : '${uso.usados} de $maximo';
    final estado = maximo == null
        ? 'Sin límite'
        : uso.lleno
            ? 'Límite alcanzado'
            : '${uso.disponibles} disponible${uso.disponibles == 1 ? '' : 's'}';

    return Semantics(
      label: '${recurso.titulo}: $cifra. $estado',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(recurso.titulo, style: context.textos.titleSmall)),
              Text(cifra, style: context.textos.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: maximo == null ? 0 : fraccion,
              minHeight: compacto ? 4 : 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.16),
            ),
          ),
          if (!compacto) ...[
            const SizedBox(height: 4),
            Text(estado, style: context.textos.bodySmall?.copyWith(color: uso.lleno ? sem.peligro : sem.textoSuave)),
          ],
        ],
      ),
    );
  }
}

/// Hoja inferior que explica que el plan no admite un [recurso] más.
///
/// Se muestra ANTES de abrir el formulario (para no hacer llenar datos que el
/// servidor va a rechazar) y también si el servidor responde LIMITE_PLAN. El
/// texto es neutro y sin enlaces de pago: los planes se gestionan fuera de la
/// app (política de Google Play).
Future<void> mostrarHojaLimite(BuildContext context, RecursoLimitado recurso, {PlanEmpresa? plan}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final sem = ctx.sem;
      final uso = plan?.de(recurso);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  child: Icon(Icons.workspace_premium_outlined, color: sem.alerta, size: 28),
                ),
              ),
              const SizedBox(height: Espacio.md),
              Text('Llegaste al límite de tu plan', style: ctx.textos.headlineSmall),
              const SizedBox(height: Espacio.xs),
              Text(
                uso?.maximo == null
                    ? 'Tu plan no admite más ${recurso.plural} por ahora.'
                    : 'Tu plan ${plan!.nombre} incluye hasta ${uso!.maximo} ${uso.maximo == 1 ? recurso.singular : recurso.plural}'
                        ' y ya los estás usando.',
                style: ctx.textos.bodyLarge?.copyWith(color: sem.textoSuave),
              ),
              if (plan?.vencido ?? false) ...[
                const SizedBox(height: Espacio.xs),
                Text(
                  'Tu plan venció y la empresa opera con los límites del plan Gratis. Lo que ya tenías se conserva.',
                  style: ctx.textos.bodyMedium?.copyWith(color: sem.alerta),
                ),
              ],
              if (uso != null) ...[
                const SizedBox(height: Espacio.lg),
                MedidorUso(recurso: recurso, uso: uso),
              ],
              const SizedBox(height: Espacio.lg),
              _Sugerencia(
                icono: Icons.swap_horiz_rounded,
                texto: recurso == RecursoLimitado.personas
                    ? 'Puedes dar de baja a alguien que ya no trabaje en la empresa para liberar su cupo.'
                    : recurso == RecursoLimitado.sedes
                        ? 'Puedes desactivar una sede que ya no uses para liberar su cupo.'
                        : 'Puedes desactivar un producto que ya no vendas para liberar su cupo.',
              ),
              const SizedBox(height: Espacio.sm),
              const _Sugerencia(
                icono: Icons.support_agent_rounded,
                texto: 'Tu plan lo gestiona el equipo de la plataforma: el administrador de tu empresa puede solicitar un cambio.',
              ),
              const SizedBox(height: Espacio.lg),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Entendido')),
            ],
          ),
        ),
      );
    },
  );
}

class _Sugerencia extends StatelessWidget {
  const _Sugerencia({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 20, color: context.colores.primary),
        const SizedBox(width: Espacio.sm),
        Expanded(child: Text(texto, style: context.textos.bodyMedium)),
      ],
    );
  }
}

/// ¿Cabe un [recurso] más? Consulta el plan y, si no cabe, explica el límite.
///
/// Si no hay red o el servidor no responde, deja continuar: el servidor tiene
/// la última palabra y su respuesta LIMITE_PLAN abre la misma hoja.
Future<bool> hayCupo(BuildContext context, Api api, RecursoLimitado recurso) async {
  PlanEmpresa? plan;
  try {
    plan = await api.plan();
  } on ApiError {
    return true;
  }
  if (plan == null || !plan.de(recurso).lleno) return true;
  if (context.mounted) await mostrarHojaLimite(context, recurso, plan: plan);
  return false;
}

/// Si [error] es LIMITE_PLAN, explica el límite y devuelve true; si no, false.
Future<bool> manejarLimite(BuildContext context, Api api, Object error) async {
  if (error is! ApiError || !error.limitePlan) return false;
  final recurso = RecursoLimitado.desdeApi(error.recurso) ?? RecursoLimitado.personas;
  PlanEmpresa? plan;
  try {
    plan = await api.plan();
  } on ApiError {
    plan = null;
  }
  if (context.mounted) await mostrarHojaLimite(context, recurso, plan: plan);
  return true;
}

/// Tarjeta con el plan vigente de una app y sus medidores.
class TarjetaPlan extends StatelessWidget {
  const TarjetaPlan({super.key, required this.plan});
  final PlanEmpresa plan;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final vence = plan.vence;
    return Seccion(
      titulo: 'Plan de ${plan.nombreApp}',
      hijos: [
        Row(
          children: [
            Expanded(child: Text(plan.nombre, style: context.textos.headlineSmall)),
            Pildora(
              texto: plan.vencido ? 'Vencido' : (plan.esGratis ? 'Gratis' : 'Activo'),
              color: plan.vencido ? sem.alerta : (plan.esGratis ? sem.textoSuave : sem.entrada),
            ),
          ],
        ),
        if (vence != null) ...[
          const SizedBox(height: Espacio.xxs),
          Text(
            plan.vencido
                ? 'Venció el ${_fecha(vence)}: ${plan.nombreApp} opera con los límites del plan Gratis.'
                : 'Vigente hasta el ${_fecha(vence)}',
            style: context.textos.bodySmall?.copyWith(color: plan.vencido ? sem.alerta : sem.textoSuave),
          ),
        ],
        const SizedBox(height: Espacio.md),
        for (final r in plan.recursos) ...[
          MedidorUso(recurso: r, uso: plan.de(r)),
          if (r != plan.recursos.last) const SizedBox(height: Espacio.md),
        ],
        const SizedBox(height: Espacio.md),
        Text(
          plan.esPresente
              ? 'Las personas incluyen a gerentes, talento humano y a quienes solo marcan asistencia. '
                  'Cada app tiene su propio plan: para ampliarlo, el administrador lo solicita al equipo de la plataforma.'
              : 'Cada app tiene su propio plan: para ampliarlo, el administrador lo solicita al equipo de la plataforma.',
          style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
        ),
      ],
    );
  }

  static String _fecha(DateTime f) {
    const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${f.day} ${meses[f.month - 1]} ${f.year}';
  }
}
