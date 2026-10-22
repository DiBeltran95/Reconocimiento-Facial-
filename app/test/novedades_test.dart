import 'package:control_personal/core/tema.dart';
import 'package:control_personal/data/api.dart';
import 'package:control_personal/data/modelos.dart';
import 'package:control_personal/ui/admin/novedades_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Misma forma que responde GET /api/novedades (NovedadesControlador::aJson).
Map<String, dynamic> _json({
  String tipo = 'INCAPACIDAD',
  String estado = 'PENDIENTE',
  String desde = '2026-11-03',
  String hasta = '2026-11-05',
  String? horaDesde,
  String? horaHasta,
  int soportes = 1,
}) =>
    {
      'id': 17,
      'tipo': tipo,
      'estado': estado,
      'canal': 'WHATSAPP',
      'fecha_desde': desde,
      'fecha_hasta': hasta,
      'hora_desde': horaDesde,
      'hora_hasta': horaHasta,
      'motivo': 'Gripa fuerte, el médico me dio tres días.',
      'comentario': null,
      'soportes': soportes,
      'empleado': {'id': 4, 'nombre': 'Laura Gómez Ruiz', 'documento': '1032456789', 'cargo': 'Cajera'},
      'sede': {'id': 1, 'nombre': 'Centro'},
      'resuelto_por': null,
      'resuelto_en': null,
      'creada': '2026-11-02T18:20:00-05:00',
    };

Widget _app(Widget hijo) => MaterialApp(theme: construirTema(Brightness.dark), home: Scaffold(body: hijo));

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es_CO');
  });

  group('Modelo', () {
    test('lee una novedad de varios días', () {
      final n = Novedad.desdeJson(_json());
      expect(n.tipo, TipoNovedad.incapacidad);
      expect(n.pendiente, isTrue);
      expect(n.porHoras, isFalse);
      expect(n.dias, 3);
      expect(duracionNovedad(n), '3 días');
      expect(n.empleado, 'Laura Gómez Ruiz');
      expect(n.soportes, 1);
    });

    test('un permiso por horas dura lo que dicen sus horas', () {
      final n = Novedad.desdeJson(_json(tipo: 'PERMISO', hasta: '2026-11-03', horaDesde: '08:00', horaHasta: '12:30'));
      expect(n.porHoras, isTrue);
      expect(n.dias, 1);
      expect(duracionNovedad(n), contains('4'));
      expect(periodoNovedad(n), contains('–'));
    });

    test('tipos y estados desconocidos no rompen la lectura', () {
      expect(TipoNovedad.desdeApi('NUEVO_TIPO'), TipoNovedad.otro);
      expect(EstadoNovedad.desdeApi('APROBADA'), EstadoNovedad.aprobada);
    });
  });

  group('Pantalla', () {
    testWidgets('la tarjeta muestra quién, qué, cuándo y el soporte', (t) async {
      final n = Novedad.desdeJson(_json());
      await t.pumpWidget(_app(TarjetaNovedad(novedad: n, alTocar: () {})));
      expect(find.text('Laura Gómez Ruiz'), findsOneWidget);
      expect(find.text('Incapacidad médica'), findsOneWidget);
      expect(find.text('Soporte'), findsOneWidget);
      expect(find.textContaining('3 días'), findsOneWidget);
    });

    testWidgets('rechazar sin motivo no envía nada y explica qué falta', (t) async {
      final n = Novedad.desdeJson(_json());
      final api = Api(baseUrl: 'https://ejemplo.invalid');
      await t.pumpWidget(_app(SingleChildScrollView(child: HojaNovedad(novedad: n, api: api, veSoportes: false))));
      await t.ensureVisible(find.text('Rechazar'));
      await t.tap(find.text('Rechazar'));
      await t.pump();
      expect(find.textContaining('motivo del rechazo'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('sin permiso de salud el soporte queda bloqueado', (t) async {
      final n = Novedad.desdeJson(_json());
      final api = Api(baseUrl: 'https://ejemplo.invalid');
      await t.pumpWidget(_app(SingleChildScrollView(child: HojaNovedad(novedad: n, api: api, veSoportes: false))));
      expect(find.textContaining('solo lo ven el administrador y talento humano'), findsOneWidget);
    });

    testWidgets('una resuelta muestra el resultado y no los botones', (t) async {
      final j = _json(estado: 'APROBADA')
        ..['resuelto_por'] = 'Ana Talento'
        ..['comentario'] = 'Que te mejores';
      final n = Novedad.desdeJson(j);
      final api = Api(baseUrl: 'https://ejemplo.invalid');
      await t.pumpWidget(_app(SingleChildScrollView(child: HojaNovedad(novedad: n, api: api, veSoportes: false))));
      expect(find.text('Aprobar'), findsNothing);
      expect(find.textContaining('Ana Talento'), findsOneWidget);
      expect(find.textContaining('Que te mejores'), findsOneWidget);
    });
  });
}
