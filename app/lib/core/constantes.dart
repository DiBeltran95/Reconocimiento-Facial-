/// Parámetros del sistema. Los marcados como "ajustable" tienen un valor por
/// defecto aquí y el administrador puede cambiarlos desde el dispositivo.
abstract final class Constantes {
  /// Modelo de embeddings faciales (MobileFaceNet, entrada 112×112×3 float32).
  static const rutaModelo = 'assets/modelos/mobilefacenet.tflite';

  /// Normalización de píxeles que espera el modelo: (p - media) / escala.
  static const modeloMedia = 127.5;
  static const modeloEscala = 128.0;

  /// Similitud coseno mínima para aceptar a alguien (ajustable 0.50 – 0.85).
  static const umbralPorDefecto = 0.62;

  /// Diferencia mínima con el segundo candidato: evita confundir parecidos.
  static const margenSegundo = 0.06;

  /// Cuadros consecutivos que deben coincidir con la misma persona.
  static const votosNecesarios = 2;

  /// Intentos sin coincidencia antes de mostrar "no te reconocemos".
  static const intentosMaximos = 10;

  /// Tamaño mínimo del rostro respecto al ancho de la imagen.
  static const rostroMinimo = 0.30;

  /// Ángulos máximos de la cabeza (grados) para considerar "de frente".
  static const anguloMaximo = 18.0;

  /// Segundos antes de confirmar automáticamente la marcación sugerida.
  static const segundosAutoConfirmar = 4;

  /// Minutos en que se ignora una nueva marcación de la misma persona
  /// (evita dobles registros por pasar dos veces frente al kiosco). Ajustable.
  static const minutosEsperaPorDefecto = 2;

  /// Frecuencia de sincronización en segundo plano.
  static const intervaloSync = Duration(minutes: 3);

  /// Desfase de reloj (segundos) a partir del cual se avisa en el kiosco.
  static const desfaseRelojMaximo = 120;

  /// Días que se conservan en el teléfono las marcaciones ya enviadas.
  static const diasHistorialLocal = 3;

  /// Minutos de inactividad que cierran la sesión de administración.
  static const minutosSesionAdmin = 5;

  /// Fotos guiadas en el registro facial.
  static const fotosEnrolamiento = 3;
}
