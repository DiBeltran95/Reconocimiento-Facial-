import 'package:flutter/foundation.dart';

import '../data/almacen_local.dart';
import '../data/api.dart';
import '../data/modelos.dart';
import '../vision/comparador.dart';
import '../vision/motor_rostros.dart';
import 'ajustes.dart';
import 'asistencia.dart';
import 'config_dispositivo.dart';
import 'sesion_admin.dart';
import 'sincronizador.dart';

/// Raíz de la aplicación: sabe si este teléfono es un punto de marcación
/// (vinculado a una sede) y mantiene vivos los servicios compartidos.
///
/// La API existe siempre: en un teléfono sin vincular también se inicia
/// sesión (para administrar o para vincularlo con la cuenta Operario).
class EstadoApp extends ChangeNotifier {
  EstadoApp._(this.almacen, this.ajustes, this.motor, this.errorMotor, this.api) {
    sesion.api = api;
  }

  final AlmacenLocal almacen;
  final Ajustes ajustes;
  final MotorRostros? motor;
  final String? errorMotor;
  final Comparador comparador = Comparador();
  final SesionAdminCtrl sesion = SesionAdminCtrl();
  final Api api;

  ConfigDispositivo? config;
  Sincronizador? sincronizador;
  Asistencia? asistencia;

  /// Mensaje a mostrar si el servidor desvinculó este dispositivo.
  String? avisoDesvinculado;

  /// ¿Este teléfono es un punto de marcación?
  bool get configurado => config != null && sincronizador != null;

  static Future<EstadoApp> iniciar() async {
    final almacen = await AlmacenLocal.abrir();
    final ajustes = Ajustes(almacen);
    await ajustes.cargar();

    MotorRostros? motor;
    String? error;
    try {
      motor = await MotorRostros.iniciar();
    } catch (e) {
      error = '$e';
      debugPrint('No se pudo cargar el modelo facial: $e');
    }

    final config = await ConfigDispositivo.cargar();
    final url = config?.url ?? await ConfigDispositivo.ultimaUrl() ?? Api.urlPorDefecto;
    final estado = EstadoApp._(almacen, ajustes, motor, error, Api(baseUrl: url));
    if (config != null) await estado._activar(config);
    return estado;
  }

  /// Solo en un teléfono sin vincular (instalaciones propias de la empresa).
  Future<void> cambiarServidor(String url) async {
    if (configurado) return;
    api.baseUrl = Api.normalizarUrl(url);
    await ConfigDispositivo.recordarUrl(api.baseUrl);
    notifyListeners();
  }

  /// Este teléfono queda como punto de marcación de [registro.sede].
  Future<void> vincular(DispositivoRegistrado registro) async {
    final nueva = ConfigDispositivo(
      url: api.baseUrl,
      token: registro.token,
      sede: registro.sede,
      nombre: registro.nombre,
      codigo: registro.codigo,
    );
    await nueva.guardar();
    await ConfigDispositivo.recordarUrl(nueva.url);
    avisoDesvinculado = null;
    await _activar(nueva);
    notifyListeners();
  }

  Future<void> _activar(ConfigDispositivo c) async {
    sincronizador?.dispose();
    config = c;
    api
      ..baseUrl = c.url
      ..tokenDispositivo = c.token;
    final sync = Sincronizador(
      api: api,
      almacen: almacen,
      motor: motor,
      comparador: comparador,
      alRevocar: () => desvincular(aviso: 'Un administrador desvinculó este teléfono.'),
      alCambiarSede: _actualizarSede,
    );
    sincronizador = sync;
    asistencia = Asistencia(almacen, sync);
    await sync.iniciar();
  }

  Future<void> _actualizarSede(Sede sede) async {
    final c = config;
    if (c == null || (c.sede.nombre == sede.nombre && c.sede.codigo == sede.codigo)) return;
    config = c.conSede(sede);
    await config!.guardar();
    notifyListeners();
  }

  /// Borra todo rastro local (empleados, rostros, cola) y el teléfono vuelve
  /// a ser uno cualquiera: ya no se puede marcar en él.
  Future<void> desvincular({String? aviso, bool avisarServidor = false}) async {
    if (config == null) return;
    if (avisarServidor) {
      try {
        await api.kioscoDesvincular();
      } catch (_) {}
    }
    sesion.cerrar();
    sincronizador?.dispose();
    sincronizador = null;
    asistencia = null;
    api.tokenDispositivo = null;
    config = null;
    comparador.cargar(const []);
    await almacen.borrarTodo();
    await ConfigDispositivo.borrar();
    await ajustes.cargar();
    avisoDesvinculado = aviso;
    notifyListeners();
  }
}
