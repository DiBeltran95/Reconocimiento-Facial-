import 'dart:typed_data';

enum TipoMarcacion {
  entrada('ENTRADA', 'Entrada'),
  salida('SALIDA', 'Salida');

  const TipoMarcacion(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  TipoMarcacion get opuesto => this == entrada ? salida : entrada;

  static TipoMarcacion desdeApi(String valor) => valor == 'SALIDA' ? salida : entrada;
}

class Sede {
  const Sede({
    required this.id,
    required this.nombre,
    required this.codigo,
    this.direccion,
    this.telefono,
    this.esPrincipal = false,
    this.activo = true,
    this.elegida = true,
    this.elegidaVentario,
  });

  final int id;
  final String nombre;
  final String codigo;
  final String? direccion;
  final String? telefono;
  final bool esPrincipal;
  final bool activo;

  /// ¿Presente trabaja en esta sede? Las sedes son de la empresa (compartidas
  /// con Ventario) y cada app usa solo las que se eligen para ella.
  final bool elegida;

  /// ¿La usa Ventario? Solo viene en el listado completo del administrador.
  final bool? elegidaVentario;

  factory Sede.desdeJson(Map<String, dynamic> j) => Sede(
        id: (j['id'] as num).toInt(),
        nombre: j['nombre'] as String,
        codigo: (j['codigo'] ?? '') as String,
        direccion: j['direccion'] as String?,
        telefono: j['telefono'] as String?,
        esPrincipal: j['es_principal'] as bool? ?? false,
        activo: j['activo'] as bool? ?? true,
        elegida: j['elegida'] as bool? ?? true,
        elegidaVentario: j['elegida_ventario'] as bool?,
      );

  Map<String, dynamic> aJson() => {'id': id, 'nombre': nombre, 'codigo': codigo, 'direccion': direccion};
}

/// Versión de una foto en el servidor: n = posición (1..3), v = versión.
class FotoRef {
  const FotoRef(this.n, this.v);
  final int n;
  final int v;

  factory FotoRef.desdeJson(Map<String, dynamic> j) => FotoRef((j['n'] as num).toInt(), (j['v'] as num).toInt());

  @override
  String toString() => '$n:$v';
}

/// Empleado tal como lo guarda el teléfono para reconocerlo sin conexión.
class EmpleadoLocal {
  const EmpleadoLocal({
    required this.id,
    required this.documento,
    required this.nombre,
    this.cargo,
    this.rutaFoto,
    this.vectores = 0,
    this.turnoHoy,
    this.turnoFecha,
    this.tolerancia = 10,
  });

  final int id;
  final String documento;
  final String nombre;
  final String? cargo;

  /// Primera foto en disco (para mostrar la cara al confirmar).
  final String? rutaFoto;

  /// Cuántos vectores faciales tiene listos (0 = no se puede reconocer).
  final int vectores;

  /// Bloques del turno de [turnoFecha] ('08:30-12:00,14:00-18:00') y su tolerancia.
  final String? turnoHoy;
  final String? turnoFecha;
  final int tolerancia;

  bool get reconocible => vectores > 0;

  /// Turno vigente solo si corresponde al día de hoy en el teléfono.
  List<Bloque>? turnoDe(DateTime dia) {
    final f = '${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
    if (turnoHoy == null || turnoFecha != f) return null;
    return bloquesDesdeTexto(turnoHoy!);
  }
}

/// Empleado de la API de administración.
class Empleado {
  const Empleado({
    required this.id,
    required this.sedeId,
    required this.documento,
    required this.nombre,
    this.cargo,
    this.activo = true,
    this.fotos = const [],
    this.turnoSemana,
    this.consentimientoEn,
    this.cuentaEmail,
    this.cuentaActiva = true,
    this.enPausa = false,
    this.telefono,
    this.email,
    this.cuentaRolAsistencia,
    this.cuentaRolInventario,
  });

  final int id;
  final int sedeId;
  final String documento;
  final String nombre;
  final String? cargo;
  final bool activo;
  final List<FotoRef> fotos;

  /// Turno que le corresponde esta semana (null = sin horario asignado).
  final TurnoCorto? turnoSemana;

  /// Cuándo se registró su autorización de datos biométricos (Ley 1581).
  final DateTime? consentimientoEn;

  /// Cuenta ligada (entra también a las apps con ese correo), o null.
  final String? cuentaEmail;
  final bool cuentaActiva;

  /// En pausa porque el plan de Presente no alcanza para todos: no marca ni
  /// cuenta en el cupo hasta que el administrador la reactive.
  final bool enPausa;
  final String? telefono;
  final String? email;

  /// Accesos de su cuenta: rol en Presente y en Ventario (null = no entra).
  final RolAsistencia? cuentaRolAsistencia;
  final String? cuentaRolInventario;

  bool get tieneRostro => fotos.isNotEmpty;
  bool get tieneConsentimiento => consentimientoEn != null;

