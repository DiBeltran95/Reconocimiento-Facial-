import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../vision/motor_rostros.dart';

/// Cámara frontal con flujo de cuadros para el reconocimiento.
class CamaraFrontal {
  CameraController? controlador;
  CameraDescription? descripcion;

  bool get lista => controlador?.value.isInitialized ?? false;

  /// En Android la vista previa frontal se muestra en espejo pero los cuadros
  /// de análisis no; en iOS ambos vienen en espejo. Esto alinea la malla del HUD.
  bool get espejarHud => Platform.isAndroid && descripcion?.lensDirection == CameraLensDirection.front;

  int get rotacion => MotorRostros.rotacion(descripcion!, controlador!.value.deviceOrientation);

  Future<void> iniciar(void Function(CameraImage) alCuadro) async {
    final camaras = await availableCameras();
    if (camaras.isEmpty) throw CameraException('SinCamara', 'Este dispositivo no tiene cámara');
    descripcion = camaras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => camaras.first,
    );
    final c = CameraController(
      descripcion!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await c.initialize();
    try {
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
    await c.startImageStream(alCuadro);
    controlador = c;
  }

  Future<void> detener() async {
    final c = controlador;
    controlador = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  static String mensajeError(Object e) {
    if (e is CameraException) {
      return switch (e.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' =>
          'Sin permiso de cámara. Actívalo en Ajustes del teléfono › Aplicaciones › Presente.',
        'SinCamara' => 'Este dispositivo no tiene cámara frontal.',
        _ => 'No se pudo abrir la cámara (${e.description ?? e.code}).',
      };
    }
    return 'No se pudo abrir la cámara: $e';
  }
}

/// Vista previa que llena la pantalla (recorte tipo "cover"), como un espejo.
class VistaCamara extends StatelessWidget {
  const VistaCamara({super.key, required this.controlador});

  final CameraController controlador;

  @override
  Widget build(BuildContext context) {
    final previa = controlador.value.previewSize;
    if (!controlador.value.isInitialized || previa == null) return const SizedBox.expand();
    // previewSize viene en horizontal; la app está en vertical.
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: previa.height,
          height: previa.width,
          child: CameraPreview(controlador),
        ),
      ),
    );
  }
}

/// Traduce coordenadas del cuadro analizado (espacio de ML Kit) a pantalla,
/// replicando el recorte "cover" de [VistaCamara].
class MapaPantalla {
  MapaPantalla({required this.imagen, required this.pantalla, required this.espejo}) {
    _escala = (pantalla.width / imagen.width) > (pantalla.height / imagen.height)
        ? pantalla.width / imagen.width
        : pantalla.height / imagen.height;
    _dx = (pantalla.width - imagen.width * _escala) / 2;
    _dy = (pantalla.height - imagen.height * _escala) / 2;
  }

  final Size imagen;
  final Size pantalla;
  final bool espejo;
  late final double _escala;
  late final double _dx;
  late final double _dy;

  Offset punto(double x, double y) {
    final sx = x * _escala + _dx;
    return Offset(espejo ? pantalla.width - sx : sx, y * _escala + _dy);
  }
}
