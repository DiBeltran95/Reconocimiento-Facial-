import 'package:intl/intl.dart';

/// Formatos de fecha y hora en español de Colombia.
abstract final class Formato {
  static final _hora = DateFormat('h:mm a', 'es_CO');
  static final _horaSeg = DateFormat('h:mm:ss a', 'es_CO');
  static final _reloj = DateFormat('HH:mm', 'es_CO');
  static final _fechaLarga = DateFormat("EEEE, d 'de' MMMM", 'es_CO');
  static final _fechaCorta = DateFormat('d MMM y', 'es_CO');
  static final _fechaIso = DateFormat('yyyy-MM-dd');

  static String hora(DateTime f) => _limpiarAmPm(_hora.format(f.toLocal()));
  static String horaConSegundos(DateTime f) => _limpiarAmPm(_horaSeg.format(f.toLocal()));
  static String reloj(DateTime f) => _reloj.format(f.toLocal());
  static String fechaLarga(DateTime f) => _capitalizar(_fechaLarga.format(f.toLocal()));
  static String fechaCorta(DateTime f) => _fechaCorta.format(f.toLocal());
  static String fechaIso(DateTime f) => _fechaIso.format(f);

  static String duracion(int minutos) {
    if (minutos <= 0) return '0 min';
    final h = minutos ~/ 60;
    final m = minutos % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
  }

  static String haceCuanto(DateTime? f) {
    if (f == null) return 'nunca';
    final d = DateTime.now().difference(f);
    if (d.inSeconds < 60) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return fechaCorta(f);
  }

  /// '08:30-12:00,14:00-18:00' → '08:30–12:00 · 14:00–18:00'
  static String bloques(String texto) => texto
      .split(',')
      .where((b) => b.contains('-'))
      .map((b) => b.replaceAll('-', '–'))
      .join(' · ');

  /// "28 de septiembre"
  static String diaMes(DateTime f) => DateFormat("d 'de' MMMM", 'es_CO').format(f);

  /// Semana: "6 – 12 oct".
  static String semana(DateTime lunes) {
    final domingo = lunes.add(const Duration(days: 6));
    final mes = DateFormat('MMM', 'es_CO');
    return lunes.month == domingo.month
        ? '${lunes.day} – ${domingo.day} ${mes.format(domingo)}'
        : '${lunes.day} ${mes.format(lunes)} – ${domingo.day} ${mes.format(domingo)}';
  }

  /// Lunes de la semana de [f] (sin hora).
  static DateTime lunes(DateTime f) {
    final d = DateTime(f.year, f.month, f.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  /// Iniciales para avatares: "Diego Beltrán" → "DB".
  static String iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes.first.substring(0, 1) + partes[1].substring(0, 1)).toUpperCase();
  }

  /// Primer nombre para saludar: "Diego Beltrán" → "Diego".
  static String primerNombre(String nombre) => nombre.trim().split(RegExp(r'\s+')).first;

  static String _capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // "7:58 a. m." → "7:58 a. m." (normaliza espacios no separables de ICU)
  static String _limpiarAmPm(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');
}
