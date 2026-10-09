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

/// Raíz de la aplicación: decide si el teléfono ya está vinculado a una sede
/// y mantiene vivos los servicios compartidos.
class EstadoApp extends ChangeNotifier {
  EstadoApp._(this.almacen, this.ajustes, this.motor, this.errorMotor);

  final AlmacenLocal almacen;
  final Ajustes ajustes;
  final MotorRostros? motor;
  final String? errorMotor;
  final Comparador comparador = Comparador();
  final SesionAdminCtrl sesion = SesionAdminCtrl();

  ConfigDispositivo? config;
  Api? api;
  Sincronizador? sincronizador;
  Asistencia? asistencia;

  /// Mensaje a mostrar si el servidor desvinculó este dispositivo.
  String? avisoDesvinculado;

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

    final estado = EstadoApp._(almacen, ajustes, motor, error);
    final config = await ConfigDispositivo.cargar();
    if (config != null) await estado._activar(config);
    return estado;
  }

  /// Completa la vinculación (desde el asistente de configuración).
  Future<void> vincular(ConfigDispositivo nueva) async {
    await nueva.guardar();
    await ConfigDispositivo.recordarUrl(nueva.url);
    await _activar(nueva);
    notifyListeners();
  }

  Future<void> _activar(ConfigDispositivo c) async {
    config = c;
    api = Api(baseUrl: c.url, tokenDispositivo: c.token);
    sesion.api = api;
    final sync = Sincronizador(
      api: api!,
      almacen: almacen,
      motor: motor,
      comparador: comparador,
      alRevocar: () => desvincular(aviso: 'Un administrador desvinculó este dispositivo.'),
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

  /// Borra todo rastro local (empleados, rostros, cola) y vuelve al asistente.
  Future<void> desvincular({String? aviso, bool avisarServidor = false}) async {
    if (config == null) return;
    if (avisarServidor) {
      try {
        await api?.kioscoDesvincular();
      } catch (_) {}
    }
    sesion.cerrar();
    sincronizador?.dispose();
    sincronizador = null;
    asistencia = null;
    api?.cerrar();
    api = null;
    config = null;
    comparador.cargar(const []);
    await almacen.borrarTodo();
    await ConfigDispositivo.borrar();
    await ajustes.cargar();
    avisoDesvinculado = aviso;
    notifyListeners();
  }
}
