import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constantes.dart';
import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../servicios/asistencia.dart';
import '../../servicios/sincronizador.dart';
import '../comun/widgets.dart';
import 'controlador_kiosco.dart';

/// Panel inferior del kiosco: cambia según la fase del reconocimiento.
class PanelFase extends StatelessWidget {
  const PanelFase({super.key, required this.k, required this.sync, required this.alAdministrar});

  final ControladorKiosco k;
  final Sincronizador sync;
  final VoidCallback alAdministrar;

  @override
  Widget build(BuildContext context) {
    switch (k.fase) {
      case FaseKiosco.iniciando:
        return const _Instruccion(
          icono: Icons.videocam_outlined,
          titulo: 'Iniciando cámara…',
          detalle: 'Preparando el sistema biométrico',
          cargando: true,
        );
      case FaseKiosco.esperando:
        return const _Instruccion(
          icono: Icons.face_retouching_natural_rounded,
          titulo: 'Acércate y mira a la cámara',
          detalle: 'Registro de entrada y salida por reconocimiento facial',
        );
      case FaseKiosco.ajustando:
        return _Instruccion(icono: Icons.center_focus_weak_rounded, titulo: k.guia, color: Hud.alerta);
      case FaseKiosco.analizando:
        return const _Instruccion(
          icono: Icons.radar_rounded,
          titulo: 'Analizando rostro…',
          detalle: 'Quédate quieto un instante',
          cargando: true,
        );
      case FaseKiosco.vivacidad:
        return const _Instruccion(
          icono: Icons.visibility_outlined,
          titulo: 'Parpadea para confirmar',
          detalle: 'Prueba de vida: evita registros con fotos',
          latido: true,
        );
      case FaseKiosco.sinRostros:
        final p = sync.progresoRostros;
        return _Instruccion(
          icono: Icons.group_add_outlined,
          titulo: p != null ? 'Preparando rostros ${p.hechos} de ${p.total}' : 'Aún no hay rostros registrados',
          detalle: p != null
              ? 'Descargando y procesando el personal de la sede'
              : 'Un administrador debe registrar al personal de esta sede.',
          cargando: p != null || sync.sincronizando,
          accion: p == null ? ('Administrar', alAdministrar) : null,
        );
      case FaseKiosco.identificado:
        return TarjetaIdentificado(k: k);
      case FaseKiosco.registrado:
        return const SizedBox.shrink();
      case FaseKiosco.repetido:
        final u = k.ultima;
        return _Instruccion(
          icono: Icons.history_toggle_off_rounded,
          color: Hud.alerta,
          titulo: u == null
              ? 'Ya registraste tu marcación'
              : 'Ya registraste tu ${u.tipo.etiqueta.toLowerCase()} a las ${Formato.hora(u.hora)}',
          detalle: 'No es necesario volver a marcar, ${Formato.primerNombre(k.empleado?.nombre ?? '')}.',
        );
      case FaseKiosco.desconocido:
        return _Instruccion(
          icono: Icons.person_off_outlined,
          color: Hud.peligro,
          titulo: 'No te reconocemos',
          detalle: 'Si eres nuevo, pide a un administrador que registre tu rostro.',
          accion: ('Intentar de nuevo', k.reintentar),
        );
      case FaseKiosco.error:
        if (k.error == 'modelo') {
          return _Instruccion(
            icono: Icons.memory_rounded,
            color: Hud.peligro,
            titulo: 'Falta el modelo de reconocimiento',
            detalle: 'Agrega ${Constantes.rutaModelo} a la app (ver README).',
            accion: ('Administrar', alAdministrar),
          );
        }
        return _Instruccion(
          icono: Icons.no_photography_outlined,
          color: Hud.peligro,
          titulo: 'Cámara no disponible',
          detalle: k.error,
          accion: ('Reintentar', () => k.iniciar()),
        );
    }
  }
}

class _Instruccion extends StatelessWidget {
  const _Instruccion({
    required this.icono,
    required this.titulo,
    this.detalle,
    this.color = Hud.cian,
    this.cargando = false,
    this.latido = false,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String? detalle;
  final Color color;
  final bool cargando;
  final bool latido;
  final (String, VoidCallback)? accion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: PanelVidrio(
        color: color,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _IconoNeon(icono: icono, color: color, latido: latido),
                const SizedBox(width: Espacio.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: Hud.cuerpo(tam: 20, peso: FontWeight.w700)),
                      if (detalle != null) ...[
                        const SizedBox(height: Espacio.xxs),
                        Text(detalle!, style: Hud.cuerpo(tam: 14, color: Hud.textoSuave, peso: FontWeight.w500)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (cargando) ...[
              const SizedBox(height: Espacio.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ],
            if (accion != null) ...[
              const SizedBox(height: Espacio.md),
              OutlinedButton(
                onPressed: accion!.$2,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.7)),
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(accion!.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconoNeon extends StatelessWidget {
  const _IconoNeon({required this.icono, required this.color, this.latido = false});
  final IconData icono;
  final Color color;
  final bool latido;

  @override
  Widget build(BuildContext context) {
    final caja = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16)],
      ),
      child: ExcludeSemantics(child: Icon(icono, color: color, size: 26)),
    );
    if (!latido || context.sinMovimiento) return caja;
    return _Latido(child: caja);
  }
}

class _Latido extends StatefulWidget {
  const _Latido({required this.child});
  final Widget child;

  @override
  State<_Latido> createState() => _LatidoState();
}

class _LatidoState extends State<_Latido> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.06).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: widget.child,
      );
}

/// Tarjeta "¿Eres tú?": muestra quién se reconoció y registra con un toque
/// (o sola, al terminar la cuenta regresiva).
class TarjetaIdentificado extends StatelessWidget {
  const TarjetaIdentificado({super.key, required this.k});
  final ControladorKiosco k;

