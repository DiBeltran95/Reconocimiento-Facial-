import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../servicios/asistencia.dart';
import '../../servicios/estado_app.dart';
import '../../servicios/sincronizador.dart';
import '../comun/widgets.dart';

/// Tarjeta con título técnico (base de las pantallas de ajustes).
class Seccion extends StatelessWidget {
  const Seccion({super.key, required this.titulo, required this.hijos, this.colorTitulo});
  final String titulo;
  final List<Widget> hijos;
  final Color? colorTitulo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Etiqueta(titulo, color: colorTitulo),
            const SizedBox(height: Espacio.sm),
            ...hijos,
          ],
        ),
      ),
    );
  }
}

class Dato extends StatelessWidget {
  const Dato({super.key, required this.icono, required this.etiqueta, required this.valor});
  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espacio.xs),
      child: Row(
        children: [
          Icon(icono, size: 20, color: context.sem.textoSuave),
          const SizedBox(width: Espacio.sm),
          SizedBox(width: 76, child: Text(etiqueta, style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave))),
          Expanded(child: Text(valor, style: context.textos.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class Contador extends StatelessWidget {
  const Contador({super.key, required this.valor, required this.etiqueta, this.color});
  final String valor;
  final String etiqueta;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: '$etiqueta: $valor',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(valor, style: Hud.titulo(tam: 28, color: color ?? context.colores.onSurface)),
            Text(
              etiqueta.toUpperCase(),
              textAlign: TextAlign.center,
              style: context.textos.labelSmall?.copyWith(color: context.sem.textoSuave),
            ),
          ],
        ),
      ),
    );
  }
}

class Aviso extends StatelessWidget {
  const Aviso({super.key, required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final s = context.sem;
    return Container(
      padding: const EdgeInsets.all(Espacio.sm),
      decoration: BoxDecoration(
        color: s.alertaFondo,
        borderRadius: BorderRadius.circular(Redondeo.sm),
        border: Border.all(color: s.alerta.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icono, color: s.alerta, size: 20),
          const SizedBox(width: Espacio.xs),
          Expanded(child: Text(texto, style: context.textos.bodySmall?.copyWith(color: context.colores.onSurface))),
        ],
      ),
    );
  }
}

class TarjetaEsteKiosco extends StatelessWidget {
  const TarjetaEsteKiosco({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.read<EstadoApp>().config;
    return Seccion(
      titulo: 'Este kiosco',
      hijos: [
        Dato(icono: Icons.phone_android_rounded, etiqueta: 'Nombre', valor: config?.nombre ?? '—'),
        Dato(icono: Icons.location_on_outlined, etiqueta: 'Sede', valor: config?.sede.nombre ?? '—'),
        Dato(icono: Icons.dns_outlined, etiqueta: 'Servidor', valor: config?.url ?? '—'),
      ],
    );
  }
}

class TarjetaSincronizacion extends StatelessWidget {
  const TarjetaSincronizacion({super.key, this.permitirReprocesar = false});
  final bool permitirReprocesar;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<Sincronizador>();
    final sem = context.sem;
    final p = sync.progresoRostros;
    return Seccion(
      titulo: 'Sincronización',
      hijos: [
        Row(
          children: [
            Pildora(texto: sync.enLinea ? 'En línea' : 'Sin conexión', color: sync.enLinea ? sem.entrada : sem.alerta),
            const Spacer(),
            Text('Última: ${Formato.haceCuanto(sync.ultimaSync)}', style: context.textos.bodySmall),
          ],
        ),
        const SizedBox(height: Espacio.md),
        Row(
          children: [
            Contador(valor: '${sync.empleados}', etiqueta: 'Empleados'),
            Contador(valor: '${sync.reconocibles}', etiqueta: 'Con rostro'),
            Contador(valor: '${sync.pendientes}', etiqueta: 'Por enviar', color: sync.pendientes > 0 ? sem.alerta : null),
          ],
        ),
        if (p != null) ...[
          const SizedBox(height: Espacio.md),
          Text('Procesando rostros ${p.hechos} de ${p.total}', style: context.textos.bodyMedium),
          const SizedBox(height: Espacio.xs),
          LinearProgressIndicator(value: p.total == 0 ? null : p.hechos / p.total),
        ],
        if (sync.relojDesfasado) ...[
          const SizedBox(height: Espacio.md),
          Aviso(
            icono: Icons.schedule_rounded,
            texto: 'La hora del equipo difiere ${(sync.desfaseReloj!.inSeconds.abs() / 60).ceil()} min '
                'de la del servidor. Corrígela en los ajustes del teléfono.',
          ),
        ],
        if (sync.error != null) ...[
          const SizedBox(height: Espacio.md),
          Aviso(icono: Icons.error_outline_rounded, texto: sync.error!),
        ],
        const SizedBox(height: Espacio.md),
        FilledButton.tonalIcon(
          onPressed: sync.sincronizando ? null : () => sync.sincronizar(),
          icon: sync.sincronizando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_rounded),
          label: Text(sync.sincronizando ? 'Sincronizando…' : 'Sincronizar ahora'),
        ),
        if (permitirReprocesar) ...[
          const SizedBox(height: Espacio.xs),
          TextButton.icon(
            onPressed: sync.sincronizando
                ? null
                : () {
                    avisar(context, 'Procesando rostros de nuevo…');
                    sync.sincronizar(forzar: true);
                  },
            icon: const Icon(Icons.memory_rounded),
            label: const Text('Volver a procesar todos los rostros'),
          ),
        ],
      ],
    );
  }
}

