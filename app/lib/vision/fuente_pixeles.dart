import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Acceso uniforme a los píxeles de una imagen en coordenadas "derechas"
/// (las mismas que usa ML Kit para reportar rostros), sin convertir el cuadro
/// completo: solo se leen los píxeles que el alineador necesita.
abstract class FuentePixeles {
  /// Dimensiones en orientación derecha.
  int get ancho;
  int get alto;

  /// Color 0xRRGGBB del píxel (x, y). Fuera de la imagen devuelve negro.
  int rgb(int x, int y);

  /// Crea la fuente a partir de un cuadro de la cámara.
  /// [rotacion] = grados (horario) que hay que girar el cuadro para verlo derecho.
  static FuentePixeles? desdeCamara(CameraImage img, int rotacion) {
    if (img.planes.isEmpty) return null;
    final plano = img.planes.first;
    if (Platform.isIOS) {
      return FuenteBgra(plano.bytes, img.width, img.height, plano.bytesPerRow);
    }
    if (img.planes.length == 1) {
      return FuenteNv21(plano.bytes, img.width, img.height, plano.bytesPerRow, rotacion);
    }
    return null;
  }
}

/// Mapea coordenadas derechas → crudas según la rotación del sensor.
mixin _Rotable {
  int get anchoCrudo;
  int get altoCrudo;
  int get rotacion;

  int get ancho => rotacion % 180 == 0 ? anchoCrudo : altoCrudo;
  int get alto => rotacion % 180 == 0 ? altoCrudo : anchoCrudo;

  /// Devuelve x | (y << 16) crudo, o -1 si cae fuera.
  int crudo(int x, int y) {
    if (x < 0 || y < 0 || x >= ancho || y >= alto) return -1;
    int rx, ry;
    switch (rotacion) {
      case 90:
        rx = y;
        ry = altoCrudo - 1 - x;
      case 180:
        rx = anchoCrudo - 1 - x;
        ry = altoCrudo - 1 - y;
      case 270:
        rx = anchoCrudo - 1 - y;
        ry = x;
      default:
        rx = x;
        ry = y;
    }
    return rx | (ry << 16);
  }
}

/// Android (CameraX entregando NV21 en un solo plano): Y completo + VU intercalado.
class FuenteNv21 with _Rotable implements FuentePixeles {
  FuenteNv21(this.bytes, this.anchoCrudo, this.altoCrudo, this.paso, this.rotacion);

  final Uint8List bytes;
  @override
  final int anchoCrudo;
  @override
  final int altoCrudo;
  final int paso;
  @override
  final int rotacion;

  @override
  int rgb(int x, int y) {
    final c = crudo(x, y);
    if (c < 0) return 0;
    final rx = c & 0xFFFF;
    final ry = c >> 16;
    final iy = ry * paso + rx;
    final iuv = altoCrudo * paso + (ry >> 1) * paso + (rx & ~1);
    if (iuv + 1 >= bytes.length) return 0;
    final yy = bytes[iy];
    final v = bytes[iuv] - 128;
    final u = bytes[iuv + 1] - 128;
    final r = (yy + 1.370705 * v).round().clamp(0, 255);
    final g = (yy - 0.698001 * v - 0.337633 * u).round().clamp(0, 255);
    final b = (yy + 1.732446 * u).round().clamp(0, 255);
    return (r << 16) | (g << 8) | b;
  }
}

/// iOS: BGRA8888. El plugin de cámara ya entrega el cuadro derecho.
class FuenteBgra implements FuentePixeles {
  FuenteBgra(this.bytes, this.ancho, this.alto, this.paso);

  final Uint8List bytes;
  @override
  final int ancho;
  @override
  final int alto;
  final int paso;

  @override
  int rgb(int x, int y) {
    if (x < 0 || y < 0 || x >= ancho || y >= alto) return 0;
    final i = y * paso + x * 4;
    return (bytes[i + 2] << 16) | (bytes[i + 1] << 8) | bytes[i];
  }
}

/// Imagen ya decodificada en RGB contiguo (fotos JPEG descargadas).
class FuenteRgb implements FuentePixeles {
  FuenteRgb(this.bytes, this.ancho, this.alto);

  final Uint8List bytes;
  @override
  final int ancho;
  @override
  final int alto;

  @override
  int rgb(int x, int y) {
    if (x < 0 || y < 0 || x >= ancho || y >= alto) return 0;
    final i = (y * ancho + x) * 3;
    return (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
  }
}
