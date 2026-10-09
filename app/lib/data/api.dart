import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'modelos.dart';

class ApiError implements Exception {
  const ApiError(this.status, this.mensaje, {this.campo, this.codigo});

  /// 0 = sin conexión / tiempo agotado.
  final int status;
  final String mensaje;
  final String? campo;
  final String? codigo;

  bool get sinConexion => status == 0;
  bool get noAutorizado => status == 401;
  bool get dispositivoRevocado => codigo == 'DISPOSITIVO_REVOCADO';

  @override
  String toString() => mensaje;
}

/// Cliente del backend PHP. El kiosco se identifica con su token de
/// dispositivo; el administrador, con el JWT de su sesión.
class Api {
  Api({required String baseUrl, this.tokenDispositivo}) : baseUrl = normalizarUrl(baseUrl);

  String baseUrl;
  String? tokenDispositivo;
  String? tokenAdmin;

  final http.Client _http = http.Client();
  static const _timeout = Duration(seconds: 20);

  static String normalizarUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Uri uri(String ruta, [Map<String, String>? query]) {
    final base = Uri.parse('$baseUrl$ruta');
    return query == null || query.isEmpty ? base : base.replace(queryParameters: query);
  }

  Map<String, String> cabeceras({bool admin = false, bool json = true}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        if (admin && tokenAdmin != null) 'Authorization': 'Bearer $tokenAdmin',
        if (!admin && tokenDispositivo != null) 'X-Dispositivo': tokenDispositivo!,
      };

  Future<http.Response> _enviar(Future<http.Response> Function() peticion) async {
    try {
      return await peticion().timeout(_timeout);
    } on TimeoutException {
      throw const ApiError(0, 'El servidor tardó demasiado en responder');
    } on SocketException {
      throw const ApiError(0, 'Sin conexión a internet');
    } on HandshakeException {
      throw const ApiError(0, 'No se pudo establecer una conexión segura');
    } on http.ClientException {
      throw const ApiError(0, 'Sin conexión con el servidor');
    }
  }

