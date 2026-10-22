import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constantes.dart';
import '../data/api.dart';
import '../data/modelos.dart';

/// Sesión de administración (administrador, gerente o talento humano).
///
/// Depende del teléfono:
///  - **Teléfono personal** (no es punto de marcación): la sesión se
///    **recuerda**, como en Ventario. Se guarda en el almacenamiento seguro,
///    no se cierra al salir de la app ni sin internet, y se renueva sola cada
///    vez que hay conexión. Solo termina con «Cerrar sesión» o si el servidor
///    la rechaza (cuenta inactivada, vencida tras 30 días sin conexión).
///  - **Teléfono de marcación** (vinculado a una sede, en un lugar público):
///    vive solo en memoria y se cierra tras unos minutos sin uso.
class SesionAdminCtrl extends ChangeNotifier {
  SesionAdminCtrl({FlutterSecureStorage? almacen}) : _almacen = almacen ?? const FlutterSecureStorage();

  final FlutterSecureStorage _almacen;
  static const _clave = 'sesion_admin';
  static const _claveSedes = 'sedes_panel';

  Api? api;
  SesionAdmin? _sesion;
  Timer? _inactividad;
  bool _recordada = true;

  SesionAdmin? get sesion => _sesion != null && _sesion!.vigente ? _sesion : null;
  bool get activa => sesion != null;

  /// true en el teléfono personal; false en un teléfono de marcación.
  bool get recordada => _recordada;
  set recordada(bool valor) {
    if (valor == _recordada) return;
    _recordada = valor;
    if (valor) {
      _inactividad?.cancel();
      final s = _sesion;
      if (s != null) unawaited(_guardar(s));
    } else {
      // Pasa a ser un teléfono público: no queda ninguna sesión guardada.
      unawaited(_olvidar());
      if (_sesion != null) tocar();
    }
  }

  /// Recupera la sesión guardada (sin red). Llamar al abrir la app.
  Future<void> restaurar() async {
    if (!_recordada) return;
    try {
      final crudo = await _almacen.read(key: _clave);
      final s = crudo == null ? null : SesionAdmin.desdeJson(jsonDecode(crudo) as Map<String, dynamic>);
      if (s == null || !s.vigente) {
        if (crudo != null) await _olvidar();
        return;
      }
      _sesion = s;
      api?.tokenAdmin = s.token;
      notifyListeners();
    } catch (_) {
      // Almacenamiento ilegible: se pide entrar de nuevo.
    }
  }

  /// Renueva la sesión recordada si hay internet. Sin red no pasa nada (sigue
  /// la guardada); si el servidor la rechaza (401), se cierra.
  Future<void> renovar() async {
    if (!_recordada || _sesion == null || api == null) return;
    try {
      final s = await api!.renovarSesion();
      _sesion = s;
      await _guardar(s);
      notifyListeners();
    } on ApiError catch (e) {
      if (e.noAutorizado) cerrar();
    } catch (_) {}
  }

  Future<SesionAdmin> iniciar(String email, String password) async {
    final s = await api!.login(email.trim(), password, recordar: _recordada);
    _abrir(s);
    return s;
  }

  /// Sesión que ya abrió otra pantalla con la misma API (p. ej. el registro
  /// de una empresa nueva).
  void adoptar(SesionAdmin s) => _abrir(s);

  void _abrir(SesionAdmin s) {
    _sesion = s;
    api?.tokenAdmin = s.token;
    if (_recordada) {
      unawaited(_guardar(s));
    } else {
      tocar();
    }
    notifyListeners();
  }

  /// Reinicia el contador de inactividad (solo en un teléfono de marcación).
  void tocar() {
    if (_recordada) return;
    _inactividad?.cancel();
    _inactividad = Timer(const Duration(minutes: Constantes.minutosSesionAdmin), cerrar);
  }

  void cerrar() {
    _inactividad?.cancel();
    final habia = _sesion != null;
    _sesion = null;
    api?.tokenAdmin = null;
    unawaited(_olvidar());
    if (habia) notifyListeners();
  }

  /// Sedes del panel, para abrirlo aunque no haya internet.
  Future<void> guardarSedes(List<Sede> sedes) async {
    if (!_recordada) return;
    try {
      await _almacen.write(key: _claveSedes, value: jsonEncode([for (final s in sedes) s.aJson()]));
    } catch (_) {}
  }

  Future<List<Sede>> sedesGuardadas() async {
    try {
      final crudo = await _almacen.read(key: _claveSedes);
      if (crudo == null) return const [];
      return [for (final s in jsonDecode(crudo) as List) Sede.desdeJson(s as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _guardar(SesionAdmin s) async {
    try {
      await _almacen.write(key: _clave, value: jsonEncode(s.aJson()));
    } catch (_) {}
  }

  Future<void> _olvidar() async {
    try {
      await _almacen.delete(key: _clave);
      await _almacen.delete(key: _claveSedes);
    } catch (_) {}
  }

  @override
  void dispose() {
    _inactividad?.cancel();
    super.dispose();
  }
}