  @override
  Widget build(BuildContext context) {
    final e = k.empleado!;
    final sugerido = k.tipo;
    final otro = sugerido.opuesto;
    final color = _colorTipo(sugerido);
    return PanelVidrio(
      color: color,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AvatarEmpleado(nombre: e.nombre, archivo: e.rutaFoto, tam: 68, anillo: color),
              const SizedBox(width: Espacio.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IDENTIDAD CONFIRMADA', style: Hud.mono(tam: 11, color: color, peso: FontWeight.w700, espaciado: 1.8)),
                    const SizedBox(height: 2),
                    Text(e.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: Hud.titulo(tam: 24)),
                    if (e.cargo != null && e.cargo!.isNotEmpty)
                      Text(e.cargo!, style: Hud.cuerpo(tam: 14, color: Hud.textoSuave, peso: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          if (e.turnoDe(DateTime.now()) != null) ...[
            const SizedBox(height: Espacio.sm),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 16, color: Hud.cian),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'TURNO HOY  ${Formato.bloques(e.turnoHoy!)}',
                    style: Hud.mono(tam: 12, color: Hud.texto, peso: FontWeight.w600, espaciado: 0.6),
                  ),
                ),
              ],
            ),
          ],
          if (k.ultima != null) ...[
            const SizedBox(height: Espacio.xs),
            Text(
              'Última marcación hoy: ${k.ultima!.tipo.etiqueta.toLowerCase()} a las ${Formato.hora(k.ultima!.hora)}',
              style: Hud.cuerpo(tam: 13, color: Hud.textoSuave, peso: FontWeight.w500),
            ),
          ],
          const SizedBox(height: Espacio.md),
          _BotonCuentaAtras(
            etiqueta: 'Registrar ${sugerido.etiqueta.toUpperCase()}',
            icono: sugerido == TipoMarcacion.entrada ? Icons.login_rounded : Icons.logout_rounded,
            color: color,
            restante: k.segundosRestantes,
            total: Constantes.segundosAutoConfirmar,
            alPulsar: () => k.confirmar(sugerido),
          ),
          const SizedBox(height: Espacio.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => k.confirmar(otro),
                  icon: Icon(otro == TipoMarcacion.entrada ? Icons.login_rounded : Icons.logout_rounded, size: 20),
                  label: Text('Es ${otro.etiqueta.toLowerCase()}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _colorTipo(otro),
                    side: BorderSide(color: _colorTipo(otro).withValues(alpha: 0.6)),
                  ),
                ),
              ),
              const SizedBox(width: Espacio.sm),
              Expanded(
                child: TextButton(
                  onPressed: k.descartar,
                  style: TextButton.styleFrom(foregroundColor: Hud.textoSuave, minimumSize: const Size(0, 52)),
                  child: const Text('No soy yo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _colorTipo(TipoMarcacion t) => t == TipoMarcacion.entrada ? Hud.entrada : Hud.salida;

class _BotonCuentaAtras extends StatelessWidget {
  const _BotonCuentaAtras({
    required this.etiqueta,
    required this.icono,
    required this.color,
    required this.restante,
    required this.total,
    required this.alPulsar,
  });

  final String etiqueta;
  final IconData icono;
  final Color color;
  final int restante;
  final int total;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$etiqueta. Se registrará automáticamente en $restante segundos',
      excludeSemantics: true,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(Redondeo.md),
        child: InkWell(
          onTap: alPulsar,
          borderRadius: BorderRadius.circular(Redondeo.md),
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icono, color: Hud.fondo, size: 24),
                const SizedBox(width: Espacio.sm),
                Flexible(
                  child: Text(etiqueta, style: Hud.cuerpo(tam: 18, color: Hud.fondo, peso: FontWeight.w800)),
                ),
                const SizedBox(width: Espacio.md),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: restante / total),
                        duration: const Duration(milliseconds: 950),
                        builder: (_, v, _) => CircularProgressIndicator(
                          value: v,
                          strokeWidth: 3,
                          color: Hud.fondo,
                          backgroundColor: Hud.fondo.withValues(alpha: 0.2),
                        ),
                      ),
                      Text('$restante', style: Hud.mono(tam: 13, color: Hud.fondo, peso: FontWeight.w800, espaciado: 0)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirmación a pantalla completa tras registrar.
class PantallaRegistrado extends StatelessWidget {
  const PantallaRegistrado({
    super.key,
    required this.empleado,
    required this.marcacion,
    required this.enLinea,
    this.puntualidad,
  });

  final EmpleadoLocal empleado;
  final Marcacion marcacion;
  final bool enLinea;
  final Puntualidad? puntualidad;

  String _saludo() {
    final nombre = Formato.primerNombre(empleado.nombre);
    final h = marcacion.hora.toLocal().hour;
    if (marcacion.tipo == TipoMarcacion.salida) {
      return h < 15 ? '¡Hasta luego, $nombre!' : '¡Buen descanso, $nombre!';
    }
    if (h < 12) return '¡Buenos días, $nombre!';
    if (h < 19) return '¡Buenas tardes, $nombre!';
    return '¡Buenas noches, $nombre!';
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorTipo(marcacion.tipo);
    return Semantics(
      liveRegion: true,
      label: '${_saludo()} ${marcacion.tipo.etiqueta} registrada a las ${Formato.hora(marcacion.hora)}. '
          '${puntualidad?.texto ?? ''}',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: context.sinMovimiento ? Duration.zero : const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Hud.fondo.withValues(alpha: 0.86),
              gradient: RadialGradient(
                center: const Alignment(0, -0.15),
                radius: 1.1,
                colors: [
                  Color.alphaBlend(color.withValues(alpha: 0.22), Hud.fondo.withValues(alpha: 0.88)),
                  Hud.fondo.withValues(alpha: 0.96),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(Espacio.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 148,
                        height: 148,
                        child: CustomPaint(painter: _PintorCheck(progreso: t, color: color)),
                      ),
                      const SizedBox(height: Espacio.lg),
                      Text(
                        _saludo(),
                        textAlign: TextAlign.center,
                        style: Hud.titulo(tam: 34).copyWith(shadows: Hud.brillo(color, radio: 22)),
                      ),
                      const SizedBox(height: Espacio.md),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Espacio.md, vertical: Espacio.xs),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: color.withValues(alpha: 0.7)),
                          color: color.withValues(alpha: 0.12),
                        ),
                        child: Text(
                          '${marcacion.tipo.etiqueta.toUpperCase()} · ${Formato.horaConSegundos(marcacion.hora)}',
                          style: Hud.mono(tam: 16, color: color, peso: FontWeight.w700, espaciado: 1.5),
                        ),
                      ),
                      if (puntualidad != null) ...[
                        const SizedBox(height: Espacio.sm),
                        _PildoraPuntualidad(puntualidad!),
                      ],
                      const SizedBox(height: Espacio.md),
                      Text(
                        enLinea ? 'Registro guardado' : 'Guardado en el equipo · se enviará al volver la conexión',
                        textAlign: TextAlign.center,
                        style: Hud.cuerpo(tam: 15, color: Hud.textoSuave, peso: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PildoraPuntualidad extends StatelessWidget {
  const _PildoraPuntualidad(this.p);
  final Puntualidad p;

  @override
  Widget build(BuildContext context) {
    final color = p.aTiempo ? Hud.entrada : Hud.alerta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espacio.md, vertical: Espacio.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Hud.panel,
        border: Border.all(color: color.withValues(alpha: 0.8)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 16)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(p.aTiempo ? Icons.verified_rounded : Icons.timer_outlined, color: color, size: 20),
          const SizedBox(width: Espacio.xs),
          Flexible(child: Text(p.texto, style: Hud.cuerpo(tam: 16, color: color, peso: FontWeight.w700))),
        ],
      ),
    );
  }
}

/// Círculo + visto que se dibujan progresivamente.
class _PintorCheck extends CustomPainter {
  _PintorCheck({required this.progreso, required this.color});
  final double progreso;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    final halo = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(c, r, halo);

    final trazo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = color;
    final pc = (progreso / 0.6).clamp(0.0, 1.0);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 2 * pc, false, trazo);

    final pv = ((progreso - 0.45) / 0.55).clamp(0.0, 1.0);
    if (pv > 0) {
      final camino = Path()
        ..moveTo(c.dx - r * 0.42, c.dy + r * 0.02)
        ..lineTo(c.dx - r * 0.10, c.dy + r * 0.34)
        ..lineTo(c.dx + r * 0.46, c.dy - r * 0.30);
      final medida = camino.computeMetrics().first;
      canvas.drawPath(medida.extractPath(0, medida.length * pv), trazo..strokeWidth = 7);
    }
  }

  @override
  bool shouldRepaint(_PintorCheck v) => v.progreso != progreso || v.color != color;
}
