import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constantes.dart';

/// Convierte un rostro alineado en un vector (embedding) con MobileFaceNet.
/// La inferencia corre en un isolate aparte: la interfaz (y la animación del
/// HUD) nunca se congela mientras se reconoce a alguien.
class Embebedor {
  Embebedor._(this._interprete, this._aislado, this.tam, this.dimension);

  final Interpreter _interprete;
  final IsolateInterpreter _aislado;
  final int tam;
  final int dimension;

  Future<void> _cola = Future.value();

  static Future<Embebedor> cargar() async {
    final opciones = InterpreterOptions()..threads = 2;
    final interprete = await Interpreter.fromAsset(Constantes.rutaModelo, options: opciones);

    final entrada = interprete.getInputTensor(0);
    if (entrada.type != TensorType.float32 || entrada.shape.length != 4) {
      throw StateError('El modelo debe recibir float32 [1, N, N, 3]; recibe ${entrada.type} ${entrada.shape}');
    }
    final tam = entrada.shape[1];
    if (entrada.shape[0] != 1) {
      // Algunos MobileFaceNet exportados traen lote 2: se fija a 1.
      interprete.resizeInputTensor(0, [1, tam, tam, 3]);
    }
    interprete.allocateTensors();
    final dimension = interprete.getOutputTensor(0).shape.last;

    final aislado = await IsolateInterpreter.create(address: interprete.address);
    return Embebedor._(interprete, aislado, tam, dimension);
  }

  /// Vector L2-normalizado del rostro. Las llamadas se encolan (el intérprete
  /// en isolate solo atiende una a la vez).
  Future<Float32List> vector(Float32List entrada) {
    final resultado = Completer<Float32List>();
    _cola = _cola.then((_) async {
      try {
        final salida = Float32List(dimension);
        await _aislado.run(entrada.buffer, salida.buffer);
        resultado.complete(normalizar(salida));
      } catch (e, s) {
        resultado.completeError(e, s);
      }
    });
    return resultado.future;
  }

  static Float32List normalizar(Float32List v) {
    var suma = 0.0;
    for (final x in v) {
      suma += x * x;
    }
    final norma = math.sqrt(suma);
    if (norma == 0) return v;
    for (var i = 0; i < v.length; i++) {
      v[i] = v[i] / norma;
    }
    return v;
  }

  /// Similitud coseno entre vectores ya normalizados (−1 … 1).
  static double similitud(Float32List a, Float32List b) {
    var s = 0.0;
    final n = math.min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  Future<void> cerrar() async {
    await _aislado.close();
    _interprete.close();
  }
}
