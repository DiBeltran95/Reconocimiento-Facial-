import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/modelos.dart';

/// Vínculo del teléfono con el servidor. El token vive en el almacenamiento
/// seguro del sistema (Keystore / Keychain), nunca en texto plano.
class ConfigDispositivo {
  const ConfigDispositivo({required this.url, required this.token, required this.sede, required this.nombre});

  final String url;
  final String token;
  final Sede sede;
  final String nombre;

  static const _almacen = FlutterSecureStorage();
  static const _clave = 'config_dispositivo';

  ConfigDispositivo conSede(Sede nueva) => ConfigDispositivo(url: url, token: token, sede: nueva, nombre: nombre);

  static Future<ConfigDispositivo?> cargar() async {
    try {
      final crudo = await _almacen.read(key: _clave);
      if (crudo == null) return null;
      final j = jsonDecode(crudo) as Map<String, dynamic>;
      return ConfigDispositivo(
        url: j['url'] as String,
        token: j['token'] as String,
        sede: Sede.desdeJson(j['sede'] as Map<String, dynamic>),
        nombre: j['nombre'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> guardar() => _almacen.write(
        key: _clave,
        value: jsonEncode({'url': url, 'token': token, 'sede': sede.aJson(), 'nombre': nombre}),
      );

  static Future<void> borrar() => _almacen.delete(key: _clave);

  /// Última URL usada (para no reescribirla al volver a vincular).
  static Future<String?> ultimaUrl() => _almacen.read(key: 'ultima_url');
  static Future<void> recordarUrl(String url) => _almacen.write(key: 'ultima_url', value: url);
}
