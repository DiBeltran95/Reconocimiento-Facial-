import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';

import '../../core/constantes.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../../vision/motor_rostros.dart';
import '../comun/camara.dart';
import '../comun/hud.dart';
import '../comun/widgets.dart';

/// Registro facial guiado: 3 tomas automáticas (frente, un lado, el otro).
/// Varios ángulos hacen el reconocimiento mucho más robusto.
class EnrolarPage extends StatefulWidget {
  const EnrolarPage({super.key, required this.empleado});
  final Empleado empleado;

  @override
  State<EnrolarPage> createState() => _EnrolarPageState();
}

enum _Etapa { camara, revision, guardando }

class _EnrolarPageState extends State<EnrolarPage> {
  late final EstadoApp _estado = context.read<EstadoApp>();
  final CamaraFrontal _camara = CamaraFrontal();
  final List<Uint8List> _fotos = [];

  _Etapa _etapa = _Etapa.camara;
  bool _ocupado = false;
  bool _capturando = false;
  int _estables = 0;
  int _signoLado = 0;
  Face? _rostro;
  Size? _tamano;
  String _guia = 'Mira al frente';
  bool _guiaOk = false;
  String? _error;
  String? _progreso;
  ({String nombre, double similitud})? _duplicado;
  int _destello = 0;