  factory Empleado.desdeJson(Map<String, dynamic> j) {
    final cuenta = j['cuenta'] as Map<String, dynamic>?;
    return Empleado(
      id: (j['id'] as num).toInt(),
      sedeId: (j['sede_id'] as num).toInt(),
      documento: j['documento'] as String,
      nombre: j['nombre'] as String,
      cargo: j['cargo'] as String?,
      activo: j['activo'] as bool? ?? true,
      fotos: ((j['fotos'] as List?) ?? const [])
          .map((f) => FotoRef.desdeJson(f as Map<String, dynamic>))
          .toList(),
      turnoSemana: j['turno_semana'] == null ? null : TurnoCorto.desdeJson(j['turno_semana'] as Map<String, dynamic>),
      consentimientoEn: j['consentimiento_en'] == null ? null : DateTime.parse(j['consentimiento_en'] as String),
      cuentaEmail: cuenta?['email'] as String?,
      cuentaActiva: cuenta?['activa'] as bool? ?? true,
      enPausa: j['en_pausa'] as bool? ?? false,
      telefono: j['telefono'] as String?,
      email: j['email'] as String?,
      cuentaRolAsistencia: RolAsistencia.desdeApi(cuenta?['rol_asistencia'] as String?),
      cuentaRolInventario: cuenta?['rol_inventario'] as String?,
    );
  }
}

/// Marcación guardada en el teléfono (pendiente o ya enviada).
class Marcacion {
  const Marcacion({
    this.idLocal,
    required this.empleadoId,
    required this.tipo,
    required this.hora,
    this.enviada = false,
  });

  final int? idLocal;
  final int empleadoId;
  final TipoMarcacion tipo;

  /// Hora del dispositivo, en UTC y truncada a segundos (así la llave única
  /// del servidor coincide exactamente al reenviar).
  final DateTime hora;
  final bool enviada;

  Map<String, dynamic> aJsonApi() => {
        'empleado_id': empleadoId,
        'tipo': tipo.api,
        'hora': hora.toUtc().toIso8601String(),
      };
}

class ResultadoEnvio {
  const ResultadoEnvio(this.indice, this.estado, this.motivo);
  final int indice;
  final String estado; // ok | duplicada | rechazada
  final String? motivo;

  bool get aceptada => estado == 'ok' || estado == 'duplicada';
}

/// Respuesta de sincronización del kiosco.
class PlantillaSede {
  const PlantillaSede({required this.sede, required this.empleados, this.etag, this.fecha});
  final Sede sede;
  final List<EmpleadoRemoto> empleados;
  final String? etag;

  /// Día (Y-m-d, hora del servidor) al que corresponden los turnos.
  final String? fecha;
}

class EmpleadoRemoto {
  const EmpleadoRemoto({
    required this.id,
    required this.documento,
    required this.nombre,
    this.cargo,
    required this.fotos,
    this.turnoHoy,
    this.tolerancia = 10,
  });

  final int id;
  final String documento;
  final String nombre;
  final String? cargo;
  final List<FotoRef> fotos;
  final String? turnoHoy;
  final int tolerancia;

  /// Firma de versión de las fotos: si cambia, hay que reprocesar el rostro.
  String get firmaFotos => fotos.map((f) => f.toString()).join(',');

  factory EmpleadoRemoto.desdeJson(Map<String, dynamic> j) => EmpleadoRemoto(
        id: (j['id'] as num).toInt(),
        documento: j['documento'] as String,
        nombre: j['nombre'] as String,
        cargo: j['cargo'] as String?,
        fotos: ((j['fotos'] as List?) ?? const [])
            .map((f) => FotoRef.desdeJson(f as Map<String, dynamic>))
            .toList(),
        turnoHoy: (j['turno_hoy'] as Map<String, dynamic>?)?['bloques'] as String?,
        tolerancia: ((j['turno_hoy'] as Map<String, dynamic>?)?['tolerancia_min'] as num?)?.toInt() ?? 10,
      );
}

/// Nivel de acceso dentro de esta app: lo que puede hacer en el kiosco.
enum Rol {
  general('GENERAL', 'General'),
  administrativo('ADMINISTRATIVO', 'Administrativo');

  const Rol(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static Rol desdeApi(String? v) => v == 'ADMINISTRATIVO' ? administrativo : general;
}

/// Rol de la cuenta en Presente (la misma cuenta puede tener otro en Ventario).
enum RolAsistencia {
  admin('ADMIN', 'Administrador', 'Todo en la empresa: sedes, equipo, horarios y reportes'),
  gerente('GERENTE', 'Gerente', 'Personal, horarios y reportes de sus sedes'),
  talentoHumano('TALENTO_HUMANO', 'Talento humano', 'Personal, rostros, turnos, reportes y teléfonos de todas las sedes'),
  operario('OPERARIO', 'Operario', 'Cuenta de los teléfonos de marcación: una para todas las sedes');

  const RolAsistencia(this.api, this.etiqueta, this.descripcion);
  final String api;
  final String etiqueta;
  final String descripcion;

  /// GENERAL y OPERADOR son los nombres anteriores del operario.
  static RolAsistencia? desdeApi(String? v) => switch (v) {
        'GENERAL' || 'OPERADOR' => operario,
        _ => values.where((r) => r.api == v).firstOrNull,
      };
}

/// Rol de la cuenta en la app de Inventario POS.
enum RolInventario {
  admin('ADMIN', 'Director'),
  gerente('GERENTE', 'Gerente'),
  auxiliar('AUXILIAR_INVENTARIO', 'Auxiliar de inventario'),
  vendedor('VENDEDOR', 'Vendedor');

  const RolInventario(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  /// Vendedor y auxiliar pertenecen a exactamente una sede.
  bool get unaSede => this == auxiliar || this == vendedor;

  static RolInventario? desdeApi(String? v) => values.where((r) => r.api == v).firstOrNull;
}

/// Empresa de la cuenta, tal como la devuelve el login.
class EmpresaRef {
  const EmpresaRef({required this.uuid, required this.nombre});
  final String uuid;
  final String nombre;

