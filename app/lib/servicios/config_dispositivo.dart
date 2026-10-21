import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/modelos.dart';

/// Vínculo del teléfono con el servidor. El token vive en el almacenamiento
/// seguro del sistema (Keystore / Keychain), nunca en texto plano.
class ConfigDispositivo {
  const ConfigDispositivo({
    required this.url,
    required this.token,
    required this.sede,
    required this.nombre,
    this.codigo,
  });

  final String url;
  final String token;
  final Sede sede;
  final String nombre;

  /// Código corto que se ve en pantalla y en «Teléfonos de marcación».
  final String? codigo;

  static const _almacen = FlutterSecureStorage();
  static const _clave = 'config_dispositivo';
  static const _claveInstalacion = 'instalacion_uuid';

  ConfigDispositivo conSede(Sede nueva) =>
      ConfigDispositivo(url: url, token: token, sede: nueva, nombre: nombre, codigo: codigo);

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
        codigo: j['codigo'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> guardar() => _almacen.write(
        key: _clave,
        value: jsonEncode({'url': url, 'token': token, 'sede': sede.aJson(), 'nombre': nombre, 'codigo': codigo}),
      );

  static Future<void> borrar() => _almacen.delete(key: _clave);

  /// Última URL usada (para no reescribirla al volver a vincular).
  static Future<String?> ultimaUrl() => _almacen.read(key: 'ultima_url');
  static Future<void> recordarUrl(String url) => _almacen.write(key: 'ultima_url', value: url);

  /// Identidad de ESTA instalación (UUID v4). Muchos teléfonos del mismo
  /// modelo usan la misma cuenta Operario: el servidor los distingue por esto.
  /// Sobrevive a desvincular, así un teléfono que se vuelve a vincular
  /// conserva su registro y su código.
  static Future<String> instalacion() async {
    final previa = await _almacen.read(key: _claveInstalacion);
    if (previa != null && previa.length == 36) return previa;
    final nueva = uuidV4();
    await _almacen.write(key: _claveInstalacion, value: nueva);
    return nueva;
  }

  static String uuidV4([Random? azar]) {
    final r = azar ?? Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
