import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/constantes.dart';
import '../../data/modelos.dart';
import '../../servicios/asistencia.dart';
import '../../servicios/estado_app.dart';
import '../../vision/motor_rostros.dart';
import '../../vision/vivacidad.dart';
import '../comun/camara.dart';

enum FaseKiosco {
  iniciando,
  esperando,
  ajustando,
  vivacidad,
  analizando,
  identificado,
  registrado,
  repetido,
  desconocido,
  sinRostros,
  error;

  bool get aceptaCuadros => const {esperando, ajustando, vivacidad, analizando, sinRostros}.contains(this);
  bool get escaneando => const {esperando, ajustando, vivacidad, analizando, sinRostros}.contains(this);
}

/// Máquina de estados del kiosco:
/// esperando → ajustando (calidad) → analizando (+ parpadeo) → identificado
/// → (confirmación automática) → registrado → esperando.
class ControladorKiosco extends ChangeNotifier {
  ControladorKiosco(this.estado);

  final EstadoApp estado;
  final CamaraFrontal camara = CamaraFrontal();
  final DetectorParpadeo _parpadeo = DetectorParpadeo();

  FaseKiosco fase = FaseKiosco.iniciando;
  String guia = '';
  String? error;

  /// Rostro actual y tamaño del cuadro (para dibujar la malla del HUD).
  Face? rostro;
  Size? tamanoImagen;

  double similitud = 0;
  EmpleadoLocal? empleado;
  TipoMarcacion tipo = TipoMarcacion.entrada;
  Marcacion? ultima;
  Marcacion? registrada;
  Puntualidad? puntualidad;
  int segundosRestantes = 0;

  /// Se incrementa en cada registro exitoso para lanzar la onda del HUD.
  int pulsos = 0;

  bool _activo = false;
  bool _ocupado = false;
  bool _cerrado = false;
  int? _candidato;
  int _votos = 0;
  int _intentos = 0;
  DateTime _ultimoRostro = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _temporizador;

  MotorRostros? get _motor => estado.motor;

  Future<void> iniciar() async {
    if (_activo || _cerrado) return;
    _activo = true;
    if (_motor == null) {
      fase = FaseKiosco.error;
      error = 'modelo';
      _notificar();
      return;
    }
    fase = FaseKiosco.iniciando;
    _notificar();
    try {
      await camara.iniciar(_alCuadro);
      if (!_activo) {
        await camara.detener();
        return;
      }
      error = null;
      _reiniciar();
    } catch (e) {
      _activo = false;
      fase = FaseKiosco.error;
      error = CamaraFrontal.mensajeError(e);
      _notificar();
    }
  }

  Future<void> pausar() async {
    _activo = false;
    _temporizador?.cancel();
    rostro = null;
    await camara.detener();
    _notificar();
  }

  void _alCuadro(CameraImage cuadro) {
    if (_ocupado || !_activo || !fase.aceptaCuadros) return;
    _ocupado = true;
    _procesar(cuadro).catchError((Object e) => debugPrint('Kiosco: $e')).whenComplete(() => _ocupado = false);
  }

  Future<void> _procesar(CameraImage cuadro) async {
    final motor = _motor!;
    final c = camara.controlador;
    if (c == null) return;
    final rotacion = camara.rotacion;
    final entrada = motor.entradaDesdeCamara(cuadro, rotacion);
    if (entrada == null) return;

    final rostros = await motor.detectar(entrada);
    if (!_activo || !fase.aceptaCuadros) return;
    tamanoImagen = MotorRostros.tamanoDerecho(cuadro, rotacion);

    if (rostros.isEmpty) {
      rostro = null;
      final sinCara = DateTime.now().difference(_ultimoRostro) > const Duration(milliseconds: 1200);
      if (sinCara && fase != FaseKiosco.esperando && fase != FaseKiosco.sinRostros) {
        _reiniciar();
      } else {
        _notificar();
      }
      return;
    }

    _ultimoRostro = DateTime.now();
    final r = MotorRostros.mayor(rostros);
    rostro = r;

    if (estado.comparador.vacio) {
      fase = FaseKiosco.sinRostros;
      _notificar();
      return;
    }

    final problema = _calidad(r, tamanoImagen!);
    if (problema != null) {
      fase = FaseKiosco.ajustando;
      guia = problema;
      _votos = 0;
      _candidato = null;
      _notificar();
      return;
    }

    final ajustes = estado.ajustes;
    if (ajustes.pruebaDeVida) _parpadeo.procesar(r);

    final vector = await motor.vectorDeCuadro(cuadro, rotacion, r);
    if (vector == null || !_activo || !fase.aceptaCuadros) return;

    final m = estado.comparador.buscar(vector);
    final aceptado = m != null && m.similitud >= ajustes.umbral && m.margen >= Constantes.margenSegundo;
    similitud = m?.similitud ?? 0;
    if (aceptado) {
      if (_candidato == m.empleadoId) {
        _votos++;
      } else {
        _candidato = m.empleadoId;
        _votos = 1;
      }
    } else {
      _candidato = null;
      _votos = 0;
      _intentos++;
    }

    final listo = _votos >= Constantes.votosNecesarios;
    if (listo && (!ajustes.pruebaDeVida || _parpadeo.completado)) {
      await _identificar(_candidato!);
      return;
    }
    if (listo) {
      fase = FaseKiosco.vivacidad;
      guia = 'Parpadea para confirmar';
    } else if (_intentos >= Constantes.intentosMaximos) {
      _mostrar(FaseKiosco.desconocido, const Duration(seconds: 6));
      HapticFeedback.vibrate();
      return;
    } else {
      fase = FaseKiosco.analizando;
      guia = 'Analizando rostro…';
    }
    _notificar();
  }