  int get _paso => _fotos.length;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _iniciarCamara();
  }

  @override
  void dispose() {
    _camara.detener();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _iniciarCamara() async {
    if (_estado.motor == null) {
      setState(() => _error = 'Falta el modelo de reconocimiento facial (ver README).');
      return;
    }
    try {
      await _camara.iniciar(_alCuadro);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = CamaraFrontal.mensajeError(e));
    }
  }

  void _alCuadro(CameraImage cuadro) {
    if (_ocupado || _capturando || _etapa != _Etapa.camara || _paso >= Constantes.fotosEnrolamiento) return;
    _ocupado = true;
    _procesar(cuadro).catchError((Object e) => debugPrint('Enrolar: $e')).whenComplete(() => _ocupado = false);
  }

  Future<void> _procesar(CameraImage cuadro) async {
    final motor = _estado.motor!;
    final rotacion = _camara.rotacion;
    final entrada = motor.entradaDesdeCamara(cuadro, rotacion);
    if (entrada == null) return;
    final rostros = await motor.detectar(entrada);
    if (!mounted || _etapa != _Etapa.camara) return;
    _tamano = MotorRostros.tamanoDerecho(cuadro, rotacion);

    if (rostros.isEmpty) {
      setState(() {
        _rostro = null;
        _estables = 0;
        _guia = 'Ubica tu rostro dentro del óvalo';
        _guiaOk = false;
      });
      return;
    }
    if (rostros.length > 1) {
      setState(() {
        _rostro = MotorRostros.mayor(rostros);
        _estables = 0;
        _guia = 'Solo debe aparecer una persona';
        _guiaOk = false;
      });
      return;
    }

    final r = rostros.first;
    final problema = _evaluar(r, _tamano!);
    setState(() {
      _rostro = r;
      _guia = problema ?? 'Perfecto, quédate quieto';
      _guiaOk = problema == null;
      _estables = problema == null ? _estables + 1 : 0;
    });
    if (_estables >= 3) await _capturar(cuadro, rotacion, r);
  }

  String? _evaluar(Face r, Size img) {
    final relativo = r.boundingBox.width / img.width;
    if (relativo < 0.33) return 'Acércate un poco más';
    if (relativo > 0.85) return 'Aléjate un poco';
    final cx = r.boundingBox.center.dx / img.width;
    final cy = r.boundingBox.center.dy / img.height;
    if ((cx - 0.5).abs() > 0.18 || (cy - 0.45).abs() > 0.2) return 'Centra tu rostro en el óvalo';
    if ((r.headEulerAngleX ?? 0).abs() > 15) return 'Mantén la cabeza recta, sin subir ni bajar';
    if ((r.headEulerAngleZ ?? 0).abs() > 15) return 'Endereza la cabeza';
    final ojos = ((r.leftEyeOpenProbability ?? 1) + (r.rightEyeOpenProbability ?? 1)) / 2;
    if (ojos < 0.5) return 'Mantén los ojos abiertos';

    final yaw = r.headEulerAngleY ?? 0;
    switch (_paso) {
      case 0:
        if (yaw.abs() > 8) return 'Mira directo a la cámara';
      case 1:
        if (yaw.abs() < 10) return 'Gira levemente la cabeza hacia un lado';
        if (yaw.abs() > 30) return 'Un poco menos de giro';
      default:
        if (yaw.abs() < 10 || yaw.sign == _signoLado) return 'Ahora gira levemente hacia el otro lado';
        if (yaw.abs() > 30) return 'Un poco menos de giro';
    }
    return null;
  }

  Future<void> _capturar(CameraImage cuadro, int rotacion, Face r) async {
    _capturando = true;
    try {
      final jpeg = await MotorRostros.jpegDeCuadro(cuadro, rotacion);
      if (_paso == 0) {
        // ¿Este rostro ya pertenece a OTRA persona registrada?
        final v = await _estado.motor!.vectorDeCuadro(cuadro, rotacion, r);
        final c = v == null ? null : _estado.comparador.buscar(v, excluir: widget.empleado.id);
        if (c != null && c.similitud >= _estado.ajustes.umbral) {
          final otro = await _estado.almacen.empleado(c.empleadoId);
          _duplicado = (nombre: otro?.nombre ?? 'otro empleado', similitud: c.similitud);
        }
      }
      if (_paso == 1) _signoLado = (r.headEulerAngleY ?? 0).sign.toInt();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _fotos.add(jpeg);
        _destello++;
        _estables = 0;
        _guia = switch (_paso) {
          1 => 'Gira levemente la cabeza hacia un lado',
          2 => 'Ahora gira levemente hacia el otro lado',
          _ => '¡Listo!',
        };
        _guiaOk = false;
      });
      if (_paso >= Constantes.fotosEnrolamiento) {
        await _camara.detener();
        if (mounted) setState(() => _etapa = _Etapa.revision);
      }
    } finally {
      _capturando = false;
    }
  }

  Future<void> _repetir() async {
    setState(() {
      _fotos.clear();
      _duplicado = null;
      _signoLado = 0;
      _etapa = _Etapa.camara;
      _guia = 'Mira al frente';
    });
    await _iniciarCamara();
  }

  Future<void> _guardar() async {
    setState(() {
      _etapa = _Etapa.guardando;
      _progreso = 'Subiendo fotos al servidor…';
    });
    try {
      final refs = await _estado.api.subirFotos(widget.empleado.id, _fotos);
      if (widget.empleado.sedeId == _estado.config?.sede.id) {
        setState(() => _progreso = 'Calculando huella facial en este equipo…');
        await _estado.sincronizador?.incorporarEnrolamiento(widget.empleado, refs, _fotos);
      }
      if (!mounted) return;
      avisar(context, 'Rostro de ${widget.empleado.nombre} registrado');
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _etapa = _Etapa.revision);
      avisar(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Hud.fondo,
        body: switch (_etapa) {
          _Etapa.camara => _vistaCamara(),
          _ => _vistaRevision(),
        },
      ),
    );
  }

  Widget _vistaCamara() {
    final c = _camara.controlador;
    final color = _error != null ? Hud.peligro : (_guiaOk ? Hud.entrada : Hud.cian);
    final yaw = _rostro?.headEulerAngleY;
    return LayoutBuilder(builder: (context, caja) {
      final mapa = _tamano != null && c != null
          ? MapaPantalla(imagen: _tamano!, pantalla: caja.biggest, espejo: _camara.espejarHud)
          : null;
      return Stack(
        children: [
          if (c != null && _camara.lista) Positioned.fill(child: ExcludeSemantics(child: VistaCamara(controlador: c))),
          Positioned.fill(
            child: HudBiometrico(
              color: color,
              rostro: _rostro,
              mapa: mapa,
              segmentos: Constantes.fotosEnrolamiento,
              completados: _paso,
              pulso: _destello,
              lecturaSuperior: 'ENROLAMIENTO › ${(_paso + 1).clamp(1, 3)}/${Constantes.fotosEnrolamiento}',
              lecturaDerecha: yaw == null ? null : 'YAW ${yaw >= 0 ? '+' : ''}${yaw.toStringAsFixed(0)}°',
              lecturaInferior: 'ID #${widget.empleado.id.toString().padLeft(4, '0')}',
            ),
          ),
          // Destello de captura.
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_destello),
                tween: Tween(begin: _destello == 0 ? 0 : 0.55, end: 0),
                duration: const Duration(milliseconds: 350),
                builder: (_, v, _) => ColoredBox(color: Colors.white.withValues(alpha: v)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Espacio.xs, Espacio.xs, Espacio.md, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        tooltip: 'Cancelar',
                        icon: const Icon(Icons.close_rounded, color: Hud.texto),
                      ),
                      const SizedBox(width: Espacio.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('REGISTRO FACIAL', style: Hud.mono(tam: 11, color: Hud.cian, peso: FontWeight.w700, espaciado: 2)),
                            Text(widget.empleado.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Hud.titulo(tam: 20)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(Espacio.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Semantics(
                      liveRegion: true,
                      child: PanelVidrio(
                        color: color,
                        child: _error != null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!, style: Hud.cuerpo(tam: 16)),
                                  const SizedBox(height: Espacio.md),
                                  OutlinedButton(onPressed: _iniciarCamara, child: const Text('Reintentar')),
                                ],
                              )
                            : Row(
                                children: [
                                  _Pasos(actual: _paso),
                                  const SizedBox(width: Espacio.md),
                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration: Duraciones.rapida,
                                      child: Text(
                                        _guia,
                                        key: ValueKey(_guia),
                                        style: Hud.cuerpo(tam: 19, peso: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _vistaRevision() {
    final guardando = _etapa == _Etapa.guardando;
    return FondoTecnico(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Etiqueta('Revisión', color: Hud.cian),
              const SizedBox(height: Espacio.xs),
              Text('¿Las fotos se ven bien?', style: Hud.titulo(tam: 28)),
              const SizedBox(height: Espacio.xs),
              Text(
                'Rostro descubierto, buena luz y sin otras personas. Estas fotos se usarán en todos los kioscos de la sede.',
                style: Hud.cuerpo(tam: 15, color: Hud.textoSuave, peso: FontWeight.w500),
              ),
              const SizedBox(height: Espacio.lg),
              Row(
                children: [
                  for (var i = 0; i < _fotos.length; i++) ...[
                    if (i > 0) const SizedBox(width: Espacio.sm),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Redondeo.lg),
                            border: Border.all(color: Hud.panelBorde),
                            boxShadow: [BoxShadow(color: Hud.cian.withValues(alpha: 0.18), blurRadius: 18)],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Redondeo.lg),
                            child: Image.memory(_fotos[i], fit: BoxFit.cover, semanticLabel: 'Foto ${i + 1}'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_duplicado != null) ...[
                const SizedBox(height: Espacio.lg),
                PanelVidrio(
                  color: Hud.alerta,
                  radio: Redondeo.lg,
                  padding: const EdgeInsets.all(Espacio.md),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Hud.alerta),
                      const SizedBox(width: Espacio.sm),
                      Expanded(
                        child: Text(
                          'Este rostro se parece a ${_duplicado!.nombre} '
                          '(${(_duplicado!.similitud * 100).toStringAsFixed(0)} %). '
                          'Verifica que sea la persona correcta antes de guardar.',
                          style: Hud.cuerpo(tam: 14, peso: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              if (guardando) ...[
                Text(_progreso ?? '', textAlign: TextAlign.center, style: Hud.cuerpo(tam: 15, color: Hud.textoSuave)),
                const SizedBox(height: Espacio.sm),
                const LinearProgressIndicator(color: Hud.cian, backgroundColor: Hud.cianTenue),
                const SizedBox(height: Espacio.lg),
              ],
              FilledButton.icon(
                onPressed: guardando ? null : _guardar,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Guardar rostro'),
                style: FilledButton.styleFrom(backgroundColor: Hud.cian, foregroundColor: Hud.fondo),
              ),
              const SizedBox(height: Espacio.sm),
              OutlinedButton.icon(
                onPressed: guardando ? null : _repetir,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Repetir fotos'),
                style: OutlinedButton.styleFrom(foregroundColor: Hud.texto, side: const BorderSide(color: Hud.linea)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pasos extends StatelessWidget {
  const _Pasos({required this.actual});
  final int actual;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Foto ${(actual + 1).clamp(1, 3)} de ${Constantes.fotosEnrolamiento}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < Constantes.fotosEnrolamiento; i++)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < actual ? Hud.entrada : (i == actual ? Hud.cian : Colors.transparent),
                border: Border.all(color: i <= actual ? Colors.transparent : Hud.linea),
                boxShadow: i == actual ? [BoxShadow(color: Hud.cian.withValues(alpha: 0.7), blurRadius: 8)] : null,
              ),
            ),
        ],
      ),
    );
  }
}
