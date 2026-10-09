import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constantes.dart';
import '../data/almacen_local.dart';
import '../data/api.dart';
import '../data/modelos.dart';
import '../vision/comparador.dart';
import '../vision/motor_rostros.dart';

/// Sincronización "offline-first":
///  1. Envía la cola de marcaciones pendientes (idempotente).
///  2. Trae la plantilla de la sede (304 si no cambió nada).
///  3. Descarga solo las fotos nuevas y calcula sus vectores EN el teléfono.
///  4. Trae las marcaciones de hoy hechas en otros kioscos de la sede.
class Sincronizador extends ChangeNotifier {
  Sincronizador({
    required this.api,
    required this.almacen,
    required this.motor,
    required this.comparador,
    required this.alRevocar,
    required this.alCambiarSede,
  });

  final Api api;
  final AlmacenLocal almacen;
  final MotorRostros? motor;
  final Comparador comparador;
  final VoidCallback alRevocar;
  final ValueChanged<Sede> alCambiarSede;

  bool enLinea = true;
  bool sincronizando = false;
  DateTime? ultimaSync;
  String? error;
  int pendientes = 0;
  int empleados = 0;
  int reconocibles = 0;
  Duration? desfaseReloj;

  /// Progreso al procesar rostros nuevos (null = nada en curso).
  ({int hechos, int total})? progresoRostros;

  Timer? _temporizador;
  Timer? _envioDiferido;
  Completer<void>? _enCurso;
  bool _cerrado = false;

  bool get relojDesfasado =>
      desfaseReloj != null && desfaseReloj!.inSeconds.abs() > Constantes.desfaseRelojMaximo;

  Future<void> iniciar() async {
    await recargarComparador();
    await _actualizarConteos();
    _temporizador = Timer.periodic(Constantes.intervaloSync, (_) => sincronizar());
    unawaited(sincronizar());
  }

  Future<void> sincronizar({bool forzar = false}) async {
    if (_enCurso != null) return _enCurso!.future;
    final enCurso = _enCurso = Completer<void>();
    sincronizando = true;
    _notificar();
    try {
      final salud = await api.salud();
      desfaseReloj = salud.desfase;
      enLinea = true;
      await _enviarPendientes();
      await _sincronizarPlantilla(forzar: forzar);
      await almacen.fusionarRemotas(await api.kioscoMarcacionesHoy());
      await almacen.limpiarHistorial();
      ultimaSync = DateTime.now();
      error = null;
    } on ApiError catch (e) {
      if (e.sinConexion) {
        enLinea = false;
      } else {
        error = e.mensaje;
      }
      if (e.dispositivoRevocado) alRevocar();
    } catch (e) {
      error = 'Error al sincronizar: $e';
    } finally {
      progresoRostros = null;
      sincronizando = false;
      await _actualizarConteos();
      _enCurso = null;
      enCurso.complete();
      _notificar();
    }
  }

  /// Intenta enviar de inmediato (tras cada marcación). Si no hay red, la
  /// marcación queda en cola y se reintenta en la próxima sincronización.
  void enviarPronto() {
    _envioDiferido?.cancel();
    _envioDiferido = Timer(const Duration(milliseconds: 600), () async {
      if (_enCurso != null) return;
      try {
        await _enviarPendientes();
        enLinea = true;
      } on ApiError catch (e) {
        if (e.sinConexion) enLinea = false;
        if (e.dispositivoRevocado) alRevocar();
      } catch (_) {}
      await _actualizarConteos();
      _notificar();
    });
  }

  Future<void> _enviarPendientes() async {
    const lote = 200;
    while (true) {
      final cola = await almacen.pendientes(limite: lote);
      if (cola.isEmpty) break;
      final resultados = await api.kioscoEnviarMarcaciones(cola);
      final aceptadas = <int>[];
      final rechazadas = <int>[];
      for (final r in resultados) {
        if (r.indice < 0 || r.indice >= cola.length) continue;
        (r.aceptada ? aceptadas : rechazadas).add(cola[r.indice].idLocal!);
        if (!r.aceptada) debugPrint('Marcación rechazada por el servidor: ${r.motivo}');
      }
      await almacen.marcarEnviadas(aceptadas);
      await almacen.descartar(rechazadas);
      if (cola.length < lote) break;
    }
  }

