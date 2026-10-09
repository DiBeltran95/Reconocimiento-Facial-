import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño "futurista moderno":
///  - Base oscura azul-noche con acentos cian neón (HUD / Sci-Fi FUI).
///  - Tipografías: Space Grotesk (títulos y reloj), Plus Jakarta Sans (texto),
///    JetBrains Mono (lecturas técnicas del HUD).
///  - Líneas finas, bordes de 1 px, brillo sutil y movimiento con propósito
///    (siempre se respeta "reducir movimiento" del sistema).
/// Todo color sale de aquí: nada de hex sueltos en las pantallas.
abstract final class Espacio {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class Redondeo {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

abstract final class Duraciones {
  static const rapida = Duration(milliseconds: 150);
  static const media = Duration(milliseconds: 260);
  static const lenta = Duration(milliseconds: 420);
  static const escaneo = Duration(milliseconds: 2200);
  static const giro = Duration(seconds: 9);
}

/// Paleta del HUD biométrico (kiosco y captura). Siempre oscura: la cámara
/// es protagonista y el texto claro mantiene contraste ≥ 7:1 sobre el velo.
abstract final class Hud {
  static const fondo = Color(0xFF02040A);
  static const velo = Color(0xD902040A); // 85 % sobre el video
  static const texto = Color(0xFFF1F5F9);
  static const textoSuave = Color(0xFFB6C2D4);
  static const cian = Color(0xFF22D3EE);
  static const cianTenue = Color(0x5522D3EE);
  static const azul = Color(0xFF3B82F6);
  static const linea = Color(0x6622D3EE);
  static const entrada = Color(0xFF34D399);
  static const salida = Color(0xFFA78BFA);
  static const alerta = Color(0xFFFBBF24);
  static const peligro = Color(0xFFFB7185);
  static const panel = Color(0xE60A1324);
  static const panelBorde = Color(0x8022D3EE);

  static TextStyle mono({double tam = 12, Color color = textoSuave, FontWeight peso = FontWeight.w500, double espaciado = 1.2}) =>
      GoogleFonts.jetBrainsMono(fontSize: tam, color: color, fontWeight: peso, letterSpacing: espaciado);

  static TextStyle titulo({double tam = 28, Color color = texto, FontWeight peso = FontWeight.w700}) =>
      GoogleFonts.spaceGrotesk(fontSize: tam, color: color, fontWeight: peso, letterSpacing: -0.4, height: 1.1);

  static TextStyle cuerpo({double tam = 18, Color color = texto, FontWeight peso = FontWeight.w600}) =>
      GoogleFonts.plusJakartaSans(fontSize: tam, color: color, fontWeight: peso, height: 1.35);

  static List<Shadow> brillo(Color c, {double radio = 12}) => [Shadow(color: c.withValues(alpha: 0.75), blurRadius: radio)];
}

/// Colores con significado (entrada, salida, alertas) en claro y oscuro.
@immutable
class Semanticos extends ThemeExtension<Semanticos> {
  const Semanticos({
    required this.entrada,
    required this.entradaFondo,
    required this.salida,
    required this.salidaFondo,
    required this.alerta,
    required this.alertaFondo,
    required this.peligro,
    required this.peligroFondo,
    required this.textoSuave,
    required this.borde,
    required this.brillo,
    required this.degradado,
  });

  final Color entrada;
  final Color entradaFondo;
  final Color salida;
  final Color salidaFondo;
  final Color alerta;
  final Color alertaFondo;
  final Color peligro;
  final Color peligroFondo;
  final Color textoSuave;
  final Color borde;

  /// Halo para elementos destacados (tarjetas activas, indicadores).
  final Color brillo;

  /// Degradado de acento para cabeceras y botones principales.
  final List<Color> degradado;

  static const claro = Semanticos(
    entrada: Color(0xFF047857),
    entradaFondo: Color(0xFFD1FAE5),
    salida: Color(0xFF6D28D9),
    salidaFondo: Color(0xFFEDE9FE),
    alerta: Color(0xFFB45309),
    alertaFondo: Color(0xFFFEF3C7),
    peligro: Color(0xFFBE123C),
    peligroFondo: Color(0xFFFFE4E6),
    textoSuave: Color(0xFF475569),
    borde: Color(0xFFD5DEE9),
    brillo: Color(0x330E7490),
    degradado: [Color(0xFF0E7490), Color(0xFF2563EB)],
  );

  static const oscuro = Semanticos(
    entrada: Color(0xFF34D399),
    entradaFondo: Color(0xFF052E25),
    salida: Color(0xFFA78BFA),
    salidaFondo: Color(0xFF221A45),
    alerta: Color(0xFFFBBF24),
    alertaFondo: Color(0xFF3A2405),
    peligro: Color(0xFFFB7185),
    peligroFondo: Color(0xFF3F0D18),
    textoSuave: Color(0xFFA9B6C8),
    borde: Color(0xFF1C2E4A),
    brillo: Color(0x4022D3EE),
    degradado: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
  );

  @override
  Semanticos copyWith() => this;

