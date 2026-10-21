import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../../servicios/sincronizador.dart';
import '../comun/camara.dart';
import '../comun/hud.dart';
import '../comun/widgets.dart';
import 'controlador_kiosco.dart';
import 'paneles_kiosco.dart';

/// Marcación: la persona mira la cámara y queda registrada.
///
/// Solo se abre desde «Marcar asistencia» en un teléfono vinculado, y se
/// cierra sola tras registrar o tras [inactividad] sin nadie frente a la
/// cámara: así la cámara no queda encendida todo el día.
class KioscoPage extends StatefulWidget {
  const KioscoPage({super.key});

  static const inactividad = Duration(seconds: 20);

  @override
  State<KioscoPage> createState() => _KioscoPageState();
}

class _KioscoPageState extends State<KioscoPage> with WidgetsBindingObserver {
  late final ControladorKiosco _k = ControladorKiosco(context.read<EstadoApp>());
  late final Timer _vigia;
  DateTime _ultimaActividad = DateTime.now();
  late int _pulsosVistos = _k.pulsos;
  bool _cerrando = false;

  /// Fases en las que alguien está frente a la cámara.
  static const _conPersona = {
    FaseKiosco.ajustando,
    FaseKiosco.vivacidad,
    FaseKiosco.analizando,
    FaseKiosco.identificado,
    FaseKiosco.registrado,
    FaseKiosco.repetido,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _modoKiosco();
    WakelockPlus.enable();
    _k.addListener(_alCambiar);
    _vigia = Timer.periodic(const Duration(seconds: 1), (_) => _vigilar());
    _k.iniciar();
  }

  @override
  void dispose() {
    _vigia.cancel();
    _k.removeListener(_alCambiar);
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _k.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      _k.pausar();
    } else if (s == AppLifecycleState.resumed) {
      _modoKiosco();
      _ultimaActividad = DateTime.now();
      _k.iniciar();
      context.read<EstadoApp>().sincronizador?.sincronizar();
    }
  }

  void _modoKiosco() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  void _alCambiar() {
    if (_k.rostro != null || _conPersona.contains(_k.fase)) _ultimaActividad = DateTime.now();
    if (_k.pulsos != _pulsosVistos) {
      // Registró: se deja ver la confirmación y se apaga la cámara.
      _pulsosVistos = _k.pulsos;
      _cerrar(tras: const Duration(milliseconds: 3400));
    } else if (_k.fase == FaseKiosco.repetido) {
      _cerrar(tras: const Duration(seconds: 4));
    }
  }

  void _vigilar() {
    if (DateTime.now().difference(_ultimaActividad) >= KioscoPage.inactividad) _cerrar();
  }

  Future<void> _cerrar({Duration tras = Duration.zero}) async {
    if (_cerrando) return;
    _cerrando = true;
    if (tras > Duration.zero) await Future<void>.delayed(tras);
    await _k.pausar();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<Sincronizador>();
    final estado = context.read<EstadoApp>();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Hud.fondo,
        body: ListenableBuilder(
          listenable: _k,
          builder: (context, _) {
            final acento = colorFase(_k);
            final controlador = _k.camara.controlador;
            return LayoutBuilder(builder: (context, caja) {
              final pantalla = caja.biggest;
              final mapa = (_k.tamanoImagen != null && controlador != null)
                  ? MapaPantalla(imagen: _k.tamanoImagen!, pantalla: pantalla, espejo: _k.camara.espejarHud)
                  : null;
              return Stack(
                children: [
                  if (controlador != null && _k.camara.lista)
                    Positioned.fill(child: ExcludeSemantics(child: VistaCamara(controlador: controlador))),
                  Positioned.fill(
                    child: HudBiometrico(
                      color: acento,
                      rostro: _k.fase.aceptaCuadros || _k.fase == FaseKiosco.identificado ? _k.rostro : null,
                      mapa: mapa,
                      escaneando: _k.fase.escaneando,
                      pulso: _k.pulsos,
                      lecturaSuperior: 'BIO·SCAN › ${_etiquetaFase(_k.fase)}',
                      lecturaDerecha: _k.similitud > 0 &&
                              (_k.fase == FaseKiosco.analizando ||
                                  _k.fase == FaseKiosco.vivacidad ||
                                  _k.fase == FaseKiosco.identificado)
                          ? 'MATCH ${(_k.similitud * 100).clamp(0, 99.9).toStringAsFixed(1)}%'
                          : null,
                      lecturaInferior: 'ROSTROS ${sync.reconocibles.toString().padLeft(3, '0')} · '
                          '${estado.config?.sede.codigo ?? '--'}',
                    ),
                  ),
                  SafeArea(
                    child: Column(
                      children: [
                        EncabezadoKiosco(
                          sede: estado.config?.sede.nombre ?? '',
                          sync: sync,
                          alCerrar: _cerrar,
                        ),
                        if (sync.relojDesfasado) AvisoReloj(desfase: sync.desfaseReloj!),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Espacio.md, 0, Espacio.md, Espacio.md),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: AnimatedSwitcher(
                              duration: Duraciones.media,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (hijo, anim) => FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(anim),
                                  child: hijo,
                                ),
                              ),
                              child: PanelFase(key: ValueKey(_claveFase()), k: _k, sync: sync),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_k.fase == FaseKiosco.registrado && _k.registrada != null && _k.empleado != null)
                    Positioned.fill(
                      child: PantallaRegistrado(
                        empleado: _k.empleado!,
                        marcacion: _k.registrada!,
                        enLinea: sync.enLinea,
                        puntualidad: _k.puntualidad,
                      ),
                    ),
                ],
              );
            });
          },
        ),
      ),
    );
  }

  /// Cambia el panel solo cuando cambia su contenido (evita parpadeos).
  String _claveFase() => switch (_k.fase) {
        FaseKiosco.ajustando => 'ajustando',
        FaseKiosco.identificado => 'identificado-${_k.empleado?.id}',
        FaseKiosco.error => 'error-${_k.error}',
        _ => _k.fase.name,
      };

  String _etiquetaFase(FaseKiosco f) => switch (f) {
        FaseKiosco.iniciando => 'INICIANDO',
        FaseKiosco.esperando => 'BUSCANDO',
        FaseKiosco.ajustando => 'ALINEANDO',
        FaseKiosco.vivacidad => 'VIVACIDAD',
        FaseKiosco.analizando => 'ANALIZANDO',
        FaseKiosco.identificado => 'IDENTIFICADO',
        FaseKiosco.registrado => 'REGISTRADO',
        FaseKiosco.repetido => 'DUPLICADO',
        FaseKiosco.desconocido => 'SIN COINCIDENCIA',
        FaseKiosco.sinRostros => 'SIN BASE',
        FaseKiosco.error => 'ERROR',
      };
}

