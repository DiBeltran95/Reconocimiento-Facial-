import 'package:control_personal/core/tema.dart';
import 'package:control_personal/data/modelos.dart';
import 'package:control_personal/servicios/config_dispositivo.dart';
import 'package:control_personal/ui/inicio/inicio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Widget _app(Widget hijo) => MaterialApp(theme: construirTema(Brightness.dark), home: hijo);

MarcaDeHoy _marca(int empleado, String nombre, TipoMarcacion tipo, int hora, {int minuto = 0}) => (
      nombre: nombre,
      marcacion: Marcacion(empleadoId: empleado, tipo: tipo, hora: DateTime(2026, 10, 21, hora, minuto), enviada: true),
    );

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es_CO');
    Intl.defaultLocale = 'es_CO';
  });

  group('Pantalla inicial sin vincular', () {
    testWidgets('no deja marcar y ofrece iniciar sesión o crear cuenta', (t) async {
      var sesion = 0;
      var cuenta = 0;
      t.view.physicalSize = const Size(412, 915) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(VistaInicioSinVincular(alIniciarSesion: () => sesion++, alCrearCuenta: () => cuenta++)));

      expect(find.text('Marcar asistencia'), findsOneWidget);
      expect(find.textContaining('aún no es un punto de marcación'), findsOneWidget);
      final boton = t.widget<BotonMarcar>(find.byType(BotonMarcar));
      expect(boton.alTocar, isNull);

      await t.tap(find.text('Iniciar sesión'));
      await t.tap(find.text('Crear cuenta de empresa gratis'));
      expect((sesion, cuenta), (1, 1));
    });

    testWidgets('explica por qué el teléfono dejó de marcar', (t) async {
      await t.pumpWidget(_app(VistaInicioSinVincular(
        alIniciarSesion: () {},
        alCrearCuenta: () {},
        aviso: 'Un administrador desvinculó este teléfono.',
      )));
      expect(find.text('Un administrador desvinculó este teléfono.'), findsOneWidget);
    });
  });

  group('Teléfono de marcación', () {
    Widget vista({List<MarcaDeHoy> marcas = const [], VoidCallback? alMarcar}) => _app(VistaInicioVinculado(
          sede: 'Centro',
          telefono: 'Centro · Teléfono 2',
          codigo: 'K7QD',
          marcas: marcas,
          estadoSync: const Text('En línea'),
          alMarcar: alMarcar ?? () {},
          alAdministrar: () {},
          reloj: const Text('08:30'),
        ));

    testWidgets('marca, muestra quién marcó hoy y no tiene cerrar sesión', (t) async {
      var marco = 0;
      await t.pumpWidget(vista(
        alMarcar: () => marco++,
        marcas: [
          _marca(1, 'Ana Rojas', TipoMarcacion.salida, 12, minuto: 5),
          _marca(2, 'Luis Gómez', TipoMarcacion.entrada, 8, minuto: 2),
        ],
      ));

      expect(find.text('SEDE · CENTRO'), findsOneWidget);
      expect(find.text('Ana Rojas'), findsOneWidget);
      expect(find.text('Luis Gómez'), findsOneWidget);
      expect(find.text('Salida'), findsOneWidget);
      expect(find.textContaining('K7QD'), findsOneWidget);
      expect(find.textContaining('Cerrar sesión'), findsNothing);
      expect(find.text('Administrar'), findsOneWidget);

      await t.tap(find.text('Marcar asistencia'));
      expect(marco, 1);
    });

    testWidgets('sin marcas lo dice', (t) async {
      await t.pumpWidget(vista());
      expect(find.text('Aún nadie ha marcado hoy en esta sede.'), findsOneWidget);
    });
  });

  test('de cada persona queda solo su última marca, la más reciente primero', () {
    final lista = ultimaMarcaPorPersona([
      _marca(1, 'Ana', TipoMarcacion.entrada, 8),
      _marca(2, 'Luis', TipoMarcacion.entrada, 9),
      _marca(1, 'Ana', TipoMarcacion.salida, 12),
    ]);
    expect(lista.map((m) => (m.nombre, m.marcacion.tipo)), [('Ana', TipoMarcacion.salida), ('Luis', TipoMarcacion.entrada)]);
  });

  test('cada instalación tiene un UUID v4 válido y distinto', () {
    final a = ConfigDispositivo.uuidV4();
    final b = ConfigDispositivo.uuidV4();
    final formato = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    expect(formato.hasMatch(a), isTrue, reason: a);
    expect(a, isNot(b));
  });
}
