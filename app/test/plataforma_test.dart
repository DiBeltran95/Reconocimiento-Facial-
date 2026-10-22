import 'dart:convert';

import 'package:control_personal/core/tema.dart';
import 'package:control_personal/data/api.dart';
import 'package:control_personal/data/modelos.dart';
import 'package:control_personal/ui/cuenta/plan_ui.dart';
import 'package:control_personal/ui/cuenta/registro_empresa_page.dart';
import 'package:control_personal/ui/cuenta/sin_acceso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Respuesta del plan con la MISMA forma que los dos backends (docs/PLATAFORMA.md).
const _planGratisLleno = {
  'codigo': 'GRATIS',
  'nombre': 'Gratis',
  'vence': null,
  'vencido': false,
  'sedes': {'usados': 1, 'maximo': 1, 'lleno': true},
  'personas': {'usados': 2, 'maximo': 3, 'lleno': false},
  'productos': {'usados': 0, 'maximo': 3, 'lleno': false},
};

Widget _app(Widget hijo) => MaterialApp(theme: construirTema(Brightness.dark), home: hijo);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Plan', () {
    test('lee el uso y sabe cuándo un recurso está lleno', () {
      final plan = PlanEmpresa.desdeJson(_planGratisLleno)!;
      expect(plan.esGratis, isTrue);
      expect(plan.sedes.lleno, isTrue);
      expect(plan.personas.lleno, isFalse);
      expect(plan.personas.disponibles, 1);
      expect(plan.de(RecursoLimitado.productos).maximo, 3);
    });

    test('máximo null significa sin límite', () {
      final r = RecursoPlan.desdeJson({'usados': 40, 'maximo': null});
      expect(r.ilimitado, isTrue);
      expect(r.lleno, isFalse);
      expect(r.disponibles, isNull);
    });

    test('el recurso del error LIMITE_PLAN se reconoce', () {
      expect(RecursoLimitado.desdeApi('personas'), RecursoLimitado.personas);
      expect(RecursoLimitado.desdeApi('otra'), isNull);
      const e = ApiError(409, 'Tu plan no admite más sedes', codigo: 'LIMITE_PLAN', recurso: 'sedes');
      expect(e.limitePlan, isTrue);
      expect(e.sinAccesoApp, isFalse);
    });

    test('los códigos de acceso se distinguen de un error común', () {
      expect(const ApiError(403, 'x', codigo: 'APP_NO_HABILITADA').sinAccesoApp, isTrue);
      expect(const ApiError(403, 'x', codigo: 'SIN_ACCESO_APP').sinAccesoApp, isTrue);
      expect(const ApiError(401, 'Correo o contraseña incorrectos').sinAccesoApp, isFalse);
    });
  });

  group('Cuentas', () {
    test('los roles son independientes: gerente en Presente y vendedor en Ventario', () {
      final u = Usuario.desdeJson(jsonDecode('''{
        "id": 7, "uuid": "x", "nombre": "Ana", "email": "ana@ej.co", "documento": "123",
        "rol": "ADMINISTRATIVO", "rol_asistencia": "GERENTE", "rol_inventario": "VENDEDOR",
        "sedes": [2], "activo": true, "empleado_id": 4, "telefono": "300"}''') as Map<String, dynamic>);
      expect(u.rolAsistencia, RolAsistencia.gerente);
      expect(u.rolInventario, RolInventario.vendedor);
      expect(u.tieneVentario, isTrue);
      expect(u.empleadoId, 4);
      expect(u.sedes, [2]);
    });

    test('sin rol en Inventario queda null; OPERADOR y GENERAL son el operario', () {
      final u = Usuario.desdeJson({
        'id': 1, 'nombre': 'Kiosco', 'email': 'k@ej.co', 'rol_asistencia': 'OPERADOR', 'rol_inventario': null,
        'pausa_asistencia': true,
      });
      expect(u.rolInventario, isNull);
      expect(u.rolAsistencia, RolAsistencia.operario);
      expect(u.tieneVentario, isFalse);
      expect(u.empleadoId, isNull, reason: 'el operario es una cuenta técnica');
      expect(u.pausaAsistencia, isTrue);
      expect(RolAsistencia.desdeApi('GENERAL'), RolAsistencia.operario);
    });

    test('el empleado trae teléfono, correo y sus accesos', () {
      final e = Empleado.desdeJson({
        'id': 3, 'sede_id': 1, 'documento': '1055', 'nombre': 'Luz', 'telefono': '3001234567', 'email': 'luz@ej.co',
        'cuenta': {'email': 'luz@ej.co', 'activa': true, 'rol_asistencia': null, 'rol_inventario': 'VENDEDOR'},
      });
      expect(e.telefono, '3001234567');
      expect(e.email, 'luz@ej.co');
      expect(e.cuentaRolAsistencia, isNull);
      expect(e.cuentaRolInventario, 'VENDEDOR');
    });

    test('un candidato sabe si ya entra a Ventario', () {
      final c = CandidatoCuenta.desdeJson({
        'id': 3, 'documento': '1055', 'nombre': 'Luz', 'sede_id': 1, 'sede': 'Centro', 'email': 'luz@ej.co', 'con_cuenta': true,
      });
      expect(c.conCuenta, isTrue);
      expect(c.sede, 'Centro');
    });

    test('la sesión del operario no entra al panel', () {
      SesionAdmin sesion(String rol, String rolAsis) => SesionAdmin(
            token: 't',
            nombre: 'x',
            rol: Rol.desdeApi(rol),
            rolAsistencia: RolAsistencia.desdeApi(rolAsis),
            expira: DateTime.now().add(const Duration(hours: 1)),
          );
      expect(sesion('GENERAL', 'OPERARIO').esOperario, isTrue);
      expect(sesion('GENERAL', 'OPERARIO').esAdministrativo, isFalse);
      expect(sesion('ADMINISTRATIVO', 'TALENTO_HUMANO').esAdministrativo, isTrue);
      expect(sesion('ADMINISTRATIVO', 'TALENTO_HUMANO').esTalentoHumano, isTrue);
      expect(sesion('ADMINISTRATIVO', 'TALENTO_HUMANO').esAdminEmpresa, isFalse);
    });
  });

  group('Planes por app', () {
    test('Mi empresa trae el plan de cada app', () {
      final e = EmpresaInfo.desdeJson({
        'empresa': {'uuid': 'u', 'nombre': 'Tienda'},
        'plan': {..._planGratisLleno, 'aplicativo': 'ASISTENCIA'},
        'planes': {
          'ASISTENCIA': {..._planGratisLleno, 'aplicativo': 'ASISTENCIA'},
          'INVENTARIO': {..._planGratisLleno, 'aplicativo': 'INVENTARIO', 'codigo': 'ILIMITADO', 'nombre': 'Ilimitado'},
        },
        'aplicativos': ['ASISTENCIA', 'INVENTARIO'],
      });
      expect(e.plan!.esPresente, isTrue);
      expect(e.plan!.recursos, isNot(contains(RecursoLimitado.productos)));
      expect(e.planVentario!.nombreApp, 'Ventario');
      expect(e.planVentario!.esGratis, isFalse);
      expect(e.planVentario!.recursos, contains(RecursoLimitado.productos));
    });

    test('las sedes dicen en qué app se usan', () {
      final s = Sede.desdeJson({'id': 3, 'nombre': 'Norte', 'codigo': 'NOR', 'elegida': false, 'elegida_ventario': true});
      expect(s.elegida, isFalse);
      expect(s.elegidaVentario, isTrue);
      expect(Sede.desdeJson({'id': 1, 'nombre': 'Centro'}).elegida, isTrue);
    });

    test('las personas en pausa se reconocen', () {
      final e = Empleado.desdeJson({'id': 1, 'sede_id': 1, 'documento': '1', 'nombre': 'Luz', 'en_pausa': true});
      expect(e.enPausa, isTrue);
    });
  });

  group('Pantallas', () {
    testWidgets('el medidor dice el estado con texto, no solo con color', (t) async {
      await t.pumpWidget(_app(const Scaffold(
        body: MedidorUso(recurso: RecursoLimitado.sedes, uso: RecursoPlan(usados: 1, maximo: 1)),
      )));
      expect(find.text('1 de 1'), findsOneWidget);
      expect(find.text('Límite alcanzado'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Sedes: 1 de 1. Límite alcanzado')), findsOneWidget);
    });

    testWidgets('la hoja de límite explica el plan sin botones de pago', (t) async {
      await t.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => mostrarHojaLimite(
              context,
              RecursoLimitado.sedes,
              plan: PlanEmpresa.desdeJson(_planGratisLleno),
            ),
            child: const Text('abrir'),
          ),
        ),
      )));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(find.text('Llegaste al límite de tu plan'), findsOneWidget);
      expect(find.textContaining('incluye hasta 1 sede'), findsOneWidget);
      expect(find.textContaining('equipo de la plataforma'), findsOneWidget);
      // Política de Google Play: nada de comprar, pagar ni precios dentro de la app.
      expect(find.textContaining(RegExp('comprar|pagar|precio', caseSensitive: false)), findsNothing);
      await t.tap(find.text('Entendido'));
      await t.pumpAndSettle();
      expect(find.text('Llegaste al límite de tu plan'), findsNothing);
    });

    testWidgets('el registro valida cada paso y permite volver atrás', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.5;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(RegistroEmpresaPage(api: Api(baseUrl: 'https://ejemplo.invalid'))));
      await t.pumpAndSettle();

      // Paso 1 vacío: los errores aparecen junto a cada campo.
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
      expect(find.text('Escribe tu nombre completo'), findsOneWidget);
      expect(find.text('Escribe un correo válido'), findsOneWidget);
      expect(find.text('Usa al menos 8 caracteres'), findsOneWidget);

      await t.enterText(find.widgetWithText(TextFormField, 'Tu nombre completo'), 'Ana Gómez');
      await t.enterText(find.widgetWithText(TextFormField, 'Correo'), 'ana@tienda.co');
      await t.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'Clave-Segura-2026');
      await t.pump();
      expect(find.textContaining('Muy buena'), findsOneWidget);
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
      expect(find.text('Tu empresa'), findsOneWidget);

      // Atrás conserva lo escrito.
      await t.tap(find.byTooltip('Paso anterior'));
      await t.pumpAndSettle();
      expect(find.text('Ana Gómez'), findsOneWidget);
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();

      await t.enterText(find.widgetWithText(TextFormField, 'Nombre de la empresa'), 'Tienda La 14');
      await t.tap(find.text('Continuar'));
      await t.pumpAndSettle();
      expect(find.text('Tu primera sede'), findsOneWidget);
      expect(find.text('Plan Gratis · sin costo'.toUpperCase()), findsOneWidget);

      // Sin aceptar los términos no se envía nada.
      await t.tap(find.text('Crear empresa'));
      await t.pumpAndSettle();
      expect(find.textContaining('acepta los términos'), findsOneWidget);
    });

    testWidgets('sin acceso explica el motivo y ofrece otra cuenta', (t) async {
      var otra = false;
      await t.pumpWidget(_app(Scaffold(
        body: PanelSinAcceso(
          error: const ApiError(403, 'x', codigo: 'APP_NO_HABILITADA'),
          alUsarOtraCuenta: () => otra = true,
        ),
      )));
      expect(find.text('Tu empresa aún no usa Presente'), findsOneWidget);
      await t.tap(find.text('Usar otra cuenta'));
      expect(otra, isTrue);
    });
  });
}