  String? _calidad(Face r, Size img) {
    final caja = r.boundingBox;
    final relativo = caja.width / img.width;
    if (relativo < Constantes.rostroMinimo) return 'Acércate un poco más';
    if (relativo > 0.88) return 'Aléjate un poco';
    final cx = caja.center.dx / img.width;
    final cy = caja.center.dy / img.height;
    if ((cx - 0.5).abs() > 0.2 || (cy - 0.45).abs() > 0.22) return 'Centra tu rostro en el óvalo';
    final yaw = (r.headEulerAngleY ?? 0).abs();
    final pitch = (r.headEulerAngleX ?? 0).abs();
    if (yaw > Constantes.anguloMaximo || pitch > Constantes.anguloMaximo) return 'Mira directo a la cámara';
    if ((r.headEulerAngleZ ?? 0).abs() > 25) return 'Endereza un poco la cabeza';
    return null;
  }

  Future<void> _identificar(int empleadoId) async {
    final asistencia = estado.asistencia;
    final e = await estado.almacen.empleado(empleadoId);
    if (e == null || asistencia == null) {
      _reiniciar();
      return;
    }
    final evaluacion = await asistencia.evaluar(empleadoId, minutosEspera: estado.ajustes.minutosEspera);
    empleado = e;
    ultima = evaluacion.ultima;
    if (evaluacion.enEspera) {
      _mostrar(FaseKiosco.repetido, const Duration(seconds: 4));
      return;
    }
    tipo = evaluacion.sugerido;
    fase = FaseKiosco.identificado;
    segundosRestantes = Constantes.segundosAutoConfirmar;
    HapticFeedback.mediumImpact();
    _temporizador?.cancel();
    _temporizador = Timer.periodic(const Duration(seconds: 1), (t) {
      segundosRestantes--;
      if (segundosRestantes <= 0) {
        t.cancel();
        confirmar(tipo);
      } else {
        _notificar();
      }
    });
    _notificar();
  }

  /// Registra la marcación (se guarda local y se envía en segundo plano).
  Future<void> confirmar(TipoMarcacion t) async {
    if (fase != FaseKiosco.identificado || empleado == null) return;
    _temporizador?.cancel();
    tipo = t;
    registrada = await estado.asistencia!.registrar(empleado!.id, t);
    puntualidad = Asistencia.puntualidad(empleado!, t, registrada!.hora);
    pulsos++;
    HapticFeedback.heavyImpact();
    if (estado.ajustes.sonido) SystemSound.play(SystemSoundType.click);
    _mostrar(FaseKiosco.registrado, const Duration(milliseconds: 3200));
  }

  /// "No soy yo": descarta la identificación y vuelve a escanear.
  void descartar() => _reiniciar();

  void reintentar() => _reiniciar();

  void _mostrar(FaseKiosco f, Duration duracion) {
    _temporizador?.cancel();
    fase = f;
    _notificar();
    _temporizador = Timer(duracion, _reiniciar);
  }

  void _reiniciar() {
    _temporizador?.cancel();
    fase = estado.comparador.vacio ? FaseKiosco.sinRostros : FaseKiosco.esperando;
    guia = 'Acércate y mira a la cámara';
    empleado = null;
    registrada = null;
    puntualidad = null;
    similitud = 0;
    _votos = 0;
    _candidato = null;
    _intentos = 0;
    _parpadeo.reiniciar();
    _notificar();
  }

  void _notificar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _activo = false;
    _temporizador?.cancel();
    camara.detener();
    super.dispose();
  }
}
