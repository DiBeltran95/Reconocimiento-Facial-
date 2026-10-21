// Estudio de capturas: renderiza las pantallas reales con datos de ejemplo
// para revisar el diseño sin un teléfono. No forma parte de `flutter test`.
//
//   flutter test test_capturas --update-goldens
//
// Las imágenes quedan en test_capturas/goldens/.
import 'dart:io';
import 'dart:math' as math;

import 'package:control_personal/core/tema.dart';
import 'package:control_personal/data/api.dart';
import 'package:control_personal/data/modelos.dart';
import 'package:control_personal/servicios/asistencia.dart';
import 'package:control_personal/servicios/sincronizador.dart';
import 'package:control_personal/ui/admin/asistencia_page.dart';
import 'package:control_personal/ui/admin/contexto_admin.dart';
import 'package:control_personal/ui/admin/cumplimiento_vista.dart';
import 'package:control_personal/ui/comun/camara.dart';
import 'package:control_personal/ui/comun/hud.dart';
import 'package:control_personal/ui/horarios/horarios_page.dart';
import 'package:control_personal/ui/horarios/plan_empleado.dart';
import 'package:control_personal/ui/horarios/turno_form_page.dart';
import 'package:control_personal/ui/comun/widgets.dart';
import 'package:control_personal/ui/inicio/inicio_page.dart';
import 'package:control_personal/ui/kiosco/controlador_kiosco.dart';
import 'package:control_personal/ui/kiosco/kiosco_page.dart';
import 'package:control_personal/ui/kiosco/paneles_kiosco.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

const _tam = Size(412, 915);

