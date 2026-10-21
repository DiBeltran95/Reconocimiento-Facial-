import 'package:flutter/foundation.dart';

import '../../data/api.dart';
import '../../data/modelos.dart';

/// Estado compartido por las pestañas del panel: sedes visibles, la elegida
/// y el catálogo de turnos.
class ContextoAdmin extends ChangeNotifier {
  /// [sedes] no puede venir vacía. [sedeDispositivo]: la sede de este teléfono
  /// si es punto de marcación (se elige primero).
  ContextoAdmin({required this.api, required List<Sede> sedes, this.sedeDispositivo})
      : assert(sedes.isNotEmpty),
        sedes = sedes,
        sede = sedes.firstWhere((s) => s.id == sedeDispositivo?.id, orElse: () => sedes.first);

  final Api api;
  final Sede? sedeDispositivo;
  List<Sede> sedes;
  Sede sede;
  String? error;

  List<Horario>? _horarios;
  List<Horario> get horarios => _horarios ?? const [];

  Future<void> cargarSedes() async {
    try {
      final lista = await api.sedes();
      if (lista.isNotEmpty) {
        sedes = lista;
        sede = lista.firstWhere((s) => s.id == sede.id, orElse: () => lista.first);
      }
      error = null;
    } on ApiError catch (e) {
      error = e.mensaje;
    }
    notifyListeners();
  }

  Future<List<Horario>> cargarHorarios({bool forzar = false}) async {
    if (_horarios == null || forzar) {
      _horarios = await api.horarios();
      notifyListeners();
    }
    return _horarios!;
  }

  Horario? horario(int id) => horarios.where((h) => h.id == id).firstOrNull;

  void elegirSede(Sede s) {
    if (s.id == sede.id) return;
    sede = s;
    notifyListeners();
  }
}
