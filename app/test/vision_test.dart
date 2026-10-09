import 'dart:math' as math;
import 'dart:typed_data';

import 'package:control_personal/core/formato.dart';
import 'package:control_personal/data/modelos.dart';
import 'package:control_personal/vision/alineador.dart';
import 'package:control_personal/vision/comparador.dart';
import 'package:control_personal/vision/embebedor.dart';
import 'package:control_personal/vision/fuente_pixeles.dart';
import 'package:flutter_test/flutter_test.dart';

/// Imagen RGB sintética con cuadros blancos (los "ojos") sobre fondo negro.
FuenteRgb _imagenConOjos(int ancho, int alto, List<Offset> ojos, {int radio = 3}) {
  final bytes = Uint8List(ancho * alto * 3);
  for (final o in ojos) {
    for (var y = o.dy.round() - radio; y <= o.dy.round() + radio; y++) {
      for (var x = o.dx.round() - radio; x <= o.dx.round() + radio; x++) {
        if (x < 0 || y < 0 || x >= ancho || y >= alto) continue;
        final i = (y * ancho + x) * 3;
        bytes[i] = 255;
        bytes[i + 1] = 255;
        bytes[i + 2] = 255;
      }
    }
  }
  return FuenteRgb(bytes, ancho, alto);
}

double _canalR(Float32List t, int tam, int x, int y) => t[(y * tam + x) * 3];