Future<void> _cargarFuentes() async {
  final raiz = Platform.environment['FLUTTER_ROOT']!; // lo define `flutter test`
  final dir = '$raiz/bin/cache/artifacts/material_fonts';
  Future<void> registrar(String familia, String archivo) async {
    final bytes = File('$dir/$archivo').readAsBytesSync();
    final loader = FontLoader(familia)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await registrar('MaterialIcons', 'materialicons-regular.otf');
  final pesos = {
    'regular': 'roboto-regular.ttf', '400': 'roboto-regular.ttf', '500': 'roboto-medium.ttf',
    '600': 'roboto-medium.ttf', '700': 'roboto-bold.ttf', '800': 'roboto-black.ttf', '300': 'roboto-light.ttf',
  };
  for (final familia in ['PlusJakartaSans', 'SpaceGrotesk']) {
    for (final e in pesos.entries) {
      await registrar('${familia}_${e.key}', e.value);
    }
  }
  for (final e in pesos.entries) {
    await registrar('JetBrainsMono_${e.key}', e.value.replaceFirst('roboto-', 'robotocondensed-').replaceFirst('black', 'bold').replaceFirst('medium', 'regular'));
  }
}

Widget _app(Widget hijo, {Brightness brillo = Brightness.dark}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: construirTema(brillo),
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: hijo,
    );

Future<void> _capturar(WidgetTester t, String nombre, Widget w, {int pasos = 6}) async {
  t.view.physicalSize = _tam * 2;
  t.view.devicePixelRatio = 2;
  await t.pumpWidget(w);
  for (var i = 0; i < pasos; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$nombre.png'));
  await t.pumpWidget(const SizedBox());
  t.view.reset();
}

// ---------------------------------------------------------------------------
// Dobles de prueba
// ---------------------------------------------------------------------------

class _SyncFalso extends ChangeNotifier implements Sincronizador {
  @override
  bool enLinea = true;
  @override
  int pendientes = 0;
  @override
  int reconocibles = 24;
  @override
  int empleados = 26;
  @override
  bool sincronizando = false;
  @override
  ({int hechos, int total})? progresoRostros;
  @override
  Duration? desfaseReloj;
  @override
  bool get relojDesfasado => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _KioscoFalso extends ChangeNotifier implements ControladorKiosco {
  @override
  FaseKiosco fase = FaseKiosco.esperando;
  @override
  String guia = '';
  @override
  String? error;
  @override
  Face? rostro;
  @override
  Size? tamanoImagen;
  @override
  double similitud = 0;
  @override
  EmpleadoLocal? empleado;
  @override
  TipoMarcacion tipo = TipoMarcacion.entrada;
  @override
  Marcacion? ultima;
  @override
  Marcacion? registrada;
  @override
  Puntualidad? puntualidad;
  @override
  int segundosRestantes = 3;
  @override
  int pulsos = 0;
  @override
  Future<void> iniciar() async {}
  @override
  Future<void> pausar() async {}
  @override
  Future<void> confirmar(TipoMarcacion t) async {}
  @override
  void descartar() {}
  @override
  void reintentar() {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// API con respuestas de ejemplo con la MISMA forma que el backend PHP.
class _ApiFalsa extends Api {
  _ApiFalsa() : super(baseUrl: 'https://ejemplo.invalid');

  static const _turnos = [
    {'id': 1, 'nombre': 'Turno A', 'bloques': '08:30-12:00,14:00-18:00', 'dias': 63, 'tolerancia_min': 10, 'activo': true},
    {'id': 2, 'nombre': 'Turno B', 'bloques': '10:30-14:00,16:00-21:00', 'dias': 63, 'tolerancia_min': 10, 'activo': true},
    {'id': 3, 'nombre': 'Continuo', 'bloques': '07:00-15:00', 'dias': 31, 'tolerancia_min': 5, 'activo': true},
  ];

  @override
  Future<List<Sede>> sedes({bool todas = false}) async =>
      [const Sede(id: 1, nombre: 'Sede principal', codigo: 'PRI', esPrincipal: true)];

  @override
  Future<List<Horario>> horarios() async => _turnos.map(Horario.desdeJson).toList();

  @override
  Future<PlanEmpleado> planEmpleado(int empleadoId, {int semanas = 8}) async => PlanEmpleado.desdeJson({
        'rotacion': {'desde': '2026-09-28', 'secuencia': [1, 2]},
        'semanas': [
          {'semana': '2026-10-05', 'horario': _turnos[1], 'ajustada': false},
          {'semana': '2026-10-12', 'horario': _turnos[0], 'ajustada': false},
          {'semana': '2026-10-19', 'horario': null, 'ajustada': true},
          {'semana': '2026-10-26', 'horario': _turnos[0], 'ajustada': false},
          {'semana': '2026-11-02', 'horario': _turnos[1], 'ajustada': false},
          {'semana': '2026-11-09', 'horario': _turnos[0], 'ajustada': false},
        ],
      });

  @override
  Future<ReporteDia> reporteDia({required int sedeId, required String fecha}) async {
    Map<String, dynamic> fila(int id, String nombre, String cargo, String estado, String? e, String? s, int min,
        Map<String, dynamic>? turno, String cumple, {int retraso = 0, int anticipo = 0}) {
      final marcas = [
        if (e != null) {'tipo': 'ENTRADA', 'hora': '2026-10-08T$e:00-05:00', 'hora_servidor': '2026-10-08T$e:02-05:00', 'desfase_seg': 2},
        if (s != null) {'tipo': 'SALIDA', 'hora': '2026-10-08T$s:00-05:00', 'hora_servidor': '2026-10-08T$s:01-05:00', 'desfase_seg': 1},
      ];
      return {
        'id': id, 'documento': '10${id}55432', 'nombre': nombre, 'cargo': cargo, 'estado': estado,
        'entrada': e == null ? null : '2026-10-08T$e:00-05:00', 'salida': s == null ? null : '2026-10-08T$s:00-05:00',
        'minutos': min, 'abierta_desde': null, 'alertas': <String>[], 'marcaciones': marcas,
        'turno': turno, 'cumplimiento': {
          'estado': cumple, 'programado_min': 450, 'retraso_min': retraso, 'anticipo_min': anticipo, 'parcial': false,
          'bloques': [
            {'inicio': '08:30', 'fin': '12:00', 'llegada': e, 'salida': s, 'retraso_min': retraso, 'anticipo_min': 0, 'estado': retraso > 10 ? 'TARDE' : 'OK'},
            {'inicio': '14:00', 'fin': '18:00', 'llegada': null, 'salida': null, 'retraso_min': 0, 'anticipo_min': 0, 'estado': 'PENDIENTE'},
          ],
        },
      };
    }

    return ReporteDia.desdeJson({
      'fecha': fecha, 'es_hoy': true, 'zona': 'America/Bogota',
      'sede': {'id': 1, 'nombre': 'Sede principal', 'codigo': 'PRI'},
      'resumen': {'total': 7, 'presentes': 5, 'ausentes': 1, 'en_sede': 4, 'sin_salida': 0, 'libres': 1, 'alertas': 0,
        'con_turno': 6, 'cumplen': 3, 'tarde': 2, 'incumplen': 1},
      'empleados': [
        fila(1, 'Ana María Rojas', 'Cajera', 'EN_SEDE', '08:24', null, 0, _turnos[0], 'CUMPLE'),
        fila(2, 'Carlos Pérez', 'Bodega', 'EN_SEDE', '08:52', null, 0, _turnos[0], 'TARDE', retraso: 22),
        fila(3, 'Diana Torres', 'Vendedora', 'SALIO', '08:29', '12:01', 212, _turnos[0], 'CUMPLE'),
        fila(4, 'Jorge Castillo', 'Vendedor', 'EN_SEDE', '10:41', null, 0, _turnos[1], 'TARDE', retraso: 11),
        fila(5, 'Luisa Gómez', 'Supervisora', 'AUSENTE', null, null, 0, _turnos[0], 'AUSENTE'),
        fila(6, 'Pedro Ramírez', 'Mensajero', 'EN_SEDE', '07:58', null, 0, _turnos[2], 'CUMPLE'),
        fila(7, 'Sofía Herrera', 'Auxiliar', 'LIBRE', null, null, 0, null, 'LIBRE'),
      ],
    });
  }

  @override
  Future<ReporteCumplimiento> reporteCumplimiento({required int sedeId, required DateTime desde, required DateTime hasta}) async {
    final fechas = List.generate(7, (i) => '2026-10-0${i + 2}');
    Map<String, dynamic> p(int id, String n, int? pct, List<String?> d, {int tarde = 0, int mt = 0, int aus = 0, int sal = 0}) => {
          'id': id, 'documento': '10$id', 'nombre': n, 'cargo': null, 'porcentaje': pct,
          'dias_programados': d.where((x) => x != null && x != 'LIBRE').length, 'dias_cumplidos': d.where((x) => x == 'CUMPLE').length,
          'tardanzas': tarde, 'minutos_tarde': mt, 'salidas_anticipadas': sal, 'minutos_anticipados': sal * 25,
          'ausencias': aus, 'incompletos': 0, 'sin_salida': 0, 'minutos_programados': 2700, 'minutos_trabajados': 2550,
          'dias': [for (var i = 0; i < 7; i++) {'fecha': fechas[i], 'estado': d[i]}],
        };
    return ReporteCumplimiento.desdeJson({
      'desde': fechas.first, 'hasta': fechas.last, 'dias': fechas,
      'resumen': {'porcentaje': 81, 'dias_programados': 36, 'dias_cumplidos': 29, 'tardanzas': 4, 'ausencias': 2, 'salidas_anticipadas': 1},
      'empleados': [
        p(5, 'Luisa Gómez', 50, ['CUMPLE', 'AUSENTE', 'CUMPLE', 'AUSENTE', 'TARDE', 'CUMPLE', 'LIBRE'], aus: 2, tarde: 1, mt: 14),
        p(2, 'Carlos Pérez', 67, ['TARDE', 'CUMPLE', 'TARDE', 'CUMPLE', 'CUMPLE', 'CUMPLE', 'LIBRE'], tarde: 2, mt: 41),
        p(4, 'Jorge Castillo', 83, ['CUMPLE', 'CUMPLE', 'SALIDA_ANTICIPADA', 'CUMPLE', 'CUMPLE', 'CUMPLE', 'LIBRE'], sal: 1),
        p(1, 'Ana María Rojas', 100, ['CUMPLE', 'CUMPLE', 'CUMPLE', 'CUMPLE', 'CUMPLE', 'CUMPLE', 'LIBRE']),
        p(6, 'Pedro Ramírez', 100, ['CUMPLE', 'CUMPLE', 'CUMPLE', 'CUMPLE', 'CUMPLE', 'LIBRE', 'LIBRE']),
      ],
    });
  }
}

// ---------------------------------------------------------------------------
// Escena del kiosco (cámara simulada + rostro con malla)
// ---------------------------------------------------------------------------

Face _rostro() {
  const cx = 240.0, cy = 285.0, rx = 118.0, ry = 150.0;
  List<math.Point<int>> elipse(double x, double y, double a, double b, int n) => [
        for (var i = 0; i < n; i++)
          math.Point((x + a * math.cos(2 * math.pi * i / n)).round(), (y + b * math.sin(2 * math.pi * i / n)).round()),
      ];
  return Face(
    boundingBox: const Rect.fromLTWH(cx - rx, cy - ry, rx * 2, ry * 2),
    landmarks: const {},
    contours: {
      FaceContourType.face: FaceContour(type: FaceContourType.face, points: elipse(cx, cy, rx, ry, 36)),
      FaceContourType.leftEye: FaceContour(type: FaceContourType.leftEye, points: elipse(cx - 45, cy - 30, 22, 9, 16)),
      FaceContourType.rightEye: FaceContour(type: FaceContourType.rightEye, points: elipse(cx + 45, cy - 30, 22, 9, 16)),
      FaceContourType.upperLipTop: FaceContour(type: FaceContourType.upperLipTop, points: elipse(cx, cy + 70, 38, 10, 11)),
      FaceContourType.noseBridge: FaceContour(type: FaceContourType.noseBridge, points: [for (var i = 0; i < 5; i++) math.Point(cx.round(), (cy - 25 + i * 14).round())]),
      FaceContourType.leftEyebrowTop: FaceContour(type: FaceContourType.leftEyebrowTop, points: [for (var i = 0; i < 5; i++) math.Point((cx - 75 + i * 12).round(), (cy - 58 - math.sin(i / 4 * math.pi) * 8).round())]),
      FaceContourType.rightEyebrowTop: FaceContour(type: FaceContourType.rightEyebrowTop, points: [for (var i = 0; i < 5; i++) math.Point((cx + 27 + i * 12).round(), (cy - 58 - math.sin(i / 4 * math.pi) * 8).round())]),
    },
  );
}

class _CamaraSimulada extends StatelessWidget {
  const _CamaraSimulada();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PintorPersona(), size: Size.infinite);
}

class _PintorPersona extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    // Fondo de oficina desenfocado con luces cálidas (bokeh).
    c.drawRect(Offset.zero & s, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF2E3D55), Color(0xFF131B2B)]).createShader(Offset.zero & s));
    for (final (x, y, r, col) in [
      (0.12, 0.18, 70.0, const Color(0x33FBBF24)), (0.85, 0.12, 90.0, const Color(0x2922D3EE)),
      (0.9, 0.55, 60.0, const Color(0x22A78BFA)), (0.08, 0.6, 80.0, const Color(0x1F60A5FA)),
    ]) {
      c.drawCircle(Offset(s.width * x, s.height * y), r, Paint()..color = col..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    }
    // Silueta anónima con luz de borde (se lee como "persona" sin mostrar un rostro real).
    final cara = Offset(s.width / 2, s.height * 0.40);
    final silueta = Path.combine(
      PathOperation.union,
      Path.combine(
        PathOperation.union,
        Path()..addOval(Rect.fromCenter(center: cara, width: 205, height: 262)),
        Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: cara.translate(0, 150), width: 96, height: 110), const Radius.circular(36))),
      ),
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.80), width: 460, height: 400), const Radius.circular(190))),
    );
    c.drawPath(silueta, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF4A5D7A), Color(0xFF1B2638)]).createShader(Rect.fromLTWH(0, s.height * 0.2, s.width, s.height * 0.8)));
    c.drawPath(silueta, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0x9922D3EE)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    c.drawPath(silueta, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xCC67E8F9));
  }

  @override
  bool shouldRepaint(_) => false;
}