  static EmpresaRef? desdeJson(Map<String, dynamic>? j) =>
      j == null ? null : EmpresaRef(uuid: j['uuid'] as String, nombre: j['nombre'] as String);
}

class SesionAdmin {
  const SesionAdmin({
    required this.token,
    required this.nombre,
    required this.rol,
    required this.expira,
    this.email = '',
    this.rolAsistencia,
    this.empresa,
  });
  final String token;
  final String nombre;
  final String email;
  final Rol rol;
  final RolAsistencia? rolAsistencia;
  final EmpresaRef? empresa;
  final DateTime expira;

  bool get vigente => DateTime.now().isBefore(expira);

  /// Para guardarla en el teléfono (almacenamiento seguro) y no pedir entrar
  /// cada vez que se abre la app.
  Map<String, dynamic> aJson() => {
        'token': token,
        'nombre': nombre,
        'email': email,
        'rol': rol.api,
        'rol_asistencia': rolAsistencia?.api,
        'empresa': empresa == null ? null : {'uuid': empresa!.uuid, 'nombre': empresa!.nombre},
        'expira': expira.toIso8601String(),
      };

  static SesionAdmin? desdeJson(Map<String, dynamic> j) {
    try {
      return SesionAdmin(
        token: j['token'] as String,
        nombre: j['nombre'] as String,
        email: (j['email'] as String?) ?? '',
        rol: Rol.desdeApi(j['rol'] as String?),
        rolAsistencia: RolAsistencia.desdeApi(j['rol_asistencia'] as String?),
        empresa: EmpresaRef.desdeJson(j['empresa'] as Map<String, dynamic>?),
        expira: DateTime.parse(j['expira'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// Entra al panel: administrador, gerente o talento humano.
  bool get esAdministrativo => rol == Rol.administrativo && !esOperario;

  /// La cuenta de los teléfonos de marcación: solo los vincula.
  bool get esOperario => rolAsistencia == RolAsistencia.operario || rol == Rol.general;

  bool get esTalentoHumano => rolAsistencia == RolAsistencia.talentoHumano;

  /// Dueño de la empresa: sedes, cuentas, turnos y datos de la empresa.
  bool get esAdminEmpresa => rolAsistencia == RolAsistencia.admin;
}

/// Lo usado y el máximo de un recurso del plan (`maximo` null = sin límite).
class RecursoPlan {
  const RecursoPlan({required this.usados, this.maximo});
  final int usados;
  final int? maximo;

  bool get lleno => maximo != null && usados >= maximo!;
  bool get ilimitado => maximo == null;

  /// Cuántos caben todavía (null = sin límite).
  int? get disponibles => maximo == null ? null : (maximo! - usados).clamp(0, maximo!);

  factory RecursoPlan.desdeJson(Map<String, dynamic>? j) => RecursoPlan(
        usados: ((j?['usados'] as num?) ?? 0).toInt(),
        maximo: (j?['maximo'] as num?)?.toInt(),
      );

  RecursoPlan conUnoMas() => RecursoPlan(usados: usados + 1, maximo: maximo);
}

/// Los recursos que limita un plan.
enum RecursoLimitado {
  sedes('sedes', 'Sedes', 'sede', 'sedes'),
  personas('personas', 'Personas', 'persona', 'personas'),
  productos('productos', 'Productos', 'producto', 'productos');

  const RecursoLimitado(this.api, this.titulo, this.singular, this.plural);
  final String api;
  final String titulo;
  final String singular;
  final String plural;

  static RecursoLimitado? desdeApi(String? v) => values.where((r) => r.api == v).firstOrNull;
}

/// Plan vigente de una app de la empresa y su uso. Cada app tiene el suyo:
/// pagar Ventario no cambia el de Presente.
class PlanEmpresa {
  const PlanEmpresa({
    required this.codigo,
    required this.nombre,
    required this.sedes,
    required this.personas,
    required this.productos,
    this.vence,
    this.vencido = false,
    this.aplicativo = 'ASISTENCIA',
  });

  /// ASISTENCIA (Presente) o INVENTARIO (Ventario).
  final String aplicativo;
  final String codigo;
  final String nombre;
  final DateTime? vence;
  final bool vencido;
  final RecursoPlan sedes;
  final RecursoPlan personas;
  final RecursoPlan productos;

  bool get esGratis => codigo == 'GRATIS';
  bool get esPresente => aplicativo == 'ASISTENCIA';
  String get nombreApp => esPresente ? 'Presente' : 'Ventario';

  /// Los productos solo existen en Ventario.
  List<RecursoLimitado> get recursos =>
      esPresente ? const [RecursoLimitado.sedes, RecursoLimitado.personas] : RecursoLimitado.values;

  RecursoPlan de(RecursoLimitado r) => switch (r) {
        RecursoLimitado.sedes => sedes,
        RecursoLimitado.personas => personas,
        RecursoLimitado.productos => productos,
      };

  static PlanEmpresa? desdeJson(Map<String, dynamic>? j) => j == null
      ? null
      : PlanEmpresa(
          aplicativo: (j['aplicativo'] as String?) ?? 'ASISTENCIA',
          codigo: j['codigo'] as String,
          nombre: j['nombre'] as String,
          vence: j['vence'] == null ? null : DateTime.parse(j['vence'] as String),
          vencido: j['vencido'] as bool? ?? false,
          sedes: RecursoPlan.desdeJson(j['sedes'] as Map<String, dynamic>?),
          personas: RecursoPlan.desdeJson(j['personas'] as Map<String, dynamic>?),
          productos: RecursoPlan.desdeJson(j['productos'] as Map<String, dynamic>?),
        );
}

/// Datos de la empresa, su plan y las apps que tiene habilitadas.
class EmpresaInfo {
  const EmpresaInfo({
    required this.uuid,
    required this.nombre,
    this.nit,
    this.telefono,
    this.email,
    this.plan,
    this.planVentario,
    this.aplicativos = const [],
  });

  final String uuid;
  final String nombre;
  final String? nit;
  final String? telefono;
  final String? email;

  /// Plan de Presente (esta app) y de Ventario: cada app tiene el suyo.
  final PlanEmpresa? plan;
  final PlanEmpresa? planVentario;
  final List<String> aplicativos;

  bool get tieneInventario => aplicativos.contains('INVENTARIO');

  factory EmpresaInfo.desdeJson(Map<String, dynamic> j) {
    final e = j['empresa'] as Map<String, dynamic>;
    final planes = j['planes'] as Map<String, dynamic>?;
    return EmpresaInfo(
      planVentario: PlanEmpresa.desdeJson(planes?['INVENTARIO'] as Map<String, dynamic>?),
      uuid: e['uuid'] as String,
      nombre: e['nombre'] as String,
      nit: e['nit'] as String?,
      telefono: e['telefono'] as String?,
      email: e['email_contacto'] as String?,
      plan: PlanEmpresa.desdeJson(j['plan'] as Map<String, dynamic>?),
      aplicativos: ((j['aplicativos'] as List?) ?? const []).cast<String>(),
    );
  }
}

/// Cuenta de la empresa: una persona, un rol en cada app.
class Usuario {
  const Usuario({
    required this.id,
    required this.nombre,
    required this.email,
    required this.activo,
    this.rolAsistencia,
    this.rolInventario,
    this.sedes = const [],
    this.documento,
    this.pausaAsistencia = false,
    this.telefono,
    this.empleadoId,
  });
  final int id;
  final String nombre;
  final String email;
  final RolAsistencia? rolAsistencia;
  final RolInventario? rolInventario;
  final List<int> sedes;
  final String? documento;
  final bool activo;

  /// En pausa en Presente porque el plan no alcanza para todos.
  final bool pausaAsistencia;
  final String? telefono;

  /// Empleado al que pertenece (null = cuenta técnica, como el operario).
  final int? empleadoId;

  bool get tieneVentario => rolInventario != null;


  factory Usuario.desdeJson(Map<String, dynamic> j) => Usuario(
        id: (j['id'] as num).toInt(),
        nombre: j['nombre'] as String,
        email: (j['email'] ?? j['usuario']) as String,
        rolAsistencia: RolAsistencia.desdeApi(j['rol_asistencia'] as String?),
        rolInventario: RolInventario.desdeApi(j['rol_inventario'] as String?),
        sedes: ((j['sedes'] as List?) ?? const []).map((s) => (s as num).toInt()).toList(),
        documento: j['documento'] as String?,
        activo: j['activo'] as bool? ?? true,
        pausaAsistencia: j['pausa_asistencia'] as bool? ?? false,
        telefono: j['telefono'] as String?,
        empleadoId: (j['empleado_id'] as num?)?.toInt(),
      );
}

/// Empleado que aún no tiene acceso a Presente (registrado aquí o en Ventario).
class CandidatoCuenta {
  const CandidatoCuenta({
    required this.id,
    required this.documento,
    required this.nombre,
    required this.sedeId,
    required this.sede,
    this.cargo,
    this.telefono,
    this.email,
    this.conCuenta = false,
  });
  final int id;
  final String documento;
  final String nombre;
  final int sedeId;
  final String sede;
  final String? cargo;
  final String? telefono;
  final String? email;

  /// Ya entra a Ventario: con el mismo correo y contraseña entrará aquí.
  final bool conCuenta;

  factory CandidatoCuenta.desdeJson(Map<String, dynamic> j) => CandidatoCuenta(
        id: (j['id'] as num).toInt(),
        documento: j['documento'] as String,
        nombre: j['nombre'] as String,
        sedeId: (j['sede_id'] as num).toInt(),
        sede: j['sede'] as String,
        cargo: j['cargo'] as String?,
        telefono: j['telefono'] as String?,
        email: j['email'] as String?,
        conCuenta: j['con_cuenta'] as bool? ?? false,
      );
}

/// Lista de cuentas con lo que hace falta para el formulario.
class EquipoEmpresa {
  const EquipoEmpresa({required this.usuarios, required this.aplicativos, this.plan});
  final List<Usuario> usuarios;
  final List<String> aplicativos;
  final PlanEmpresa? plan;
}

/// Teléfono de marcación. El [codigo] corto se ve en su pantalla: así se sabe
/// qué aparato físico es cuál cuando todos son del mismo modelo.
class KioscoRegistrado {
  const KioscoRegistrado({
    required this.id,
    required this.nombre,
    required this.sedeId,
    required this.sede,
    this.codigo,
    this.ultimoSync,
    this.vinculadoPor,
  });
  final int id;
  final String nombre;
  final int sedeId;
  final String sede;
  final String? codigo;
  final DateTime? ultimoSync;
  final String? vinculadoPor;

  factory KioscoRegistrado.desdeJson(Map<String, dynamic> j) => KioscoRegistrado(
        id: (j['id'] as num).toInt(),
        nombre: j['nombre'] as String,
        sedeId: (j['sede_id'] as num).toInt(),
        sede: j['sede'] as String,
        codigo: j['codigo'] as String?,
        ultimoSync: j['ultimo_sync'] == null ? null : DateTime.parse(j['ultimo_sync'] as String),
        vinculadoPor: j['vinculado_por'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Horarios
// ---------------------------------------------------------------------------

/// Bloque de trabajo en minutos desde medianoche.
typedef Bloque = ({int inicio, int fin});

List<Bloque> bloquesDesdeTexto(String texto) => [
      for (final b in texto.split(',').where((x) => x.contains('-')))
        (inicio: _minutos(b.split('-')[0]), fin: _minutos(b.split('-')[1])),
    ];

String bloquesATexto(List<Bloque> bloques) => bloques.map((b) => '${hhmm(b.inicio)}-${hhmm(b.fin)}').join(',');

int _minutos(String hhmm) {
  final p = hhmm.trim().split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String hhmm(int minutos) =>
    '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';

/// Días de la semana como bits: Lun=1 … Dom=64.
abstract final class DiasSemana {
  static const letras = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const nombres = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

  static bool incluye(int mascara, int indice) => mascara & (1 << indice) != 0;

  static String texto(int mascara) {
    if (mascara == 127) return 'Todos los días';
    if (mascara == 63) return 'Lunes a sábado';
    if (mascara == 31) return 'Lunes a viernes';
    return [for (var i = 0; i < 7; i++) if (incluye(mascara, i)) letras[i]].join(' · ');
  }
}

class Horario {
  const Horario({
    required this.id,
    required this.nombre,
    required this.bloques,
    required this.dias,
    required this.toleranciaMin,
    this.activo = true,
  });

  final int id;
  final String nombre;
  final String bloques;
  final int dias;
  final int toleranciaMin;
  final bool activo;

  List<Bloque> get listaBloques => bloquesDesdeTexto(bloques);
  int get minutosDia => listaBloques.fold(0, (s, b) => s + b.fin - b.inicio);

  factory Horario.desdeJson(Map<String, dynamic> j) => Horario(
        id: (j['id'] as num).toInt(),
        nombre: j['nombre'] as String,
        bloques: j['bloques'] as String,
        dias: (j['dias'] as num?)?.toInt() ?? 63,
        toleranciaMin: (j['tolerancia_min'] as num?)?.toInt() ?? 10,
        activo: j['activo'] as bool? ?? true,
      );
}

class PlanSemana {
  const PlanSemana({required this.semana, this.horario, required this.ajustada});
  final DateTime semana;
  final Horario? horario;
  final bool ajustada;

  factory PlanSemana.desdeJson(Map<String, dynamic> j) => PlanSemana(
        semana: DateTime.parse(j['semana'] as String),
        horario: j['horario'] == null ? null : Horario.desdeJson(j['horario'] as Map<String, dynamic>),
        ajustada: j['ajustada'] as bool? ?? false,
      );
}

class PlanEmpleado {
  const PlanEmpleado({this.desde, this.secuencia = const [], required this.semanas});
  final DateTime? desde;
  final List<int> secuencia;
  final List<PlanSemana> semanas;

  bool get tieneRotacion => secuencia.isNotEmpty;

  factory PlanEmpleado.desdeJson(Map<String, dynamic> j) {
    final rot = j['rotacion'] as Map<String, dynamic>?;
    return PlanEmpleado(
      desde: rot == null ? null : DateTime.parse(rot['desde'] as String),
      secuencia: rot == null ? const [] : (rot['secuencia'] as List).map((e) => (e as num).toInt()).toList(),
      semanas: (j['semanas'] as List).map((s) => PlanSemana.desdeJson(s as Map<String, dynamic>)).toList(),
    );
  }
}

/// Turno resumido (en listados y reportes).
class TurnoCorto {
  const TurnoCorto({required this.nombre, required this.bloques, this.toleranciaMin = 10});
  final String nombre;
  final String bloques;
  final int toleranciaMin;

  factory TurnoCorto.desdeJson(Map<String, dynamic> j) => TurnoCorto(
        nombre: (j['nombre'] as String?) ?? '',
        bloques: j['bloques'] as String,
        toleranciaMin: (j['tolerancia_min'] as num?)?.toInt() ?? 10,
      );
}

// ---------------------------------------------------------------------------
// Cumplimiento
// ---------------------------------------------------------------------------

enum EstadoCumplimiento {
  cumple('CUMPLE', 'Cumple'),
  tarde('TARDE', 'Llegó tarde'),
  sinLlegar('SIN_LLEGAR', 'Aún no llega'),
  salidaAnticipada('SALIDA_ANTICIPADA', 'Salió antes'),
  sinSalida('SIN_SALIDA', 'Sin salida'),
  incompleto('INCOMPLETO', 'Incompleto'),
  ausente('AUSENTE', 'No asistió'),
  pendiente('PENDIENTE', 'Pendiente'),
  libre('LIBRE', 'Libre'),
  extra('EXTRA', 'Fuera de turno');

  const EstadoCumplimiento(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static EstadoCumplimiento desdeApi(String? v) =>
      EstadoCumplimiento.values.firstWhere((e) => e.api == v, orElse: () => libre);

  bool get incumple => this == salidaAnticipada || this == sinSalida || this == incompleto || this == ausente;
  bool get esTarde => this == tarde || this == sinLlegar;
}

class BloqueCumplimiento {
  const BloqueCumplimiento({
    required this.inicio,
    required this.fin,
    this.llegada,
    this.salida,
    required this.retrasoMin,
    required this.anticipoMin,
    required this.estado,
  });

  final String inicio;
  final String fin;
  final String? llegada;
  final String? salida;
  final int retrasoMin;
  final int anticipoMin;
  final String estado; // OK, TARDE, ANTICIPADA, TARDE_ANTICIPADA, FALTA, PENDIENTE, SIN_LLEGAR, EN_CURSO, SIN_SALIDA

  factory BloqueCumplimiento.desdeJson(Map<String, dynamic> j) => BloqueCumplimiento(
        inicio: j['inicio'] as String,
        fin: j['fin'] as String,
        llegada: j['llegada'] as String?,
        salida: j['salida'] as String?,
        retrasoMin: (j['retraso_min'] as num).toInt(),
        anticipoMin: (j['anticipo_min'] as num).toInt(),
        estado: j['estado'] as String,
      );
}

class Cumplimiento {
  const Cumplimiento({
    required this.estado,
    required this.programadoMin,
    required this.retrasoMin,
    required this.anticipoMin,
    required this.parcial,
    required this.bloques,
  });

  final EstadoCumplimiento estado;
  final int programadoMin;
  final int retrasoMin;
  final int anticipoMin;
  final bool parcial;
  final List<BloqueCumplimiento> bloques;

  static const vacio = Cumplimiento(
    estado: EstadoCumplimiento.libre,
    programadoMin: 0,
    retrasoMin: 0,
    anticipoMin: 0,
    parcial: false,
    bloques: [],
  );

  factory Cumplimiento.desdeJson(Map<String, dynamic>? j) {
    if (j == null) return vacio;
    return Cumplimiento(
      estado: EstadoCumplimiento.desdeApi(j['estado'] as String?),
      programadoMin: (j['programado_min'] as num?)?.toInt() ?? 0,
      retrasoMin: (j['retraso_min'] as num?)?.toInt() ?? 0,
      anticipoMin: (j['anticipo_min'] as num?)?.toInt() ?? 0,
      parcial: j['parcial'] as bool? ?? false,
      bloques: ((j['bloques'] as List?) ?? const [])
          .map((b) => BloqueCumplimiento.desdeJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FilaCumplimiento {
  const FilaCumplimiento({
    required this.id,
    required this.documento,
    required this.nombre,
    this.cargo,
    this.porcentaje,
    required this.diasProgramados,
    required this.diasCumplidos,
    required this.tardanzas,
    required this.minutosTarde,
    required this.salidasAnticipadas,
    required this.minutosAnticipados,
    required this.ausencias,
    required this.incompletos,
    required this.minutosProgramados,
    required this.minutosTrabajados,
    required this.dias,
  });

  final int id;
  final String documento;
  final String nombre;
  final String? cargo;
  final int? porcentaje;
  final int diasProgramados;
  final int diasCumplidos;
  final int tardanzas;
  final int minutosTarde;
  final int salidasAnticipadas;
  final int minutosAnticipados;
  final int ausencias;
  final int incompletos;
  final int minutosProgramados;
  final int minutosTrabajados;
  final List<({DateTime fecha, EstadoCumplimiento? estado})> dias;

  factory FilaCumplimiento.desdeJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return FilaCumplimiento(
      id: n('id'),
      documento: j['documento'] as String,
      nombre: j['nombre'] as String,
      cargo: j['cargo'] as String?,
      porcentaje: (j['porcentaje'] as num?)?.toInt(),
      diasProgramados: n('dias_programados'),
      diasCumplidos: n('dias_cumplidos'),
      tardanzas: n('tardanzas'),
      minutosTarde: n('minutos_tarde'),
      salidasAnticipadas: n('salidas_anticipadas'),
      minutosAnticipados: n('minutos_anticipados'),
      ausencias: n('ausencias'),
      incompletos: n('incompletos'),
      minutosProgramados: n('minutos_programados'),
      minutosTrabajados: n('minutos_trabajados'),
      dias: ((j['dias'] as List?) ?? const []).map((d) {
        final m = d as Map<String, dynamic>;
        return (
          fecha: DateTime.parse(m['fecha'] as String),
          estado: m['estado'] == null ? null : EstadoCumplimiento.desdeApi(m['estado'] as String),
        );
      }).toList(),
    );
  }
}

class ReporteCumplimiento {
  const ReporteCumplimiento({
    required this.desde,
    required this.hasta,
    this.porcentaje,
    required this.diasProgramados,
    required this.diasCumplidos,
    required this.tardanzas,
    required this.ausencias,
    required this.salidasAnticipadas,
    required this.empleados,
  });

  final DateTime desde;
  final DateTime hasta;
  final int? porcentaje;
  final int diasProgramados;
  final int diasCumplidos;
  final int tardanzas;
  final int ausencias;
  final int salidasAnticipadas;
  final List<FilaCumplimiento> empleados;

  factory ReporteCumplimiento.desdeJson(Map<String, dynamic> j) {
    final r = j['resumen'] as Map<String, dynamic>;
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    return ReporteCumplimiento(
      desde: DateTime.parse(j['desde'] as String),
      hasta: DateTime.parse(j['hasta'] as String),
      porcentaje: (r['porcentaje'] as num?)?.toInt(),
      diasProgramados: n('dias_programados'),
      diasCumplidos: n('dias_cumplidos'),
      tardanzas: n('tardanzas'),
      ausencias: n('ausencias'),
      salidasAnticipadas: n('salidas_anticipadas'),
      empleados: (j['empleados'] as List).map((e) => FilaCumplimiento.desdeJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class DispositivoRegistrado {
  const DispositivoRegistrado({
    required this.id,
    required this.nombre,
    required this.token,
    required this.sede,
    this.codigo,
  });
  final int id;
  final String nombre;
  final String token;
  final Sede sede;
  final String? codigo;
}

// ---------------------------------------------------------------------------
// Reporte diario
// ---------------------------------------------------------------------------

enum EstadoAsistencia {
  enSede('EN_SEDE', 'En la sede'),
  salio('SALIO', 'Salió'),
  sinSalida('SIN_SALIDA', 'Sin salida'),
  ausente('AUSENTE', 'Ausente'),
  libre('LIBRE', 'Libre');

  const EstadoAsistencia(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static EstadoAsistencia desdeApi(String v) =>
      EstadoAsistencia.values.firstWhere((e) => e.api == v, orElse: () => ausente);
}

class MarcaReporte {
  const MarcaReporte({required this.tipo, required this.hora, required this.horaServidor, required this.desfaseSeg});
  final TipoMarcacion tipo;
  final DateTime hora;
  final DateTime horaServidor;
  final int desfaseSeg;

  factory MarcaReporte.desdeJson(Map<String, dynamic> j) => MarcaReporte(
        tipo: TipoMarcacion.desdeApi(j['tipo'] as String),
        hora: DateTime.parse(j['hora'] as String),
        horaServidor: DateTime.parse(j['hora_servidor'] as String),
        desfaseSeg: (j['desfase_seg'] as num).toInt(),
      );
}

class FilaReporte {
  const FilaReporte({
    required this.id,
    required this.documento,
    required this.nombre,
    this.cargo,
    required this.estado,
    this.entrada,
    this.salida,
    required this.minutos,
    this.abiertaDesde,
    required this.alertas,
    required this.marcaciones,
    this.turno,
    this.cumplimiento = Cumplimiento.vacio,
  });

  final int id;
  final String documento;
  final String nombre;
  final String? cargo;
  final EstadoAsistencia estado;
  final DateTime? entrada;
  final DateTime? salida;
  final int minutos;
  final DateTime? abiertaDesde;
  final List<String> alertas;
  final List<MarcaReporte> marcaciones;
  final TurnoCorto? turno;
  final Cumplimiento cumplimiento;

  bool get relojAdelantado => alertas.contains('RELOJ_ADELANTADO');

  /// Minutos trabajados incluyendo el tramo en curso si sigue en la sede.
  int get minutosAhora {
    if (abiertaDesde == null) return minutos;
    return minutos + DateTime.now().difference(abiertaDesde!).inMinutes;
  }

  factory FilaReporte.desdeJson(Map<String, dynamic> j) {
    DateTime? f(String k) => j[k] == null ? null : DateTime.parse(j[k] as String);
    return FilaReporte(
      id: (j['id'] as num).toInt(),
      documento: j['documento'] as String,
      nombre: j['nombre'] as String,
      cargo: j['cargo'] as String?,
      estado: EstadoAsistencia.desdeApi(j['estado'] as String),
      entrada: f('entrada'),
      salida: f('salida'),
      minutos: (j['minutos'] as num).toInt(),
      abiertaDesde: f('abierta_desde'),
      alertas: ((j['alertas'] as List?) ?? const []).cast<String>(),
      marcaciones: ((j['marcaciones'] as List?) ?? const [])
          .map((m) => MarcaReporte.desdeJson(m as Map<String, dynamic>))
          .toList(),
      turno: j['turno'] == null ? null : TurnoCorto.desdeJson(j['turno'] as Map<String, dynamic>),
      cumplimiento: Cumplimiento.desdeJson(j['cumplimiento'] as Map<String, dynamic>?),
    );
  }
}

class ReporteDia {
  const ReporteDia({
    required this.fecha,
    required this.esHoy,
    required this.sede,
    required this.total,
    required this.presentes,
    required this.ausentes,
    required this.enSede,
    required this.sinSalida,
    required this.libres,
    required this.conTurno,
    required this.cumplen,
    required this.tarde,
    required this.incumplen,
    required this.filas,
  });

  final String fecha;
  final bool esHoy;
  final Sede sede;
  final int total;
  final int presentes;
  final int ausentes;
  final int enSede;
  final int sinSalida;
  final int libres;
  final int conTurno;
  final int cumplen;
  final int tarde;
  final int incumplen;
  final List<FilaReporte> filas;

  factory ReporteDia.desdeJson(Map<String, dynamic> j) {
    final r = j['resumen'] as Map<String, dynamic>;
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    return ReporteDia(
      fecha: j['fecha'] as String,
      esHoy: j['es_hoy'] as bool? ?? false,
      sede: Sede.desdeJson(j['sede'] as Map<String, dynamic>),
      total: n('total'),
      presentes: n('presentes'),
      ausentes: n('ausentes'),
      enSede: n('en_sede'),
      sinSalida: n('sin_salida'),
      libres: n('libres'),
      conTurno: n('con_turno'),
      cumplen: n('cumplen'),
      tarde: n('tarde'),
      incumplen: n('incumplen'),
      filas: (j['empleados'] as List).map((e) => FilaReporte.desdeJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// Vector facial de una foto, listo para comparar.
class VectorRostro {
  const VectorRostro(this.empleadoId, this.valores);
  final int empleadoId;
  final Float32List valores;
}

// ---------------------------------------------------------------------------
// Novedades (permisos, incapacidades…): las envía el empleado por WhatsApp
// ---------------------------------------------------------------------------

enum TipoNovedad {
  permiso('PERMISO', 'Permiso'),
  incapacidad('INCAPACIDAD', 'Incapacidad médica'),
  citaMedica('CITA_MEDICA', 'Cita médica'),
  calamidad('CALAMIDAD', 'Calamidad doméstica'),
  vacaciones('VACACIONES', 'Vacaciones'),
  licencia('LICENCIA', 'Licencia'),
  otro('OTRO', 'Otra novedad');

  const TipoNovedad(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static TipoNovedad desdeApi(String? v) => values.where((t) => t.api == v).firstOrNull ?? otro;
}

enum EstadoNovedad {
  pendiente('PENDIENTE', 'Pendiente'),
  aprobada('APROBADA', 'Aprobada'),
  rechazada('RECHAZADA', 'Rechazada'),
  anulada('ANULADA', 'Anulada');

  const EstadoNovedad(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static EstadoNovedad desdeApi(String? v) => values.where((e) => e.api == v).firstOrNull ?? pendiente;
}

class Novedad {
  const Novedad({
    required this.id,
    required this.tipo,
    required this.estado,
    required this.desde,
    required this.hasta,
    required this.empleadoId,
    required this.empleado,
    required this.documento,
    required this.sedeId,
    required this.sede,
    this.horaDesde,
    this.horaHasta,
    this.cargo,
    this.motivo,
    this.comentario,
    this.soportes = 0,
    this.canal = 'WHATSAPP',
    this.resueltoPor,
    this.resueltoEn,
    this.creada,
  });

  final int id;
  final TipoNovedad tipo;
  final EstadoNovedad estado;

  /// Días (fecha local de la empresa, sin hora).
  final DateTime desde;
  final DateTime hasta;

  /// «08:00»; solo en un permiso por horas (dentro de [desde]).
  final String? horaDesde;
  final String? horaHasta;
  final int empleadoId;
  final String empleado;
  final String documento;
  final String? cargo;
  final int sedeId;
  final String sede;
  final String? motivo;
  final String? comentario;
  final int soportes;
  final String canal;
  final String? resueltoPor;
  final DateTime? resueltoEn;
  final DateTime? creada;

  bool get pendiente => estado == EstadoNovedad.pendiente;
  bool get porHoras => horaDesde != null;

  /// Días que cubre (1 en un permiso por horas).
  int get dias => hasta.difference(desde).inDays + 1;

  factory Novedad.desdeJson(Map<String, dynamic> j) {
    final e = j['empleado'] as Map<String, dynamic>;
    final s = j['sede'] as Map<String, dynamic>;
    DateTime? fecha(Object? v) => v == null ? null : DateTime.parse(v as String);
    return Novedad(
      id: (j['id'] as num).toInt(),
      tipo: TipoNovedad.desdeApi(j['tipo'] as String?),
      estado: EstadoNovedad.desdeApi(j['estado'] as String?),
      desde: DateTime.parse(j['fecha_desde'] as String),
      hasta: DateTime.parse(j['fecha_hasta'] as String),
      horaDesde: j['hora_desde'] as String?,
      horaHasta: j['hora_hasta'] as String?,
      motivo: j['motivo'] as String?,
      comentario: j['comentario'] as String?,
      soportes: ((j['soportes'] as num?) ?? 0).toInt(),
      canal: (j['canal'] as String?) ?? 'WHATSAPP',
      empleadoId: (e['id'] as num).toInt(),
      empleado: e['nombre'] as String,
      documento: (e['documento'] ?? '') as String,
      cargo: e['cargo'] as String?,
      sedeId: (s['id'] as num).toInt(),
      sede: s['nombre'] as String,
      resueltoPor: j['resuelto_por'] as String?,
      resueltoEn: fecha(j['resuelto_en']),
      creada: fecha(j['creada']),
    );
  }
}

class SoporteNovedad {
  const SoporteNovedad({required this.id, required this.nombre, required this.mime, required this.tamano});
  final int id;
  final String nombre;
  final String mime;
  final int tamano;

  bool get esImagen => mime.startsWith('image/');
  bool get esPdf => mime == 'application/pdf';

  factory SoporteNovedad.desdeJson(Map<String, dynamic> j) => SoporteNovedad(
        id: (j['id'] as num).toInt(),
        nombre: j['nombre'] as String,
        mime: j['mime'] as String,
        tamano: (j['tamano'] as num).toInt(),
      );
}

/// Bandeja de novedades: la lista, cuántas esperan respuesta y si la cuenta
/// puede abrir los soportes (datos de salud: administrador y talento humano).
class BandejaNovedades {
  const BandejaNovedades({required this.novedades, required this.pendientes, required this.veSoportes});
  final List<Novedad> novedades;
  final int pendientes;
  final bool veSoportes;
}