void main() {
  group('FuenteNv21', () {
    // Cuadro crudo 4×2 en horizontal; Y distinto por píxel, croma neutra.
    final y = [10, 20, 30, 40, 50, 60, 70, 80];
    final nv21 = Uint8List.fromList([...y, 128, 128, 128, 128]);

    int gris(FuentePixeles f, int x, int yy) => f.rgb(x, yy) & 0xFF;

    test('sin rotación lee el píxel crudo', () {
      final f = FuenteNv21(nv21, 4, 2, 4, 0);
      expect((f.ancho, f.alto), (4, 2));
      expect(gris(f, 0, 0), 10);
      expect(gris(f, 3, 1), 80);
    });

    test('rotación 90° (horario): la esquina inferior izquierda queda arriba a la izquierda', () {
      final f = FuenteNv21(nv21, 4, 2, 4, 90);
      expect((f.ancho, f.alto), (2, 4));
      expect(gris(f, 0, 0), 50); // crudo (0,1)
      expect(gris(f, 1, 0), 10); // crudo (0,0)
      expect(gris(f, 0, 3), 80); // crudo (3,1)
    });

    test('rotación 270°: la esquina superior derecha queda arriba a la izquierda', () {
      final f = FuenteNv21(nv21, 4, 2, 4, 270);
      expect((f.ancho, f.alto), (2, 4));
      expect(gris(f, 0, 0), 40); // crudo (3,0)
      expect(gris(f, 1, 3), 50); // crudo (0,1)
    });

    test('fuera de la imagen devuelve negro', () {
      final f = FuenteNv21(nv21, 4, 2, 4, 90);
      expect(f.rgb(-1, 0), 0);
      expect(f.rgb(2, 0), 0);
    });
  });

  group('Alineador', () {
    const tam = 112;
    // Posiciones de los ojos en la plantilla ArcFace (112×112).
    const izqPlantilla = (38, 52);
    const derPlantilla = (74, 52);

    test('lleva los ojos a la posición canónica', () {
      final f = _imagenConOjos(300, 300, const [Offset(100, 140), Offset(200, 140)]);
      final t = Alineador.entrada(f, (const Offset(100, 140), const Offset(200, 140)), tam);
      expect(_canalR(t, tam, izqPlantilla.$1, izqPlantilla.$2), greaterThan(0.9));
      expect(_canalR(t, tam, derPlantilla.$1, derPlantilla.$2), greaterThan(0.9));
      expect(_canalR(t, tam, 56, 90), lessThan(-0.9)); // boca: fondo negro
    });

    test('endereza un rostro inclinado 30°', () {
      const centro = Offset(150, 150);
      const d = 50.0;
      final a = math.pi / 6;
      final izq = Offset(centro.dx - d * math.cos(a), centro.dy - d * math.sin(a));
      final der = Offset(centro.dx + d * math.cos(a), centro.dy + d * math.sin(a));
      final f = _imagenConOjos(300, 300, [izq, der]);
      final t = Alineador.entrada(f, (izq, der), tam);
      expect(_canalR(t, tam, izqPlantilla.$1, izqPlantilla.$2), greaterThan(0.5));
      expect(_canalR(t, tam, derPlantilla.$1, derPlantilla.$2), greaterThan(0.5));
    });

    test('la versión espejo refleja horizontalmente', () {
      // Solo el ojo izquierdo marcado: en el espejo debe aparecer a la derecha.
      final f = _imagenConOjos(300, 300, const [Offset(100, 140)]);
      final ojos = (const Offset(100, 140), const Offset(200, 140));
      final normal = Alineador.entrada(f, ojos, tam);
      final espejo = Alineador.entrada(f, ojos, tam, espejo: true);
      expect(_canalR(normal, tam, izqPlantilla.$1, izqPlantilla.$2), greaterThan(0.9));
      expect(_canalR(espejo, tam, tam - 1 - izqPlantilla.$1, izqPlantilla.$2), greaterThan(0.9));
      expect(_canalR(espejo, tam, izqPlantilla.$1, izqPlantilla.$2), lessThan(0));
    });
  });

  group('Comparador', () {
    Float32List v(List<double> x) => Embebedor.normalizar(Float32List.fromList(x));

    test('elige a la persona más parecida e informa el margen', () {
      final c = Comparador()
        ..cargar([
          VectorRostro(1, v([1, 0, 0])),
          VectorRostro(1, v([0.9, 0.1, 0])),
          VectorRostro(2, v([0, 1, 0])),
          VectorRostro(3, v([0.7, 0.7, 0])),
        ]);
      final r = c.buscar(v([1, 0.05, 0]))!;
      expect(r.empleadoId, 1);
      expect(r.similitud, greaterThan(0.99));
      expect(r.segundo, closeTo(0.74, 0.02)); // persona 3
      expect(c.personas, 3);
    });

    test('puede excluir a una persona (verificación de duplicados)', () {
      final c = Comparador()..cargar([VectorRostro(1, v([1, 0])), VectorRostro(2, v([0, 1]))]);
      expect(c.buscar(v([1, 0]), excluir: 1)!.empleadoId, 2);
    });

    test('vacío devuelve null', () {
      expect(Comparador().buscar(v([1, 0])), isNull);
    });
  });

  group('Formato', () {
    test('iniciales y primer nombre', () {
      expect(Formato.iniciales('Diego Beltrán'), 'DB');
      expect(Formato.iniciales('  ana '), 'A');
      expect(Formato.primerNombre('María José Pérez'), 'María');
    });

    test('duración legible', () {
      expect(Formato.duracion(0), '0 min');
      expect(Formato.duracion(45), '45 min');
      expect(Formato.duracion(120), '2 h');
      expect(Formato.duracion(485), '8 h 05 min');
    });
  });

  group('Modelos', () {
    test('la marcación viaja en UTC con zona explícita', () {
      final m = Marcacion(empleadoId: 7, tipo: TipoMarcacion.salida, hora: DateTime.utc(2026, 10, 8, 22, 1, 5));
      expect(m.aJsonApi(), {'empleado_id': 7, 'tipo': 'SALIDA', 'hora': '2026-10-08T22:01:05.000Z'});
    });

    test('firma de fotos cambia si cambia una versión', () {
      const a = EmpleadoRemoto(id: 1, documento: '1', nombre: 'A', fotos: [FotoRef(1, 100), FotoRef(2, 200)]);
      const b = EmpleadoRemoto(id: 1, documento: '1', nombre: 'A', fotos: [FotoRef(1, 100), FotoRef(2, 201)]);
      expect(a.firmaFotos == b.firmaFotos, isFalse);
    });
  });
}
