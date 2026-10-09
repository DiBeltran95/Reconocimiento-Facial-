import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/constantes.dart';
import 'fuente_pixeles.dart';

/// Alinea el rostro a la plantilla canónica de ArcFace (112×112): los ojos
/// siempre quedan en la misma posición y horizontales. Esto hace que el
/// vector facial dependa de la persona y no de cómo se paró frente a la cámara.
abstract final class Alineador {
  // Plantilla ArcFace normalizada (ojo izquierdo/derecho de la imagen).
  static const _ojoIzqX = 38.2946 / 112;
  static const _ojoDerX = 73.5318 / 112;
  static const _ojosY = 51.6 / 112;

  /// Posición de los ojos en la imagen (ordenados de izquierda a derecha).
  static (Offset, Offset) ojos(Face rostro) {
    final a = rostro.landmarks[FaceLandmarkType.leftEye]?.position;
    final b = rostro.landmarks[FaceLandmarkType.rightEye]?.position;
    if (a != null && b != null) {
      final pa = Offset(a.x.toDouble(), a.y.toDouble());
      final pb = Offset(b.x.toDouble(), b.y.toDouble());
      return pa.dx <= pb.dx ? (pa, pb) : (pb, pa);
    }
    // Sin puntos de referencia: se estiman desde el recuadro del rostro.
    final r = rostro.boundingBox;
    final y = r.top + r.height * 0.40;
    return (Offset(r.left + r.width * 0.30, y), Offset(r.left + r.width * 0.70, y));
  }

  /// Tensor de entrada del modelo (HWC, RGB normalizado) a partir del rostro.
  /// Con [espejo] se genera la versión reflejada (robustez ante selfies).
  static Float32List entrada(FuentePixeles f, (Offset, Offset) ojos, int tam, {bool espejo = false}) {
    final (izq, der) = ojos;
    final dx = der.dx - izq.dx;
    final dy = der.dy - izq.dy;
    final distOrigen = math.max(1.0, math.sqrt(dx * dx + dy * dy));
    final angulo = math.atan2(dy, dx);
    final cosA = math.cos(angulo);
    final sinA = math.sin(angulo);

    final distDestino = (_ojoDerX - _ojoIzqX) * tam;
    final escala = distOrigen / distDestino; // píxeles origen por píxel destino
    final cxDestino = (_ojoIzqX + _ojoDerX) / 2 * tam;
    final cyDestino = _ojosY * tam;
    final cxOrigen = (izq.dx + der.dx) / 2;
    final cyOrigen = (izq.dy + der.dy) / 2;

    final salida = Float32List(tam * tam * 3);
    const media = Constantes.modeloMedia;
    const div = Constantes.modeloEscala;
    var i = 0;
    for (var v = 0; v < tam; v++) {
      final ry = (v - cyDestino) * escala;
      for (var u = 0; u < tam; u++) {
        final uu = espejo ? tam - 1 - u : u;
        final rx = (uu - cxDestino) * escala;
        final sx = cxOrigen + rx * cosA - ry * sinA;
        final sy = cyOrigen + rx * sinA + ry * cosA;
        final c = _bilineal(f, sx, sy);
        salida[i++] = (((c >> 16) & 0xFF) - media) / div;
        salida[i++] = (((c >> 8) & 0xFF) - media) / div;
        salida[i++] = ((c & 0xFF) - media) / div;
      }
    }
    return salida;
  }

  static int _bilineal(FuentePixeles f, double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final fx = x - x0;
    final fy = y - y0;
    final c00 = f.rgb(x0, y0);
    final c10 = f.rgb(x0 + 1, y0);
    final c01 = f.rgb(x0, y0 + 1);
    final c11 = f.rgb(x0 + 1, y0 + 1);
    int canal(int s) {
      final a = ((c00 >> s) & 0xFF) * (1 - fx) + ((c10 >> s) & 0xFF) * fx;
      final b = ((c01 >> s) & 0xFF) * (1 - fx) + ((c11 >> s) & 0xFF) * fx;
      return (a * (1 - fy) + b * fy).round();
    }

    return (canal(16) << 16) | (canal(8) << 8) | canal(0);
  }
}
