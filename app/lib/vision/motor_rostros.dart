import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'alineador.dart';
import 'embebedor.dart';
import 'fuente_pixeles.dart';

/// Orquesta todo el trabajo de visión en el teléfono:
/// detección (ML Kit) → alineación → vector facial (MobileFaceNet).
class MotorRostros {
  MotorRostros._(this.embebedor);

  final Embebedor embebedor;

  /// Detector en vivo: rápido, con puntos de ojos (alineación), contorno
  /// (malla del HUD) y probabilidad de ojos abiertos (prueba de vida).
  final FaceDetector _enVivo = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: true,
      enableContours: true,
      enableClassification: true,
      minFaceSize: 0.2,
    ),
  );

  /// Detector para fotos: preciso, sin prisa.
  final FaceDetector _enFotos = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      minFaceSize: 0.1,
    ),
  );

  static Future<MotorRostros> iniciar() async => MotorRostros._(await Embebedor.cargar());

  static const _orientaciones = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Grados (horario) que hay que girar el cuadro para verlo derecho.
  static int rotacion(CameraDescription camara, DeviceOrientation orientacion) {
    final sensor = camara.sensorOrientation;
    if (Platform.isIOS) return sensor;
    final compensacion = _orientaciones[orientacion] ?? 0;
    return camara.lensDirection == CameraLensDirection.front
        ? (sensor + compensacion) % 360
        : (sensor - compensacion + 360) % 360;
  }

  /// Rotación para leer píxeles: en iOS el plugin ya entrega el cuadro derecho.
  static int rotacionPixeles(int rotacion) => Platform.isIOS ? 0 : rotacion;

  /// Tamaño del cuadro en orientación derecha (espacio de coordenadas de ML Kit).
  static Size tamanoDerecho(CameraImage cuadro, int rotacion) {
    final r = rotacionPixeles(rotacion);
    return r % 180 == 0
        ? Size(cuadro.width.toDouble(), cuadro.height.toDouble())
        : Size(cuadro.height.toDouble(), cuadro.width.toDouble());
  }

  InputImage? entradaDesdeCamara(CameraImage cuadro, int rotacion) {
    final giro = InputImageRotationValue.fromRawValue(rotacion);
    final formato = InputImageFormatValue.fromRawValue(cuadro.format.raw as int);
    if (giro == null || formato == null) return null;
    if (Platform.isAndroid && formato != InputImageFormat.nv21) return null;
    if (Platform.isIOS && formato != InputImageFormat.bgra8888) return null;
    if (cuadro.planes.length != 1) return null;
    final plano = cuadro.planes.first;
    return InputImage.fromBytes(
      bytes: plano.bytes,
      metadata: InputImageMetadata(
        size: Size(cuadro.width.toDouble(), cuadro.height.toDouble()),
        rotation: giro,
        format: formato,
        bytesPerRow: plano.bytesPerRow,
      ),
    );
  }

  Future<List<Face>> detectar(InputImage entrada) => _enVivo.processImage(entrada);

  /// Vector facial del rostro detectado en un cuadro de la cámara.
  Future<Float32List?> vectorDeCuadro(CameraImage cuadro, int rotacion, Face rostro) async {
    final fuente = FuentePixeles.desdeCamara(cuadro, rotacionPixeles(rotacion));
    if (fuente == null) return null;
    final entrada = Alineador.entrada(fuente, Alineador.ojos(rostro), embebedor.tam);
    return embebedor.vector(entrada);
  }

  /// Procesa una foto JPEG guardada en el teléfono. Devuelve los vectores
  /// [original, espejo] o una lista vacía si la foto no tiene un rostro claro.
  Future<List<Float32List>> vectoresDeFoto(String ruta) async {
    final rostros = await _enFotos.processImage(InputImage.fromFilePath(ruta));
    if (rostros.isEmpty) return const [];
    final rostro = mayor(rostros);

    // Decodificar el JPEG es pesado: se hace fuera del hilo de la interfaz.
    final rgb = await Isolate.run(() => _decodificarRgb(ruta));
    if (rgb == null) return const [];
    final fuente = FuenteRgb(rgb.bytes, rgb.ancho, rgb.alto);
    final (a, b) = Alineador.ojos(rostro);
    final ojos = (a * rgb.escala, b * rgb.escala);
    return [
      await embebedor.vector(Alineador.entrada(fuente, ojos, embebedor.tam)),
      await embebedor.vector(Alineador.entrada(fuente, ojos, embebedor.tam, espejo: true)),
    ];
  }

  /// Convierte un cuadro de cámara en un JPEG derecho (para el registro facial).
  static Future<Uint8List> jpegDeCuadro(CameraImage cuadro, int rotacion) {
    final r = rotacionPixeles(rotacion);
    final plano = cuadro.planes.first;
    final bytes = Uint8List.fromList(plano.bytes);
    final ancho = cuadro.width;
    final alto = cuadro.height;
    final paso = plano.bytesPerRow;
    final ios = Platform.isIOS;
    return Isolate.run(() {
      final FuentePixeles f = ios ? FuenteBgra(bytes, ancho, alto, paso) : FuenteNv21(bytes, ancho, alto, paso, r);
      final imagen = img.Image(width: f.ancho, height: f.alto);
      for (var y = 0; y < f.alto; y++) {
        for (var x = 0; x < f.ancho; x++) {
          final c = f.rgb(x, y);
          imagen.setPixelRgb(x, y, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
        }
      }
      return img.encodeJpg(imagen, quality: 90);
    });
  }

  static Face mayor(List<Face> rostros) => rostros.reduce(
        (a, b) => a.boundingBox.width * a.boundingBox.height >= b.boundingBox.width * b.boundingBox.height ? a : b,
      );

  Future<void> cerrar() async {
    await _enVivo.close();
    await _enFotos.close();
    await embebedor.cerrar();
  }
}

({Uint8List bytes, int ancho, int alto, double escala})? _decodificarRgb(String ruta) {
  final datos = File(ruta).readAsBytesSync();
  var imagen = img.decodeImage(datos);
  if (imagen == null) return null;
  imagen = img.bakeOrientation(imagen);
  final anchoOriginal = imagen.width;
  // Fotos enormes se reducen (los ojos quedan igual de nítidos para 112 px).
  final lado = math.max(imagen.width, imagen.height);
  if (lado > 1280) {
    imagen = imagen.width >= imagen.height ? img.copyResize(imagen, width: 1280) : img.copyResize(imagen, height: 1280);
  }
  return (
    bytes: imagen.getBytes(order: img.ChannelOrder.rgb),
    ancho: imagen.width,
    alto: imagen.height,
    escala: imagen.width / anchoOriginal,
  );
}