Widget _kiosco(_KioscoFalso k, {bool registrado = false}) {
  final sync = _SyncFalso();
  return Scaffold(
    backgroundColor: Hud.fondo,
    body: LayoutBuilder(builder: (context, caja) {
      final mapa = MapaPantalla(imagen: const Size(480, 640), pantalla: caja.biggest, espejo: false);
      return Stack(children: [
        const Positioned.fill(child: _CamaraSimulada()),
        Positioned.fill(
          child: HudBiometrico(
            color: colorFase(k),
            rostro: k.rostro,
            mapa: mapa,
            escaneando: k.fase.escaneando,
            lecturaSuperior: 'BIO·SCAN › ${k.fase == FaseKiosco.identificado ? 'IDENTIFICADO' : 'ANALIZANDO'}',
            lecturaDerecha: k.similitud > 0 ? 'MATCH ${(k.similitud * 100).toStringAsFixed(1)}%' : null,
            lecturaInferior: 'ROSTROS 024 · PRI',
          ),
        ),
        SafeArea(
          child: Column(children: [
            EncabezadoKiosco(sede: 'Sede principal', sync: sync, alCerrar: () {}),
            const Spacer(),
            Padding(padding: const EdgeInsets.all(16), child: PanelFase(k: k, sync: sync)),
          ]),
        ),
        if (registrado)
          Positioned.fill(
            child: PantallaRegistrado(empleado: k.empleado!, marcacion: k.registrada!, enLinea: true, puntualidad: k.puntualidad),
          ),
      ]);
    }),
  );
}

