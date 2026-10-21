import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'modelos.dart';

class ApiError implements Exception {
  const ApiError(this.status, this.mensaje, {this.campo, this.codigo, this.recurso});

  /// 0 = sin conexión / tiempo agotado.
  final int status;
  final String mensaje;
  final String? campo;
  final String? codigo;

  /// Con LIMITE_PLAN: qué recurso se llenó (sedes, personas, productos).
  final String? recurso;

  bool get sinConexion => status == 0;
  bool get noAutorizado => status == 401;
  bool get dispositivoRevocado => codigo == 'DISPOSITIVO_REVOCADO';
  bool get limitePlan => codigo == 'LIMITE_PLAN';

  /// La persona existe y su contraseña es correcta, pero no puede usar esta
  /// app: se explica en una pantalla propia, no como un error genérico.
  bool get sinAccesoApp => const {
        'CUENTA_DESACTIVADA',
        'EMPRESA_INEXISTENTE',
        'EMPRESA_SUSPENDIDA',
        'APP_NO_HABILITADA',
        'SIN_ACCESO_APP',
      }.contains(codigo);

  @override
  String toString() => mensaje;
}

/// Cliente del backend PHP. El kiosco se identifica con su token de
/// dispositivo; el administrador, con el JWT de su sesión.
class Api {
  Api({required String baseUrl, this.tokenDispositivo}) : baseUrl = normalizarUrl(baseUrl);

  /// Servidor de la plataforma. Se fija al compilar
  /// (`--dart-define=API_URL=https://…`); quien instala desde la tienda no
  /// tiene que escribir ninguna dirección.
  static const urlPorDefecto = String.fromEnvironment('API_URL', defaultValue: 'https://agendaservi.com');

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