/// Marcaciones de hoy registradas en (o conocidas por) este kiosco.
class MarcacionesDeHoy extends StatelessWidget {
  const MarcacionesDeHoy({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = context.read<EstadoApp>();
    // Se reconstruye con cada sincronización.
    context.watch<Sincronizador>();
    return FutureBuilder(
      future: estado.almacen.marcacionesDesde(Asistencia.inicioDelDia()),
      builder: (context, snap) {
        final lista = snap.data ?? const [];
        final sem = context.sem;
        return Seccion(
          titulo: 'Marcaciones de hoy · ${lista.length}',
          hijos: [
            if (lista.isEmpty)
              Text('Aún no hay registros hoy.', style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave))
            else
              for (final r in lista.take(50))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    r.marcacion.tipo == TipoMarcacion.entrada ? Icons.login_rounded : Icons.logout_rounded,
                    color: r.marcacion.tipo == TipoMarcacion.entrada ? sem.entrada : sem.salida,
                  ),
                  title: Text(r.nombre),
                  subtitle: Text(r.marcacion.tipo.etiqueta),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Formato.hora(r.marcacion.hora), style: Hud.mono(tam: 13, color: context.colores.onSurface, espaciado: 0)),
                      const SizedBox(width: 6),
                      Icon(
                        r.marcacion.enviada ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                        size: 18,
                        color: r.marcacion.enviada ? sem.entrada : sem.alerta,
                        semanticLabel: r.marcacion.enviada ? 'Enviada' : 'Pendiente por enviar',
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}

class TarjetaDesvincular extends StatelessWidget {
  const TarjetaDesvincular({super.key});

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Seccion(
      titulo: 'Cambiar de sede o desvincular',
      colorTitulo: sem.peligro,
      hijos: [
        Text(
          'Desvincular borra de este teléfono el personal, los rostros y la configuración. '
          'Luego podrás vincularlo a otra sede. Las marcaciones sin enviar se perderán.',
          style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
        ),
        const SizedBox(height: Espacio.md),
        OutlinedButton.icon(
          onPressed: () => _desvincular(context),
          icon: const Icon(Icons.link_off_rounded),
          label: const Text('Desvincular dispositivo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: sem.peligro,
            side: BorderSide(color: sem.peligro.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }

  Future<void> _desvincular(BuildContext context) async {
    final estado = context.read<EstadoApp>();
    final pendientes = context.read<Sincronizador>().pendientes;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.link_off_rounded, color: c.sem.peligro),
        title: const Text('¿Desvincular este kiosco?'),
        content: Text(
          pendientes > 0
              ? 'Hay $pendientes marcaciones sin enviar que se perderán. Conéctate a internet y sincroniza primero si es posible.'
              : 'Tendrás que volver a configurarlo con una cuenta General o Administrativa.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.sem.peligro, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await estado.desvincular(avisarServidor: true);
  }
}