Widget _admin(Widget pagina, String titulo, {Brightness brillo = Brightness.dark}) {
  const sede = Sede(id: 1, nombre: 'Sede principal', codigo: 'PRI');
  final ctx = ContextoAdmin(api: _ApiFalsa(), sedes: const [sede], sedeDispositivo: sede);
  return _app(
    ChangeNotifierProvider.value(
      value: ctx,
      child: Builder(builder: (context) => Scaffold(
        appBar: AppBar(
          leading: const Icon(Icons.close_rounded),
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PANEL · ADMINISTRADOR', style: context.textos.labelSmall?.copyWith(color: context.colores.primary)),
            Text(titulo),
          ]),
        ),
        body: pagina,
        bottomNavigationBar: NavigationBar(
          selectedIndex: switch (titulo) { 'Asistencia' => 0, 'Personal' => 1, 'Horarios' => 2, _ => 3 },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Asistencia'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Personal'),
            NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule_rounded), label: 'Horarios'),
            NavigationDestination(icon: Icon(Icons.tune_outlined), label: 'Ajustes'),
          ],
        ),
      )),
    ),
    brillo: brillo,
  );
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es_CO');
    await _cargarFuentes();
  });

  final ana = EmpleadoLocal(
    id: 1, documento: '1055432', nombre: 'Ana María Rojas', cargo: 'Cajera',
    turnoHoy: '08:30-12:00,14:00-18:00', turnoFecha: _hoy(), tolerancia: 10,
  );

  testWidgets('kiosco · analizando', (t) async {
    final k = _KioscoFalso()
      ..fase = FaseKiosco.analizando
      ..rostro = _rostro()
      ..similitud = 0.874;
    await _capturar(t, '01_kiosco_analizando', _app(_kiosco(k)));
  });

  testWidgets('kiosco · identificado', (t) async {
    final k = _KioscoFalso()
      ..fase = FaseKiosco.identificado
      ..rostro = _rostro()
      ..similitud = 0.912
      ..empleado = ana
      ..segundosRestantes = 3;
    await _capturar(t, '02_kiosco_identificado', _app(_kiosco(k)));
  });

  testWidgets('kiosco · registrado', (t) async {
    final ahora = DateTime.now();
    final hora = DateTime(ahora.year, ahora.month, ahora.day, 8, 52);
    final k = _KioscoFalso()
      ..fase = FaseKiosco.registrado
      ..empleado = ana
      ..registrada = Marcacion(empleadoId: 1, tipo: TipoMarcacion.entrada, hora: hora.toUtc())
      ..puntualidad = Asistencia.puntualidad(ana, TipoMarcacion.entrada, hora);
    await _capturar(t, '03_kiosco_registrado', _app(_kiosco(k, registrado: true)));
  });

  testWidgets('kiosco · rostro desconocido', (t) async {
    final k = _KioscoFalso()..fase = FaseKiosco.desconocido;
    await _capturar(t, '04_kiosco_desconocido', _app(_kiosco(k)));
  });

  testWidgets('admin · asistencia del día', (t) async {
    await _capturar(t, '05_admin_asistencia', _admin(const VistaDia(), 'Asistencia'));
  });

  testWidgets('admin · cumplimiento', (t) async {
    await _capturar(t, '06_admin_cumplimiento', _admin(const CumplimientoVista(), 'Asistencia'));
  });

  testWidgets('admin · horarios', (t) async {
    await _capturar(t, '07_admin_horarios', _admin(const HorariosPage(), 'Horarios'));
  });

  testWidgets('admin · turno', (t) async {
    final h = Horario.desdeJson(_ApiFalsa._turnos[0]);
    await _capturar(t, '08_admin_turno', _admin(TurnoFormPage(horario: h), 'Horarios'));
  });

  testWidgets('admin · rotación del empleado', (t) async {
    const e = Empleado(id: 2, sedeId: 1, documento: '1023', nombre: 'Carlos Pérez');
    await _capturar(
      t,
      '09_admin_plan_empleado',
      _admin(ListView(padding: const EdgeInsets.all(16), children: const [TarjetaHorarioEmpleado(empleado: e)]), 'Personal'),
    );
  });

  testWidgets('admin · asistencia (tema claro)', (t) async {
    await _capturar(t, '10_admin_asistencia_claro', _admin(const VistaDia(), 'Asistencia', brillo: Brightness.light));
  });

  testWidgets('inicio · sin vincular', (t) async {
    await _capturar(t, '11_inicio_sin_vincular', _app(VistaInicioSinVincular(alIniciarSesion: () {}, alCrearCuenta: () {})));
  });

  testWidgets('inicio · teléfono de marcación', (t) async {
    final hoy = DateTime.now();
    MarcaDeHoy marca(int id, String nombre, TipoMarcacion tipo, int h, int m, {bool enviada = true}) => (
          nombre: nombre,
          marcacion: Marcacion(empleadoId: id, tipo: tipo, hora: DateTime(hoy.year, hoy.month, hoy.day, h, m), enviada: enviada),
        );
    await _capturar(
      t,
      '12_inicio_vinculado',
      _app(VistaInicioVinculado(
        sede: 'Sede principal',
        telefono: 'Sede principal · Teléfono 1',
        codigo: 'K7QD',
        estadoSync: Pildora(texto: 'En línea', color: Hud.entrada, fondo: Hud.panel, icono: Icons.cloud_done_outlined),
        reloj: Text('08:52', style: Hud.titulo(tam: 52, peso: FontWeight.w600)),
        alMarcar: () {},
        alAdministrar: () {},
        marcas: [
          marca(4, 'Valentina Ortiz', TipoMarcacion.entrada, 8, 52, enviada: false),
          marca(1, 'Ana María Rojas', TipoMarcacion.entrada, 8, 41),
          marca(2, 'Carlos Pérez', TipoMarcacion.salida, 8, 30),
          marca(3, 'Luis Fernando Gómez', TipoMarcacion.entrada, 7, 58),
        ],
      )),
    );
  });
}

String _hoy() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
