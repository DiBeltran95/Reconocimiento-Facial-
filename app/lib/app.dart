import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/tema.dart';
import 'servicios/ajustes.dart';
import 'servicios/estado_app.dart';
import 'ui/configuracion/bienvenida_page.dart';
import 'ui/kiosco/kiosco_page.dart';

class ControlPersonalApp extends StatelessWidget {
  const ControlPersonalApp({super.key, required this.estado});

  final EstadoApp estado;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: estado),
        ChangeNotifierProvider.value(value: estado.ajustes),
      ],
      child: Consumer<Ajustes>(
        builder: (context, ajustes, _) => MaterialApp(
          title: 'Control de Personal',
          debugShowCheckedModeBanner: false,
          theme: construirTema(Brightness.light),
          darkTheme: construirTema(Brightness.dark),
          themeMode: ajustes.tema,
          locale: const Locale('es', 'CO'),
          supportedLocales: const [Locale('es', 'CO'), Locale('es')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const _Inicio(),
        ),
      ),
    );
  }
}

/// Sin vínculo → asistente de configuración. Con vínculo → kiosco.
class _Inicio extends StatelessWidget {
  const _Inicio();

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    if (!estado.configurado) return const BienvenidaPage();
    return ChangeNotifierProvider.value(
      // La clave fuerza un kiosco nuevo si se vuelve a vincular.
      key: ObjectKey(estado.sincronizador),
      value: estado.sincronizador!,
      child: const KioscoPage(),
    );
  }
}
