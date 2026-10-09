import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constantes.dart';
import '../data/api.dart';
import '../data/modelos.dart';

/// Sesión de administración en el kiosco: vive solo en memoria y se cierra
/// sola tras unos minutos sin actividad (el teléfono queda en un lugar público).
class SesionAdminCtrl extends ChangeNotifier {
  SesionAdminCtrl();

  Api? api;
  SesionAdmin? _sesion;
  Timer? _inactividad;

  SesionAdmin? get sesion => _sesion != null && _sesion!.vigente ? _sesion : null;
  bool get activa => sesion != null;

  Future<SesionAdmin> iniciar(String email, String password) async {
    final s = await api!.login(email.trim(), password);
    _sesion = s;
    tocar();
    notifyListeners();
    return s;
  }

  /// Reinicia el contador de inactividad (llamar en cada interacción).
  void tocar() {
    _inactividad?.cancel();
    _inactividad = Timer(const Duration(minutes: Constantes.minutosSesionAdmin), cerrar);
  }

  void cerrar() {
    _inactividad?.cancel();
    _sesion = null;
    api?.tokenAdmin = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _inactividad?.cancel();
    super.dispose();
  }
}
