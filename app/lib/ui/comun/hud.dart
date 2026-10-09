import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/tema.dart';
import 'camara.dart';

/// HUD biométrico: retícula con marcas, arcos en rotación, línea de escaneo,
/// malla del rostro en vivo y anillo de progreso. Una sola capa pintada
/// (RepaintBoundary) para no recargar la cámara que está debajo.
///
/// Con "reducir movimiento" activo en el sistema, todo queda estático y la
/// información se conserva (color, textos y progreso).
class HudBiometrico extends StatefulWidget {
  const HudBiometrico({
    super.key,
    required this.color,
    this.rostro,
    this.mapa,
    this.escaneando = true,
    this.segmentos = 0,
    this.completados = 0,
    this.pulso = 0,
    this.lecturaSuperior,
    this.lecturaInferior,
    this.lecturaDerecha,
  });

  /// Color de acento del estado actual (se anima al cambiar).
  final Color color;
  final Face? rostro;
  final MapaPantalla? mapa;
  final bool escaneando;

  /// Anillo segmentado (captura de fotos): total y completados.
  final int segmentos;
  final int completados;

  /// Disparador del pulso de éxito: cambia el valor para lanzar la onda.
  final int pulso;

  final String? lecturaSuperior;
  final String? lecturaInferior;
  final String? lecturaDerecha;

  /// Óvalo guía, compartido con las pantallas para ubicar paneles.
  static Rect ovalo(Size s) {
    final ancho = math.min(s.width * 0.70, 340.0);
    final alto = ancho * 1.30;
    return Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.43), width: ancho, height: alto);
  }

  @override
  State<HudBiometrico> createState() => _HudBiometricoState();
}

class _HudBiometricoState extends State<HudBiometrico> with TickerProviderStateMixin {
  late final AnimationController _giro = AnimationController(vsync: this, duration: Duraciones.giro);
  late final AnimationController _escaneo = AnimationController(vsync: this, duration: Duraciones.escaneo);
  late final AnimationController _onda = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _sinMovimiento = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sinMovimiento = MediaQuery.disableAnimationsOf(context);
    if (_sinMovimiento) {
      _giro.stop();
      _escaneo.stop();
    } else {
      if (!_giro.isAnimating) _giro.repeat();
      if (!_escaneo.isAnimating) _escaneo.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(HudBiometrico viejo) {
    super.didUpdateWidget(viejo);
    if (widget.pulso != viejo.pulso && !_sinMovimiento) _onda.forward(from: 0);
  }

  @override
  void dispose() {
    _giro.dispose();
    _escaneo.dispose();
    _onda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contornos = _contornos();
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.color),
      duration: Duraciones.media,
      builder: (context, color, _) {
        final c = color ?? widget.color;
        return LayoutBuilder(builder: (context, caja) {
          final tam = caja.biggest;
          final ovalo = HudBiometrico.ovalo(tam);
          final marco = ovalo.inflate(36);
          return Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PintorHud(
                      color: c,
                      giro: _giro,
                      escaneo: _escaneo,
                      onda: _onda,
                      contornos: contornos,
                      escaneando: widget.escaneando && !_sinMovimiento,
                      segmentos: widget.segmentos,
                      completados: widget.completados,
                    ),
                  ),
                ),
              ),
              if (widget.lecturaSuperior != null)
                Positioned(
                  left: marco.left,
                  top: marco.top - 22,
                  child: ExcludeSemantics(child: _Lectura(widget.lecturaSuperior!, c)),
                ),
              if (widget.lecturaDerecha != null)
                Positioned(
                  right: tam.width - marco.right,
                  top: marco.top - 22,
                  child: ExcludeSemantics(child: _Lectura(widget.lecturaDerecha!, c)),
                ),
              if (widget.lecturaInferior != null)
                Positioned(
                  left: marco.left,
                  top: marco.bottom + 8,
                  child: ExcludeSemantics(child: _Lectura(widget.lecturaInferior!, c)),
                ),
            ],
          );
        });
      },
    );
  }

  /// Contornos del rostro (ojos, cejas, labios, nariz, óvalo) en pantalla.
  List<List<Offset>> _contornos() {
    final r = widget.rostro;
    final m = widget.mapa;
    if (r == null || m == null) return const [];
    final lista = <List<Offset>>[];
    for (final c in r.contours.values) {
      if (c == null || c.points.isEmpty) continue;
      lista.add([for (final p in c.points) m.punto(p.x.toDouble(), p.y.toDouble())]);
    }
    return lista;
  }
}

class _Lectura extends StatelessWidget {
  const _Lectura(this.texto, this.color);
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: Hud.mono(tam: 11, color: color, peso: FontWeight.w600, espaciado: 1.6).copyWith(
        shadows: Hud.brillo(color, radio: 8),
      ),
    );
  }
}

class _PintorHud extends CustomPainter {
  _PintorHud({
    required this.color,
    required this.giro,
    required this.escaneo,
    required this.onda,
    required this.contornos,
    required this.escaneando,
    required this.segmentos,
    required this.completados,
  }) : super(repaint: Listenable.merge([giro, escaneo, onda]));

  final Color color;
  final Animation<double> giro;
  final Animation<double> escaneo;
  final Animation<double> onda;
  final List<List<Offset>> contornos;
  final bool escaneando;
  final int segmentos;
  final int completados;

  static const _dosPi = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final o = HudBiometrico.ovalo(size);

    // 1. Velo oscuro con ventana ovalada.
    final velo = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(o);
    canvas.drawPath(velo, Paint()..color = Hud.velo);

