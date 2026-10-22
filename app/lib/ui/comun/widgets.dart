import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';

/// Panel de vidrio esmerilado con borde neón: base de toda la información
/// que flota sobre la cámara en el kiosco.
class PanelVidrio extends StatelessWidget {
  const PanelVidrio({
    super.key,
    required this.child,
    this.color = Hud.cian,
    this.padding = const EdgeInsets.all(Espacio.lg),
    this.radio = Redondeo.xl,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final borde = BorderRadius.circular(radio);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borde,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 28, spreadRadius: -6)],
      ),
      child: ClipRRect(
        borderRadius: borde,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borde,
              color: Hud.panel,
              border: Border.all(color: color.withValues(alpha: 0.55)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.10), Colors.transparent],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Avatar con foto local, foto remota (con cabeceras) o iniciales.
class AvatarEmpleado extends StatelessWidget {
  const AvatarEmpleado({
    super.key,
    required this.nombre,
    this.archivo,
    this.url,
    this.cabeceras,
    this.tam = 44,
    this.anillo,
  });

  final String nombre;
  final String? archivo;
  final String? url;
  final Map<String, String>? cabeceras;
  final double tam;
  final Color? anillo;

  @override
  Widget build(BuildContext context) {
    final sem = Theme.of(context).extension<Semanticos>();
    final degradado = sem?.degradado ?? [Hud.cian, Hud.azul];
    Widget iniciales() => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [degradado[0].withValues(alpha: 0.30), degradado[1].withValues(alpha: 0.30)],
            ),
          ),
          child: Center(
            child: Text(
              Formato.iniciales(nombre),
              style: Hud.titulo(tam: tam * 0.36, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        );

    Widget contenido;
    if (archivo != null && File(archivo!).existsSync()) {
      contenido = Image.file(File(archivo!), fit: BoxFit.cover, cacheWidth: (tam * 3).round(), gaplessPlayback: true);
    } else if (url != null) {
      contenido = Image.network(
        url!,
        headers: cabeceras,
        fit: BoxFit.cover,
        cacheWidth: (tam * 3).round(),
        errorBuilder: (_, _, _) => iniciales(),
      );
    } else {
      contenido = iniciales();
    }

    return Semantics(
      label: 'Foto de $nombre',
      image: true,
      child: Container(
        width: tam,
        height: tam,
        padding: EdgeInsets.all(anillo == null ? 0 : 2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: anillo == null ? null : Border.all(color: anillo!, width: 2),
          boxShadow: anillo == null ? null : [BoxShadow(color: anillo!.withValues(alpha: 0.45), blurRadius: 18)],
        ),
        child: ClipOval(child: contenido),
      ),
    );
  }
}