  @override
  Semanticos lerp(Semanticos? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Semanticos(
      entrada: l(entrada, other.entrada),
      entradaFondo: l(entradaFondo, other.entradaFondo),
      salida: l(salida, other.salida),
      salidaFondo: l(salidaFondo, other.salidaFondo),
      alerta: l(alerta, other.alerta),
      alertaFondo: l(alertaFondo, other.alertaFondo),
      peligro: l(peligro, other.peligro),
      peligroFondo: l(peligroFondo, other.peligroFondo),
      textoSuave: l(textoSuave, other.textoSuave),
      borde: l(borde, other.borde),
      brillo: l(brillo, other.brillo),
      degradado: [l(degradado[0], other.degradado[0]), l(degradado[1], other.degradado[1])],
    );
  }
}

extension TemaContexto on BuildContext {
  ThemeData get tema => Theme.of(this);
  ColorScheme get colores => Theme.of(this).colorScheme;
  TextTheme get textos => Theme.of(this).textTheme;
  Semanticos get sem => Theme.of(this).extension<Semanticos>()!;
  bool get sinMovimiento => MediaQuery.disableAnimationsOf(this);
}

ThemeData construirTema(Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  final esquema = oscuro
      ? const ColorScheme.dark(
          primary: Color(0xFF22D3EE),
          onPrimary: Color(0xFF00141A),
          primaryContainer: Color(0xFF0B3A4A),
          onPrimaryContainer: Color(0xFFCFFAFE),
          secondary: Color(0xFF60A5FA),
          onSecondary: Color(0xFF051634),
          secondaryContainer: Color(0xFF0B3A4A),
          onSecondaryContainer: Color(0xFFCFFAFE),
          surface: Color(0xFF050B17),
          onSurface: Color(0xFFF1F5F9),
          surfaceContainerLowest: Color(0xFF02060F),
          surfaceContainerLow: Color(0xFF0A1324),
          surfaceContainer: Color(0xFF0E1A30),
          surfaceContainerHigh: Color(0xFF14223C),
          surfaceContainerHighest: Color(0xFF1B2B4A),
          onSurfaceVariant: Color(0xFFB6C2D4),
          outline: Color(0xFF3A5274),
          outlineVariant: Color(0xFF1C2E4A),
          error: Color(0xFFFB7185),
          onError: Color(0xFF3F0D18),
        )
      : const ColorScheme.light(
          primary: Color(0xFF0E7490),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFFCFFAFE),
          onPrimaryContainer: Color(0xFF083344),
          secondary: Color(0xFF2563EB),
          onSecondary: Color(0xFFFFFFFF),
          secondaryContainer: Color(0xFFCFFAFE),
          onSecondaryContainer: Color(0xFF083344),
          surface: Color(0xFFF4F8FC),
          onSurface: Color(0xFF0B1324),
          surfaceContainerLowest: Color(0xFFFFFFFF),
          surfaceContainerLow: Color(0xFFFFFFFF),
          surfaceContainer: Color(0xFFEDF3F9),
          surfaceContainerHigh: Color(0xFFE4ECF5),
          surfaceContainerHighest: Color(0xFFD9E3EF),
          onSurfaceVariant: Color(0xFF475569),
          outline: Color(0xFF8DA0B8),
          outlineVariant: Color(0xFFD5DEE9),
          error: Color(0xFFBE123C),
          onError: Color(0xFFFFFFFF),
        );

  final base = ThemeData(useMaterial3: true, colorScheme: esquema, brightness: brillo);
  TextStyle g(double tam, FontWeight peso, {double ls = 0, double? alto}) =>
      GoogleFonts.spaceGrotesk(fontSize: tam, fontWeight: peso, letterSpacing: ls, height: alto);

  final textos = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
      .copyWith(
        displaySmall: g(36, FontWeight.w700, ls: -0.8),
        headlineMedium: g(28, FontWeight.w700, ls: -0.5),
        headlineSmall: g(22, FontWeight.w700, ls: -0.3),
        titleLarge: g(20, FontWeight.w700, ls: -0.2),
        titleMedium: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
        bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 16, height: 1.5),
        bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.45),
        labelLarge: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
        labelSmall: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1),
      )
      .apply(bodyColor: esquema.onSurface, displayColor: esquema.onSurface);

  final redondeo = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Redondeo.md));
  const alturaBoton = Size(64, 52);

  return base.copyWith(
    textTheme: textos,
    scaffoldBackgroundColor: esquema.surface,
    extensions: [oscuro ? Semanticos.oscuro : Semanticos.claro],
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.surface,
      foregroundColor: esquema.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textos.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: esquema.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Redondeo.lg),
        side: BorderSide(color: esquema.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: alturaBoton, shape: redondeo, textStyle: textos.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: alturaBoton,
        shape: redondeo,
        textStyle: textos.labelLarge,
        side: BorderSide(color: esquema.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), textStyle: textos.labelLarge),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: esquema.primary,
      foregroundColor: esquema.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      extendedTextStyle: textos.labelLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Redondeo.lg)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: esquema.surfaceContainerLow,
      selectedColor: esquema.primaryContainer,
      checkmarkColor: esquema.onPrimaryContainer,
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.selected) ? esquema.primary : esquema.outlineVariant),
      ),
      labelStyle: textos.labelLarge?.copyWith(color: esquema.onSurface),
      secondaryLabelStyle: textos.labelLarge?.copyWith(color: esquema.onPrimaryContainer),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Redondeo.sm)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: esquema.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: Espacio.md, vertical: Espacio.md),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Redondeo.md)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Redondeo.md),
        borderSide: BorderSide(color: esquema.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Redondeo.md),
        borderSide: BorderSide(color: esquema.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: esquema.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: esquema.primaryContainer,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(textos.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: Espacio.md, vertical: Espacio.xxs),
      minVerticalPadding: Espacio.sm,
      titleTextStyle: textos.titleMedium,
      subtitleTextStyle: textos.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(color: esquema.outlineVariant, space: 1, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: redondeo,
      backgroundColor: oscuro ? const Color(0xFF14223C) : const Color(0xFF0B1324),
      contentTextStyle: textos.bodyMedium?.copyWith(color: const Color(0xFFF1F5F9)),
      actionTextColor: oscuro ? esquema.primary : const Color(0xFF67E8F9),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: esquema.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Redondeo.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: esquema.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Redondeo.xl)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? esquema.onPrimary : esquema.outline,
      ),
    ),
  );
}