    // 2. Rejilla técnica tenue alrededor (solo fuera del óvalo).
    _rejilla(canvas, size, o);

    // 3. Contorno del óvalo con halo.
    canvas.drawOval(
      o,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = color.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawOval(
      o,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color,
    );

    // 4. Anillo de marcas (cada 5°, largas cada 30°) con barrido luminoso.
    final anillo = o.inflate(14);
    final angGiro = giro.value * _dosPi;
    final marca = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 72; i++) {
      final a = i * _dosPi / 72;
      final larga = i % 6 == 0;
      var d = (a - angGiro) % _dosPi;
      if (d < 0) d += _dosPi;
      final cerca = math.max(0.0, 1 - d / 1.2);
      marca.color = color.withValues(alpha: 0.22 + 0.6 * cerca);
      final ext = _enElipse(anillo, a);
      final interior = _enElipse(anillo.deflate(larga ? 9 : 4), a);
      canvas.drawLine(interior, ext, marca);
    }

    // 5. Arcos orbitando en sentidos opuestos.
    final orbita = o.inflate(28);
    final arco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.9);
    canvas.drawArc(orbita, angGiro, 0.85, false, arco);
    canvas.drawArc(orbita, angGiro + math.pi, 0.35, false, arco..color = color.withValues(alpha: 0.55));
    canvas.drawArc(o.inflate(40), -angGiro * 1.6, 0.5, false, arco..strokeWidth = 1..color = Hud.azul.withValues(alpha: 0.7));

    // 6. Escuadras de encuadre.
    _escuadras(canvas, o.inflate(36));

    // 7. Línea de escaneo con estela (recortada al óvalo).
    if (escaneando) {
      final t = Curves.easeInOut.transform(escaneo.value);
      final y = o.top + o.height * t;
      canvas.save();
      canvas.clipPath(Path()..addOval(o));
      final estela = Rect.fromLTRB(o.left, y - 46, o.right, y);
      canvas.drawRect(
        estela,
        Paint()
          ..shader = ui.Gradient.linear(
            estela.topCenter,
            estela.bottomCenter,
            [color.withValues(alpha: 0), color.withValues(alpha: 0.22)],
          ),
      );
      canvas.drawLine(
        Offset(o.left, y),
        Offset(o.right, y),
        Paint()
          ..strokeWidth = 2
          ..shader = ui.Gradient.linear(
            Offset(o.left, y),
            Offset(o.right, y),
            [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
            [0, 0.5, 1],
          ),
      );
      canvas.restore();
    }

    // 8. Malla del rostro detectado.
    if (contornos.isNotEmpty) {
      final linea = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = color.withValues(alpha: 0.45);
      final punto = Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      for (final c in contornos) {
        if (c.length > 1) canvas.drawPath(Path()..addPolygon(c, c.length > 20), linea);
        canvas.drawPoints(ui.PointMode.points, c, punto);
      }
    }

    // 9. Anillo segmentado de progreso (captura guiada).
    if (segmentos > 0) {
      final tramo = _dosPi / segmentos;
      const hueco = 0.12;
      final seg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < segmentos; i++) {
        seg.color = i < completados ? Hud.entrada : color.withValues(alpha: 0.22);
        canvas.drawArc(o.inflate(6), -math.pi / 2 + i * tramo + hueco / 2, tramo - hueco, false, seg);
      }
    }

    // 10. Onda expansiva al confirmar.
    if (onda.value > 0 && onda.value < 1) {
      final v = Curves.easeOutCubic.transform(onda.value);
      canvas.drawOval(
        o.inflate(v * 90),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - v) + 0.5
          ..color = color.withValues(alpha: (1 - v) * 0.9),
      );
    }
  }

  Offset _enElipse(Rect r, double a) =>
      Offset(r.center.dx + r.width / 2 * math.cos(a), r.center.dy + r.height / 2 * math.sin(a));

  void _rejilla(Canvas canvas, Size size, Rect o) {
    const paso = 26.0;
    final puntos = <Offset>[];
    final zona = o.inflate(56);
    for (var y = paso / 2; y < size.height; y += paso) {
      for (var x = paso / 2; x < size.width; x += paso) {
        final p = Offset(x, y);
        if (!_dentroElipse(zona, p)) puntos.add(p);
      }
    }
    canvas.drawPoints(
      ui.PointMode.points,
      puntos,
      Paint()
        ..color = Hud.cian.withValues(alpha: 0.10)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  bool _dentroElipse(Rect r, Offset p) {
    final dx = (p.dx - r.center.dx) / (r.width / 2);
    final dy = (p.dy - r.center.dy) / (r.height / 2);
    return dx * dx + dy * dy <= 1;
  }

  void _escuadras(Canvas canvas, Rect m) {
    const largo = 26.0;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.square
      ..color = color;
    final esquinas = [
      (m.topLeft, 1.0, 1.0),
      (m.topRight, -1.0, 1.0),
      (m.bottomLeft, 1.0, -1.0),
      (m.bottomRight, -1.0, -1.0),
    ];
    for (final (e, sx, sy) in esquinas) {
      canvas.drawPath(
        Path()
          ..moveTo(e.dx, e.dy + largo * sy)
          ..lineTo(e.dx, e.dy)
          ..lineTo(e.dx + largo * sx, e.dy),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorHud v) =>
      v.color != color ||
      v.contornos != contornos ||
      v.escaneando != escaneando ||
      v.completados != completados ||
      v.segmentos != segmentos;
}
