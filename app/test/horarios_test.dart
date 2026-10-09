import 'package:control_personal/core/formato.dart';
import 'package:control_personal/data/modelos.dart';
import 'package:control_personal/servicios/asistencia.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bloques de turno', () {
    test('texto ↔ minutos', () {
      final b = bloquesDesdeTexto('08:30-12:00,14:00-18:00');
      expect(b, [(inicio: 510, fin: 720), (inicio: 840, fin: 1080)]);
      expect(bloquesATexto(b), '08:30-12:00,14:00-18:00');
      expect(Formato.bloques('08:30-12:00,14:00-18:00'), '08:30–12:00 · 14:00–18:00');
    });

    test('días de la semana como máscara', () {
      expect(DiasSemana.texto(63), 'Lunes a sábado');
      expect(DiasSemana.texto(31), 'Lunes a viernes');
      expect(DiasSemana.texto(1 | 4 | 16), 'L · X · V');
      expect(DiasSemana.incluye(63, 5), isTrue); // sábado
      expect(DiasSemana.incluye(63, 6), isFalse); // domingo
    });

    test('lunes de la semana', () {
      expect(Formato.lunes(DateTime(2026, 10, 8)), DateTime(2026, 10, 5)); // jueves → lunes
      expect(Formato.lunes(DateTime(2026, 10, 11)), DateTime(2026, 10, 5)); // domingo → lunes anterior
      expect(Formato.lunes(DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
    });
  });

  group('Puntualidad en el kiosco', () {
    final hoy = DateTime(2026, 10, 8);
    final empleado = EmpleadoLocal(
      id: 1,
      documento: '1',
      nombre: 'Ana',
      turnoHoy: '08:30-12:00,14:00-18:00',
      turnoFecha: '2026-10-08',
      tolerancia: 10,
    );
    DateTime a(int h, int m) => DateTime(hoy.year, hoy.month, hoy.day, h, m);

    test('entrada dentro de la tolerancia es a tiempo', () {
      final p = Asistencia.puntualidad(empleado, TipoMarcacion.entrada, a(8, 38))!;
      expect(p.aTiempo, isTrue);
    });

    test('entrada tarde informa los minutos', () {
      final p = Asistencia.puntualidad(empleado, TipoMarcacion.entrada, a(8, 52))!;
      expect(p.aTiempo, isFalse);
      expect(p.texto, contains('22 min'));
    });

    test('regreso del almuerzo se evalúa contra el segundo bloque', () {
      expect(Asistencia.puntualidad(empleado, TipoMarcacion.entrada, a(13, 55))!.aTiempo, isTrue);
      expect(Asistencia.puntualidad(empleado, TipoMarcacion.entrada, a(14, 30))!.texto, contains('30 min'));
    });

    test('salida anticipada y salida a tiempo', () {
      expect(Asistencia.puntualidad(empleado, TipoMarcacion.salida, a(17, 20))!.aTiempo, isFalse);
      expect(Asistencia.puntualidad(empleado, TipoMarcacion.salida, a(18, 2))!.aTiempo, isTrue);
      expect(Asistencia.puntualidad(empleado, TipoMarcacion.salida, a(12, 0))!.aTiempo, isTrue);
    });

    test('sin turno hoy no evalúa (turno de otro día)', () {
      final ayer = EmpleadoLocal(id: 2, documento: '2', nombre: 'B', turnoHoy: '08:00-17:00', turnoFecha: '2026-10-07');
      expect(Asistencia.puntualidad(ayer, TipoMarcacion.entrada, a(9, 0)), isNull);
    });
  });
}