/// Estado vacío o de error con acción opcional.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.mensaje,
    this.accion,
    this.etiquetaAccion,
    this.color,
  });

  final IconData icono;
  final String titulo;
  final String? mensaje;
  final VoidCallback? accion;
  final String? etiquetaAccion;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colores.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.withValues(alpha: 0.12),
                  border: Border.all(color: c.withValues(alpha: 0.4)),
                ),
                child: Icon(icono, size: 32, color: c),
              ),
              const SizedBox(height: Espacio.md),
              Text(titulo, style: context.textos.titleLarge, textAlign: TextAlign.center),
              if (mensaje != null) ...[
                const SizedBox(height: Espacio.xs),
                Text(
                  mensaje!,
                  style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
                  textAlign: TextAlign.center,
                ),
              ],
              if (accion != null) ...[
                const SizedBox(height: Espacio.lg),
                FilledButton.tonal(onPressed: accion, child: Text(etiquetaAccion ?? 'Reintentar')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Fondo tecnológico: rejilla de puntos y resplandores difusos.
class FondoTecnico extends StatelessWidget {
  const FondoTecnico({super.key, required this.child, this.intensidad = 1});

  final Widget child;
  final double intensidad;

  @override
  Widget build(BuildContext context) {
    final esquema = context.colores;
    final sem = context.sem;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: esquema.surface)),
        Positioned.fill(
          child: CustomPaint(
            painter: _PintorFondo(
              puntos: esquema.primary.withValues(alpha: 0.07 * intensidad),
              brillo1: sem.degradado[0].withValues(alpha: 0.16 * intensidad),
              brillo2: sem.degradado[1].withValues(alpha: 0.12 * intensidad),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _PintorFondo extends CustomPainter {
  _PintorFondo({required this.puntos, required this.brillo1, required this.brillo2});
  final Color puntos;
  final Color brillo1;
  final Color brillo2;

  @override
  void paint(Canvas canvas, Size size) {
    void halo(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()..shader = ui.Gradient.radial(c, r, [color, color.withValues(alpha: 0)]),
      );
    }

    halo(Offset(size.width * 0.9, size.height * 0.05), math.max(size.width, 320) * 0.75, brillo1);
    halo(Offset(size.width * 0.05, size.height * 0.85), math.max(size.width, 320) * 0.6, brillo2);

    const paso = 24.0;
    final lista = <Offset>[
      for (var y = paso / 2; y < size.height; y += paso)
        for (var x = paso / 2; x < size.width; x += paso) Offset(x, y),
    ];
    canvas.drawPoints(
      ui.PointMode.points,
      lista,
      Paint()
        ..color = puntos
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PintorFondo v) => v.puntos != puntos || v.brillo1 != brillo1 || v.brillo2 != brillo2;
}

/// Etiqueta técnica en mayúsculas y monoespaciada (estilo HUD).
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, this.color});
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: context.textos.labelSmall?.copyWith(color: color ?? context.colores.primary),
    );
  }
}

/// Píldora de estado con punto luminoso (color + texto, nunca solo color).
class Pildora extends StatelessWidget {
  const Pildora({super.key, required this.texto, required this.color, this.fondo, this.icono});
  final String texto;
  final Color color;
  final Color? fondo;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo ?? color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null)
            Icon(icono, size: 14, color: color)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)],
              ),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso flotante vigente (se reemplaza si llega otro).
OverlayEntry? _avisoFlotante;

/// Mensaje breve en la parte inferior.
///
/// Desde una hoja inferior o un diálogo, el snackbar quedaría DETRÁS de ellos
/// y la persona no vería el mensaje: ahí el aviso flota arriba, encima de todo.
void avisar(BuildContext context, String mensaje, {bool error = false}) {
  final color = error ? const Color(0xFFFB7185) : const Color(0xFF34D399);
  final overlay = ModalRoute.of(context) is PopupRoute ? Overlay.maybeOf(context, rootOverlay: true) : null;
  if (overlay != null) {
    _avisoFlotante?.remove();
    late final OverlayEntry entrada;
    void quitar() {
      if (_avisoFlotante == entrada) _avisoFlotante = null;
      if (entrada.mounted) entrada.remove();
    }

    entrada = OverlayEntry(
      builder: (_) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, 0),
            child: Semantics(
              liveRegion: true,
              child: Material(
                color: Hud.panel,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Redondeo.md),
                  side: BorderSide(color: color.withValues(alpha: 0.6)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Redondeo.md),
                  onTap: quitar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Espacio.md, vertical: Espacio.sm),
                    child: Row(
                      children: [
                        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: color, size: 20),
                        const SizedBox(width: Espacio.sm),
                        Expanded(child: Text(mensaje, style: const TextStyle(color: Hud.texto))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _avisoFlotante = entrada;
    overlay.insert(entrada);
    Timer(const Duration(seconds: 4), quitar);
    return;
  }
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: error ? const Color(0xFFFB7185) : const Color(0xFF34D399),
            size: 20,
          ),
          const SizedBox(width: Espacio.sm),
          Expanded(child: Text(mensaje)),
        ],
      ),
    ),
  );
}
