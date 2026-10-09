import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../data/almacen_local.dart';

/// Preferencias del kiosco que el administrador puede ajustar.
class Ajustes extends ChangeNotifier {
  Ajustes(this._almacen);

  final AlmacenLocal _almacen;

  double umbral = Constantes.umbralPorDefecto;
  bool pruebaDeVida = true;
  int minutosEspera = Constantes.minutosEsperaPorDefecto;
  ThemeMode tema = ThemeMode.dark;
  bool sonido = true;

  Future<void> cargar() async {
    umbral = double.tryParse(await _almacen.ajuste('umbral') ?? '') ?? umbral;
    pruebaDeVida = (await _almacen.ajuste('prueba_vida') ?? '1') == '1';
    minutosEspera = int.tryParse(await _almacen.ajuste('minutos_espera') ?? '') ?? minutosEspera;
    sonido = (await _almacen.ajuste('sonido') ?? '1') == '1';
    tema = switch (await _almacen.ajuste('tema')) {
      'claro' => ThemeMode.light,
      'sistema' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    notifyListeners();
  }

  Future<void> cambiarUmbral(double v) async {
    umbral = v;
    notifyListeners();
    await _almacen.guardarAjuste('umbral', v.toStringAsFixed(2));
  }

  Future<void> cambiarPruebaDeVida(bool v) async {
    pruebaDeVida = v;
    notifyListeners();
    await _almacen.guardarAjuste('prueba_vida', v ? '1' : '0');
  }

  Future<void> cambiarMinutosEspera(int v) async {
    minutosEspera = v;
    notifyListeners();
    await _almacen.guardarAjuste('minutos_espera', '$v');
  }

  Future<void> cambiarSonido(bool v) async {
    sonido = v;
    notifyListeners();
    await _almacen.guardarAjuste('sonido', v ? '1' : '0');
  }

  Future<void> cambiarTema(ThemeMode v) async {
    tema = v;
    notifyListeners();
    await _almacen.guardarAjuste('tema', switch (v) {
      ThemeMode.light => 'claro',
      ThemeMode.system => 'sistema',
      ThemeMode.dark => 'oscuro',
    });
  }
}