  Future<void> _sincronizarPlantilla({bool forzar = false}) async {
    final etag = forzar ? null : await almacen.ajuste('etag_plantilla');
    final plantilla = await api.kioscoEmpleados(etag: etag);
    if (plantilla == null) return; // 304: nada cambió

    alCambiarSede(plantilla.sede);
    final firmasLocales = await almacen.firmasFotos();
    final remotos = {for (final e in plantilla.empleados) e.id: e};

    await almacen.borrarEmpleados(firmasLocales.keys.where((id) => !remotos.containsKey(id)));

    final porProcesar = <EmpleadoRemoto>[];
    for (final e in plantilla.empleados) {
      await almacen.guardarDatosEmpleado(e, fecha: plantilla.fecha);
      if (firmasLocales[e.id] != e.firmaFotos || forzar) porProcesar.add(e);
    }

    if (porProcesar.isNotEmpty && motor != null) {
      progresoRostros = (hechos: 0, total: porProcesar.length);
      _notificar();
      for (final e in porProcesar) {
        await _procesarRostro(e);
        progresoRostros = (hechos: progresoRostros!.hechos + 1, total: porProcesar.length);
        _notificar();
      }
      await recargarComparador();
    }
    // El ETag solo se guarda cuando TODO quedó procesado.
    await almacen.guardarAjuste('etag_plantilla', plantilla.etag);
  }

  Future<void> _procesarRostro(EmpleadoRemoto e) async {
    final carpeta = almacen.carpetaDe(e.id);
    if (!carpeta.existsSync()) carpeta.createSync(recursive: true);

    final fotos = <({int n, int v, String ruta, List<Float32List> vectores})>[];
    for (final f in e.fotos) {
      final ruta = p.join(carpeta.path, '${f.n}_${f.v}.jpg');
      final archivo = File(ruta);
      if (!archivo.existsSync()) {
        await archivo.writeAsBytes(await api.descargarFoto(e.id, f.n), flush: true);
      }
      fotos.add((n: f.n, v: f.v, ruta: ruta, vectores: await motor!.vectoresDeFoto(ruta)));
    }
    await almacen.guardarRostro(empleadoId: e.id, firma: e.firmaFotos, fotos: fotos);
    _limpiarCarpeta(carpeta, fotos.map((f) => f.ruta).toSet());
  }

  /// Tras registrar un rostro desde ESTE teléfono: se guarda de una vez sin
  /// volver a descargar lo que se acaba de subir.
  Future<void> incorporarEnrolamiento(Empleado empleado, List<FotoRef> fotos, List<Uint8List> jpegs) async {
    if (motor == null) return;
    final remoto = EmpleadoRemoto(
      id: empleado.id,
      documento: empleado.documento,
      nombre: empleado.nombre,
      cargo: empleado.cargo,
      fotos: fotos,
    );
    await almacen.guardarDatosEmpleado(remoto);
    final carpeta = almacen.carpetaDe(empleado.id);
    if (!carpeta.existsSync()) carpeta.createSync(recursive: true);
    for (var i = 0; i < fotos.length && i < jpegs.length; i++) {
      await File(p.join(carpeta.path, '${fotos[i].n}_${fotos[i].v}.jpg')).writeAsBytes(jpegs[i], flush: true);
    }
    await _procesarRostro(remoto);
    await recargarComparador();
    await _actualizarConteos();
    _notificar();
  }

  void _limpiarCarpeta(Directory carpeta, Set<String> vigentes) {
    for (final f in carpeta.listSync().whereType<File>()) {
      if (!vigentes.contains(f.path)) f.deleteSync();
    }
  }

  Future<void> recargarComparador() async => comparador.cargar(await almacen.vectores());

  Future<void> _actualizarConteos() async {
    pendientes = await almacen.contarPendientes();
    final c = await almacen.conteos();
    empleados = c.empleados;
    reconocibles = c.reconocibles;
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _temporizador?.cancel();
    _envioDiferido?.cancel();
    super.dispose();
  }
}
