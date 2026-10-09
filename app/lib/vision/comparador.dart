import 'dart:typed_data';

import '../data/modelos.dart';
import 'embebedor.dart';

class Coincidencia {
  const Coincidencia(this.empleadoId, this.similitud, this.segundo);

  final int empleadoId;

  /// Similitud coseno con la mejor foto de esa persona (0 … 1).
  final double similitud;

  /// Mejor similitud de cualquier OTRA persona: si está muy cerca, es ambiguo.
  final double segundo;

  double get margen => similitud - segundo;
}

/// Índice en memoria de todos los vectores de la sede. Con cientos de
/// empleados la búsqueda lineal tarda menos de 5 ms.
class Comparador {
  List<VectorRostro> _vectores = const [];

  bool get vacio => _vectores.isEmpty;
  int get personas => _vectores.map((v) => v.empleadoId).toSet().length;

  void cargar(List<VectorRostro> vectores) => _vectores = List.unmodifiable(vectores);

  Coincidencia? buscar(Float32List consulta, {int? excluir}) {
    final mejorPorPersona = <int, double>{};
    for (final v in _vectores) {
      if (v.empleadoId == excluir) continue;
      final s = Embebedor.similitud(consulta, v.valores);
      final actual = mejorPorPersona[v.empleadoId];
      if (actual == null || s > actual) mejorPorPersona[v.empleadoId] = s;
    }
    if (mejorPorPersona.isEmpty) return null;

    var mejorId = -1;
    var mejor = -2.0;
    var segundo = -1.0;
    mejorPorPersona.forEach((id, s) {
      if (s > mejor) {
        segundo = mejor;
        mejor = s;
        mejorId = id;
      } else if (s > segundo) {
        segundo = s;
      }
    });
    return Coincidencia(mejorId, mejor, segundo.clamp(-1.0, 1.0));
  }
}
