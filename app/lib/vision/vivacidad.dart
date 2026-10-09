import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Prueba de vida por parpadeo: ojos abiertos → cerrados → abiertos.
/// Impide marcar con una foto impresa o mostrada en otra pantalla.
class DetectorParpadeo {
  static const _abiertos = 0.70;
  static const _cerrados = 0.25;

  bool _vioAbiertos = false;
  bool _vioCerrados = false;
  bool _parpadeo = false;

  bool get completado => _parpadeo;

  void reiniciar() {
    _vioAbiertos = false;
    _vioCerrados = false;
    _parpadeo = false;
  }

  void procesar(Face rostro) {
    if (_parpadeo) return;
    final izq = rostro.leftEyeOpenProbability;
    final der = rostro.rightEyeOpenProbability;
    if (izq == null || der == null) return;
    final apertura = (izq + der) / 2;
    if (apertura >= _abiertos) {
      if (_vioCerrados) {
        _parpadeo = true;
      } else {
        _vioAbiertos = true;
      }
    } else if (apertura <= _cerrados && _vioAbiertos) {
      _vioCerrados = true;
    }
  }
}