  /// [ambos]: la sesión de quien administra Y el token de este teléfono (para
  /// desvincularlo desde el propio teléfono).
  Map<String, String> cabeceras({bool admin = false, bool json = true, bool ambos = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        if ((admin || ambos) && tokenAdmin != null) 'Authorization': 'Bearer $tokenAdmin',
        if ((!admin || ambos) && tokenDispositivo != null) 'X-Dispositivo': tokenDispositivo!,
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
      recurso: mapa['recurso'] as String?,
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

  /// Correo y contraseña de la cuenta de la plataforma: la misma con la que la
  /// persona entra a Inventario. (Las cuentas migradas de la versión anterior
  /// pueden seguir usando su nombre de usuario.)
  Future<SesionAdmin> login(String email, String password) async {
    final j = await _post('/api/auth/login', {'email': email, 'password': password}) as Map<String, dynamic>;
    if (j['superadmin'] == true) {
      throw const ApiError(403, 'Esta cuenta es del equipo de la plataforma: entra desde el panel web.');
    }
    return _sesionDesde(j);
  }

  SesionAdmin _sesionDesde(Map<String, dynamic> j) {
    final u = j['usuario'] as Map<String, dynamic>;
    final sesion = SesionAdmin(
      token: j['token'] as String,
      nombre: u['nombre'] as String,
      email: (u['email'] as String?) ?? '',
      rol: Rol.desdeApi(u['rol'] as String?),
      rolAsistencia: RolAsistencia.desdeApi(u['rol_asistencia'] as String?),
      empresa: EmpresaRef.desdeJson(j['empresa'] as Map<String, dynamic>?),
      expira: DateTime.now().add(Duration(seconds: (j['expira_en'] as num).toInt() - 60)),
    );
    tokenAdmin = sesion.token;
    return sesion;
  }

  // -------------------------------------------------------------------------
  // Cuenta de la empresa (mismo contrato que Inventario: docs/PLATAFORMA.md)
  // -------------------------------------------------------------------------

  /// Crea la empresa con su primera sede y deja la sesión iniciada.
  Future<SesionAdmin> registrarEmpresa({
    required String empresa,
    String? nit,
    String? telefono,
    required String sede,
    required String nombre,
    required String email,
    required String password,
  }) async {
    final j = await _post('/api/cuenta/registro', {
      'empresa': {'nombre': empresa, 'nit': nit, 'telefono': telefono},
      'sede': {'nombre': sede},
      'usuario': {'nombre': nombre, 'email': email, 'password': password},
      'acepta_terminos': true,
    }) as Map<String, dynamic>;
    return _sesionDesde(j);
  }

  /// Envía un código de 6 números al correo (si existe; la respuesta es la misma).
  Future<int> recuperarClave(String email) async {
    final j = await _post('/api/cuenta/recuperar', {'email': email}) as Map<String, dynamic>;
    return ((j['vigencia_minutos'] as num?) ?? 15).toInt();
  }

  Future<void> restablecerClave({required String email, required String codigo, required String password}) =>
      _post('/api/cuenta/restablecer', {'email': email, 'codigo': codigo, 'password': password});

  Future<EmpresaInfo> empresa() async =>
      EmpresaInfo.desdeJson(await _get('/api/cuenta/empresa', admin: true) as Map<String, dynamic>);

  Future<EmpresaInfo> editarEmpresa({String? nombre, String? nit, String? telefono}) async =>
      EmpresaInfo.desdeJson(await _put('/api/cuenta/empresa', {
        'nombre': ?nombre,
        'nit': ?nit,
        'telefono': ?telefono,
      }, admin: true) as Map<String, dynamic>);

  /// El administrador elimina la empresa ([confirmacion] = su nombre); los
  /// demás, solo su cuenta.
  Future<void> eliminarCuenta({required String password, String? confirmacion}) async {
    final r = await _enviar(() => _http.delete(
          uri('/api/cuenta'),
          headers: cabeceras(admin: true),
          body: jsonEncode({'password': password, 'confirmacion': ?confirmacion}),
        ));
    _procesar(r);
  }

  /// Plan y uso actuales (para avisar del límite antes de abrir un formulario).
  Future<PlanEmpresa?> plan() async {
    final j = await _get('/api/auth/yo', admin: true) as Map<String, dynamic>;
    return PlanEmpresa.desdeJson(j['plan'] as Map<String, dynamic>?);
  }

  // -------------------------------------------------------------------------
  // Administración
  // -------------------------------------------------------------------------

  /// Sedes visibles. [todas] incluye las inactivas (solo para el administrador).
  Future<List<Sede>> sedes({bool todas = false}) async {
    final j = await _get('/api/sedes', query: {if (todas) 'todas': '1'}, admin: true) as Map<String, dynamic>;
    return (j['sedes'] as List).map((s) => Sede.desdeJson(s as Map<String, dynamic>)).toList();
  }

  /// Crea o edita una sede (las mismas de Inventario). El cupo lo exige el servidor.
  Future<Sede> guardarSede({
    int? id,
    required String nombre,
    String? codigo,
    String? direccion,
    String? telefono,
    bool? activo,
  }) async {
    final cuerpo = {
      'nombre': nombre,
      if (codigo != null && codigo.isNotEmpty) 'codigo': codigo,
      'direccion': direccion,
      'telefono': telefono,
      'activo': ?activo,
    };
    final j = (id == null
        ? await _post('/api/sedes', cuerpo, admin: true)
        : await _put('/api/sedes/$id', cuerpo, admin: true)) as Map<String, dynamic>;
    return Sede.desdeJson(j['sede'] as Map<String, dynamic>);
  }

  /// Convierte ESTE teléfono en punto de marcación de una sede. [instalacion]
  /// lo identifica: volver a vincularlo reutiliza su registro (y su código) en
  /// vez de duplicarlo. Sin [nombre], el servidor pone «Sede · Teléfono N».
  Future<DispositivoRegistrado> registrarDispositivo(int sedeId, {required String instalacion, String? nombre}) async {
    final j = await _post(
      '/api/dispositivos',
      {'sede_id': sedeId, 'instalacion_uuid': instalacion, if (nombre != null && nombre.isNotEmpty) 'nombre': nombre},
      admin: true,
    ) as Map<String, dynamic>;
    return DispositivoRegistrado(
      id: (j['id'] as num).toInt(),
      nombre: j['nombre'] as String,
      token: j['token'] as String,
      sede: Sede.desdeJson(j['sede'] as Map<String, dynamic>),
      codigo: j['codigo'] as String?,
    );
  }

  /// Presente empieza a usar esta sede. No se puede deshacer.
  Future<Sede> elegirSede(int id) async {
    final j = await _post('/api/sedes/$id/elegir', const {}, admin: true) as Map<String, dynamic>;
    return Sede.desdeJson(j['sede'] as Map<String, dynamic>);
  }

  /// Pausa o reactiva a una persona (reactivar exige cupo: LIMITE_PLAN).
  Future<Empleado> pausarEmpleado(int id, {required bool pausada}) async {
    final j = await _post('/api/empleados/$id/pausa', {'pausada': pausada}, admin: true) as Map<String, dynamic>;
    return Empleado.desdeJson(j['empleado'] as Map<String, dynamic>);
  }

  Future<Usuario> pausarUsuario(int id, {required bool pausada}) async {
    final j = await _post('/api/usuarios/$id/pausa', {'pausada': pausada}, admin: true) as Map<String, dynamic>;
    return Usuario.desdeJson(j['usuario'] as Map<String, dynamic>);
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

  /// [consentimiento]: la persona autorizó el tratamiento de sus datos
  /// biométricos (Ley 1581). El servidor guarda quién y cuándo lo registró.
  Future<({Empleado empleado, bool reactivado})> crearEmpleado({
    required int sedeId,
    required String documento,
    required String nombre,
    String? cargo,
    bool consentimiento = false,
  }) async {
    final j = await _post(
      '/api/empleados',
      {
        'sede_id': sedeId,
        'documento': documento,
        'nombre': nombre,
        'cargo': cargo,
        if (consentimiento) 'consentimiento': true,
      },
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

  /// Reemplaza las fotos del rostro del empleado (1 a 3 JPEG). Sin la
  /// autorización registrada el servidor no guarda datos biométricos: se envía
  /// en la misma petición (solo se llega aquí después de que la confirmaron).
  Future<List<FotoRef>> subirFotos(int empleadoId, List<Uint8List> jpegs) async {
    final peticion = http.MultipartRequest('POST', uri('/api/empleados/$empleadoId/fotos'))
      ..headers.addAll(cabeceras(admin: true, json: false))
      ..fields['consentimiento'] = '1';
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

  /// Cuentas de la empresa, con las apps habilitadas y el plan (para el formulario).
  Future<EquipoEmpresa> usuarios() async {
    final j = await _get('/api/usuarios', admin: true) as Map<String, dynamic>;
    return EquipoEmpresa(
      usuarios: (j['usuarios'] as List).map((u) => Usuario.desdeJson(u as Map<String, dynamic>)).toList(),
      aplicativos: ((j['aplicativos'] as List?) ?? const []).cast<String>(),
      plan: PlanEmpresa.desdeJson(j['plan'] as Map<String, dynamic>?),
    );
  }

  /// Crea o edita una cuenta. Los roles se envían siempre juntos (uno por app;
  /// null = sin acceso a esa app) con sus sedes, porque se validan juntos.
  Future<Usuario> guardarUsuario({
    int? id,
    required String nombre,
    String? email,
    String? password,
    RolAsistencia? rolAsistencia,
    RolInventario? rolInventario,
    required List<int> sedes,
    String? documento,
    bool? activo,
  }) async {
    final cuerpo = {
      'nombre': nombre,
      'email': ?email,
      if (password != null && password.isNotEmpty) 'password': password,
      'rol_asistencia': rolAsistencia?.api,
      'rol_inventario': rolInventario?.api,
      'sedes': sedes,
      'documento': documento,
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

  Future<void> renombrarKiosco(int id, String nombre) => _put('/api/dispositivos/$id', {'nombre': nombre}, admin: true);

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

  /// Solo con la sesión de un administrador, gerente o talento humano: quien
  /// pasa por el teléfono (o el operario) no puede quitarlo.
  Future<void> kioscoDesvincular() async =>
      _procesar(await _enviar(() => _http.delete(uri('/api/kiosco/yo'), headers: cabeceras(ambos: true))));

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