  dynamic _procesar(http.Response r) {
    if (r.statusCode == 204 || r.statusCode == 304) return null;
    dynamic cuerpo;
    try {
      cuerpo = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      cuerpo = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return cuerpo;
    final mapa = cuerpo is Map<String, dynamic> ? cuerpo : const <String, dynamic>{};
    throw ApiError(
      r.statusCode,
      (mapa['error'] as String?) ?? 'Error del servidor (${r.statusCode})',
      campo: mapa['campo'] as String?,
      codigo: mapa['codigo'] as String?,
    );
  }

  Future<dynamic> _get(String ruta, {Map<String, String>? query, bool admin = false}) async =>
      _procesar(await _enviar(() => _http.get(uri(ruta, query), headers: cabeceras(admin: admin))));

  Future<dynamic> _post(String ruta, Object cuerpo, {bool admin = false}) async => _procesar(await _enviar(
      () => _http.post(uri(ruta), headers: cabeceras(admin: admin), body: jsonEncode(cuerpo))));

  Future<dynamic> _put(String ruta, Object cuerpo, {bool admin = false}) async => _procesar(await _enviar(
      () => _http.put(uri(ruta), headers: cabeceras(admin: admin), body: jsonEncode(cuerpo))));

  Future<dynamic> _delete(String ruta, {bool admin = false}) async =>
      _procesar(await _enviar(() => _http.delete(uri(ruta), headers: cabeceras(admin: admin))));

  // -------------------------------------------------------------------------
  // Público
  // -------------------------------------------------------------------------

  /// Devuelve la hora del servidor y el desfase del reloj local (servidor − local).
  Future<({DateTime horaServidor, Duration desfase, String negocio})> salud() async {
    final antes = DateTime.now();
    final j = await _get('/api/salud') as Map<String, dynamic>;
    final despues = DateTime.now();
    final servidor = DateTime.parse(j['hora_servidor'] as String);
    // Se compara contra el punto medio del viaje de ida y vuelta.
    final medio = antes.add(despues.difference(antes) ~/ 2);
    return (
      horaServidor: servidor,
      desfase: servidor.difference(medio),
      negocio: (j['negocio'] as String?) ?? '',
    );
  }

  /// [usuario] es el nombre de usuario de la app o el correo de un
  /// administrador del sistema de inventarios.
  Future<SesionAdmin> login(String usuario, String password) async {
    final j = await _post('/api/auth/login', {'usuario': usuario, 'password': password}) as Map<String, dynamic>;
    final u = j['usuario'] as Map<String, dynamic>;
    final sesion = SesionAdmin(
      token: j['token'] as String,
      nombre: u['nombre'] as String,
      rol: Rol.desdeApi(u['rol'] as String),
      expira: DateTime.now().add(Duration(seconds: (j['expira_en'] as num).toInt() - 60)),
    );
    tokenAdmin = sesion.token;
    return sesion;
  }

  // -------------------------------------------------------------------------
  // Administración
  // -------------------------------------------------------------------------

  Future<List<Sede>> sedes() async {
    final j = await _get('/api/sedes', admin: true) as Map<String, dynamic>;
    return (j['sedes'] as List).map((s) => Sede.desdeJson(s as Map<String, dynamic>)).toList();
  }

  Future<DispositivoRegistrado> registrarDispositivo(int sedeId, String nombre) async {
    final j = await _post('/api/dispositivos', {'sede_id': sedeId, 'nombre': nombre}, admin: true)
        as Map<String, dynamic>;
    return DispositivoRegistrado(
      id: (j['id'] as num).toInt(),
      nombre: j['nombre'] as String,
      token: j['token'] as String,
      sede: Sede.desdeJson(j['sede'] as Map<String, dynamic>),
    );
  }

  Future<List<Empleado>> empleados({int? sedeId}) async {
    final j = await _get('/api/empleados', query: {if (sedeId != null) 'sede_id': '$sedeId'}, admin: true)
        as Map<String, dynamic>;
    return (j['empleados'] as List).map((e) => Empleado.desdeJson(e as Map<String, dynamic>)).toList();
  }

  Future<Empleado> empleado(int id) async {
    final j = await _get('/api/empleados/$id', admin: true) as Map<String, dynamic>;
    return Empleado.desdeJson(j['empleado'] as Map<String, dynamic>);
  }

  Future<({Empleado empleado, bool reactivado})> crearEmpleado({
    required int sedeId,
    required String documento,
    required String nombre,
    String? cargo,
  }) async {
    final j = await _post(
      '/api/empleados',
      {'sede_id': sedeId, 'documento': documento, 'nombre': nombre, 'cargo': cargo},
      admin: true,
    ) as Map<String, dynamic>;
    return (
      empleado: Empleado.desdeJson(j['empleado'] as Map<String, dynamic>),
      reactivado: j['reactivado'] as bool? ?? false,
    );
  }

  Future<Empleado> actualizarEmpleado(
    int id, {
    required int sedeId,
    required String documento,
    required String nombre,
    String? cargo,
  }) async {
    final j = await _put(
      '/api/empleados/$id',
      {'sede_id': sedeId, 'documento': documento, 'nombre': nombre, 'cargo': cargo},
      admin: true,
    ) as Map<String, dynamic>;
    return Empleado.desdeJson(j['empleado'] as Map<String, dynamic>);
  }

  Future<void> desactivarEmpleado(int id) => _delete('/api/empleados/$id', admin: true);

  /// Reemplaza las fotos del rostro del empleado (1 a 3 JPEG).
  Future<List<FotoRef>> subirFotos(int empleadoId, List<Uint8List> jpegs) async {
    final peticion = http.MultipartRequest('POST', uri('/api/empleados/$empleadoId/fotos'))
      ..headers.addAll(cabeceras(admin: true, json: false));
    for (var i = 0; i < jpegs.length; i++) {
      peticion.files.add(http.MultipartFile.fromBytes('fotos[]', jpegs[i], filename: 'rostro_${i + 1}.jpg'));
    }
    final r = await _enviar(() async => http.Response.fromStream(await _http.send(peticion)));
    final j = _procesar(r) as Map<String, dynamic>;
    return (j['fotos'] as List).map((f) => FotoRef.desdeJson(f as Map<String, dynamic>)).toList();
  }

  Future<ReporteDia> reporteDia({required int sedeId, required String fecha}) async {
    final j = await _get('/api/reportes/dia', query: {'sede_id': '$sedeId', 'fecha': fecha}, admin: true)
        as Map<String, dynamic>;
    return ReporteDia.desdeJson(j);
  }

  // ---------------------------------------------------------------- Horarios

  Future<List<Horario>> horarios() async {
    final j = await _get('/api/horarios', admin: true) as Map<String, dynamic>;
    return (j['horarios'] as List).map((h) => Horario.desdeJson(h as Map<String, dynamic>)).toList();
  }

  Future<Horario> guardarHorario({
    int? id,
    required String nombre,
    required String bloques,
    required int dias,
    required int toleranciaMin,
  }) async {
    final cuerpo = {'nombre': nombre, 'bloques': bloques, 'dias': dias, 'tolerancia_min': toleranciaMin};
    final j = (id == null
        ? await _post('/api/horarios', cuerpo, admin: true)
        : await _put('/api/horarios/$id', cuerpo, admin: true)) as Map<String, dynamic>;
    return Horario.desdeJson(j['horario'] as Map<String, dynamic>);
  }

  Future<void> archivarHorario(int id) => _delete('/api/horarios/$id', admin: true);

  Future<PlanEmpleado> planEmpleado(int empleadoId, {int semanas = 8}) async {
    final j = await _get('/api/empleados/$empleadoId/horario', query: {'semanas': '$semanas'}, admin: true)
        as Map<String, dynamic>;
    return PlanEmpleado.desdeJson(j);
  }

  static String _fecha(DateTime f) =>
      '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

  /// Misma rotación para uno o varios empleados desde la semana de [desde].
  Future<void> asignarRotacion({required List<int> empleados, required List<int> secuencia, required DateTime desde}) =>
      _post('/api/horarios/asignar', {'empleados': empleados, 'secuencia': secuencia, 'desde': _fecha(desde)}, admin: true);

  /// Cambia el turno de una sola semana. [horarioId] null = sin turno; [quitar] vuelve a la rotación.
  Future<void> ajustarSemana(int empleadoId, DateTime semana, {int? horarioId, bool quitar = false}) => _put(
        '/api/empleados/$empleadoId/semana',
        {'semana': _fecha(semana), 'horario_id': horarioId, 'quitar': quitar},
        admin: true,
      );

  Future<ReporteCumplimiento> reporteCumplimiento({required int sedeId, required DateTime desde, required DateTime hasta}) async {
    final j = await _get(
      '/api/reportes/cumplimiento',
      query: {'sede_id': '$sedeId', 'desde': _fecha(desde), 'hasta': _fecha(hasta)},
      admin: true,
    ) as Map<String, dynamic>;
    return ReporteCumplimiento.desdeJson(j);
  }

  // ---------------------------------------------------------------- Usuarios y kioscos

  Future<List<Usuario>> usuarios() async {
    final j = await _get('/api/usuarios', admin: true) as Map<String, dynamic>;
    return (j['usuarios'] as List).map((u) => Usuario.desdeJson(u as Map<String, dynamic>)).toList();
  }

  Future<Usuario> guardarUsuario({
    int? id,
    String? nombre,
    String? usuario,
    String? password,
    Rol? rol,
    bool? activo,
  }) async {
    final cuerpo = {
      'nombre': ?nombre,
      'usuario': ?usuario,
      if (password != null && password.isNotEmpty) 'password': password,
      'rol': ?rol?.api,
      'activo': ?activo,
    };
    final j = (id == null
        ? await _post('/api/usuarios', cuerpo, admin: true)
        : await _put('/api/usuarios/$id', cuerpo, admin: true)) as Map<String, dynamic>;
    return Usuario.desdeJson(j['usuario'] as Map<String, dynamic>);
  }

  Future<List<KioscoRegistrado>> kioscos() async {
    final j = await _get('/api/dispositivos', admin: true) as Map<String, dynamic>;
    return (j['dispositivos'] as List).map((d) => KioscoRegistrado.desdeJson(d as Map<String, dynamic>)).toList();
  }

  Future<void> revocarKiosco(int id) => _delete('/api/dispositivos/$id', admin: true);

  /// URL + cabeceras para mostrar una foto con Image.network.
  ({String url, Map<String, String> cabeceras}) foto(int empleadoId, int n, int v, {bool admin = true}) => (
        url: uri('/api/empleados/$empleadoId/fotos/$n', {'v': '$v'}).toString(),
        cabeceras: cabeceras(admin: admin, json: false),
      );

  // -------------------------------------------------------------------------
  // Kiosco
  // -------------------------------------------------------------------------

  Future<Sede> kioscoYo() async {
    final j = await _get('/api/kiosco/yo') as Map<String, dynamic>;
    return Sede.desdeJson(j['sede'] as Map<String, dynamic>);
  }

  Future<void> kioscoDesvincular() => _delete('/api/kiosco/yo');

  /// Plantilla de empleados de la sede. Devuelve null si nada cambió (304).
  Future<PlantillaSede?> kioscoEmpleados({String? etag}) async {
    final r = await _enviar(() => _http.get(
          uri('/api/kiosco/empleados'),
          headers: {...cabeceras(json: false), 'If-None-Match': ?etag},
        ));
    final j = _procesar(r);
    if (j == null) return null;
    final mapa = j as Map<String, dynamic>;
    return PlantillaSede(
      sede: Sede.desdeJson(mapa['sede'] as Map<String, dynamic>),
      empleados: (mapa['empleados'] as List)
          .map((e) => EmpleadoRemoto.desdeJson(e as Map<String, dynamic>))
          .toList(),
      etag: r.headers['etag'],
      fecha: mapa['fecha'] as String?,
    );
  }

  Future<List<Marcacion>> kioscoMarcacionesHoy() async {
    final j = await _get('/api/kiosco/marcaciones/hoy') as Map<String, dynamic>;
    return (j['marcaciones'] as List).map((m) {
      final mapa = m as Map<String, dynamic>;
      return Marcacion(
        empleadoId: (mapa['empleado_id'] as num).toInt(),
        tipo: TipoMarcacion.desdeApi(mapa['tipo'] as String),
        hora: DateTime.parse(mapa['hora'] as String),
        enviada: true,
      );
    }).toList();
  }

  Future<List<ResultadoEnvio>> kioscoEnviarMarcaciones(List<Marcacion> lote) async {
    final j = await _post('/api/kiosco/marcaciones', {'marcaciones': lote.map((m) => m.aJsonApi()).toList()})
        as Map<String, dynamic>;
    return (j['resultados'] as List).map((r) {
      final mapa = r as Map<String, dynamic>;
      return ResultadoEnvio((mapa['i'] as num).toInt(), mapa['estado'] as String, mapa['motivo'] as String?);
    }).toList();
  }

  Future<Uint8List> descargarFoto(int empleadoId, int n) async {
    final r = await _enviar(() => _http.get(uri('/api/empleados/$empleadoId/fotos/$n'), headers: cabeceras(json: false)));
    if (r.statusCode != 200) _procesar(r);
    return r.bodyBytes;
  }

  void cerrar() => _http.close();
}
