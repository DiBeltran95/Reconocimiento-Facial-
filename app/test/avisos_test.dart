import 'package:control_personal/core/tema.dart';
import 'package:control_personal/ui/comun/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Un aviso lanzado DESDE una hoja inferior tiene que verse: antes quedaba
/// detrás de la hoja, la persona creía que el botón no hizo nada y lo volvía
/// a tocar.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('el aviso desde una hoja inferior flota encima y se ve', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: construirTema(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (hoja) => SizedBox(
                height: 300,
                child: Center(
                  child: TextButton(
                    onPressed: () => avisar(hoja, 'Ese correo ya tiene cuenta', error: true),
                    child: const Text('Guardar'),
                  ),
                ),
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('Abrir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Guardar'));
    await t.pump();

    expect(find.text('Ese correo ya tiene cuenta'), findsOneWidget);
    // Visible por encima de la hoja: se puede tocar para cerrarlo.
    await t.tap(find.text('Ese correo ya tiene cuenta'));
    await t.pump();
    expect(find.text('Ese correo ya tiene cuenta'), findsNothing);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('en una pantalla normal sigue siendo un snackbar', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: construirTema(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => avisar(context, 'Empleado creado'),
            child: const Text('Guardar'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('Guardar'));
    await t.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Empleado creado'), findsOneWidget);
  });
}