Color colorFase(ControladorKiosco k) => switch (k.fase) {
      FaseKiosco.ajustando || FaseKiosco.repetido => Hud.alerta,
      FaseKiosco.identificado || FaseKiosco.registrado => k.tipo == TipoMarcacion.entrada ? Hud.entrada : Hud.salida,
      FaseKiosco.desconocido || FaseKiosco.error => Hud.peligro,
      _ => Hud.cian,
    };

/// Cabecera: sede, reloj grande, estado de sincronización y cerrar (apaga la cámara).
class EncabezadoKiosco extends StatelessWidget {
  const EncabezadoKiosco({super.key, required this.sede, required this.sync, required this.alCerrar});

  final String sede;
  final Sincronizador sync;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.lg, Espacio.md, Espacio.xs, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEDE · ${sede.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Hud.mono(tam: 12, color: Hud.cian, peso: FontWeight.w700, espaciado: 2),
                ),
                const SizedBox(height: Espacio.xxs),
                const RelojVivo(),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: alCerrar,
                tooltip: 'Cerrar y apagar la cámara',
                icon: const Icon(Icons.close_rounded, color: Hud.textoSuave),
              ),
              EstadoSync(sync: sync),
            ],
          ),
        ],
      ),
    );
  }
}

class RelojVivo extends StatefulWidget {
  const RelojVivo({super.key});

  @override
  State<RelojVivo> createState() => _RelojVivoState();
}

class _RelojVivoState extends State<RelojVivo> {
  late Timer _t;
  DateTime _ahora = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _ahora = DateTime.now()));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hora actual ${Formato.hora(_ahora)}, ${Formato.fechaLarga(_ahora)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formato.reloj(_ahora),
                style: Hud.titulo(tam: 52, peso: FontWeight.w600).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: Hud.brillo(Hud.cian, radio: 18),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 9),
                child: Text(
                  _ahora.second.toString().padLeft(2, '0'),
                  style: Hud.mono(tam: 16, color: Hud.cian, peso: FontWeight.w700),
                ),
              ),
            ],
          ),
          Text(Formato.fechaLarga(_ahora), style: Hud.cuerpo(tam: 15, color: Hud.textoSuave, peso: FontWeight.w500)),
        ],
      ),
    );
  }
}

class EstadoSync extends StatelessWidget {
  const EstadoSync({super.key, required this.sync});
  final Sincronizador sync;

  @override
  Widget build(BuildContext context) {
    final p = sync.progresoRostros;
    final (texto, color, icono) = switch (sync) {
      _ when p != null => ('Rostros ${p.hechos}/${p.total}', Hud.cian, Icons.memory_rounded),
      _ when !sync.enLinea && sync.pendientes > 0 =>
        ('Sin conexión · ${sync.pendientes} en cola', Hud.alerta, Icons.cloud_off_rounded),
      _ when !sync.enLinea => ('Sin conexión', Hud.alerta, Icons.cloud_off_rounded),
      _ when sync.pendientes > 0 => ('${sync.pendientes} por enviar', Hud.cian, Icons.cloud_upload_outlined),
      _ => ('En línea', Hud.entrada, Icons.cloud_done_outlined),
    };
    return Padding(
      padding: const EdgeInsets.only(right: Espacio.sm),
      child: Pildora(texto: texto, color: color, fondo: Hud.panel, icono: icono),
    );
  }
}

class AvisoReloj extends StatelessWidget {
  const AvisoReloj({super.key, required this.desfase});
  final Duration desfase;

  @override
  Widget build(BuildContext context) {
    final minutos = (desfase.inSeconds.abs() / 60).ceil();
    final sentido = desfase.isNegative ? 'adelantada' : 'atrasada';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.sm, Espacio.md, 0),
      child: PanelVidrio(
        color: Hud.alerta,
        radio: Redondeo.md,
        padding: const EdgeInsets.symmetric(horizontal: Espacio.md, vertical: Espacio.sm),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, color: Hud.alerta, size: 20),
            const SizedBox(width: Espacio.sm),
            Expanded(
              child: Text(
                'La hora de este equipo está $sentido ~$minutos min. Ajústala en la configuración del teléfono.',
                style: Hud.cuerpo(tam: 13, color: Hud.texto, peso: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
