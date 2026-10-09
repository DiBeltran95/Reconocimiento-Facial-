import '../core/formato.dart';
import '../data/almacen_local.dart';
import '../data/modelos.dart';
import 'sincronizador.dart';

/// Mensaje de puntualidad que el kiosco muestra al registrar.
class Puntualidad {
  const Puntualidad(this.texto, {required this.aTiempo});
  final String texto;
  final bool aTiempo;
}

class Evaluacion {
  const Evaluacion({required this.sugerido, this.ultima, required this.enEspera});

  /// Tipo que corresponde según su última marcación de hoy.
  final TipoMarcacion sugerido;
  final Marcacion? ultima;

  /// true si acaba de marcar (evita registros dobles).
  final bool enEspera;
}

/// Reglas de negocio de la marcación. Lo único que se registra es:
/// empleado, tipo y hora del dispositivo (la hora del servidor la pone él).
class Asistencia {
  Asistencia(this._almacen, this._sync);

  final AlmacenLocal _almacen;
  final Sincronizador _sync;

  static DateTime inicioDelDia([DateTime? ahora]) {
    final a = ahora ?? DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  Future<Evaluacion> evaluar(int empleadoId, {required int minutosEspera}) async {
    final ultima = await _almacen.ultimaMarcacion(empleadoId, inicioDelDia());
    if (ultima == null) {
      return const Evaluacion(sugerido: TipoMarcacion.entrada, enEspera: false);
    }
    final transcurrido = DateTime.now().toUtc().difference(ultima.hora.toUtc());
    return Evaluacion(
      sugerido: ultima.tipo.opuesto,
      ultima: ultima,
      enEspera: transcurrido.inSeconds >= 0 && transcurrido.inMinutes < minutosEspera,
    );
  }

  /// Compara la hora de la marcación con el turno de hoy del empleado.
  /// Devuelve null si no tiene turno hoy (no hay nada que evaluar).
  static Puntualidad? puntualidad(EmpleadoLocal e, TipoMarcacion tipo, DateTime hora) {
    final local = hora.toLocal();
    final bloques = e.turnoDe(local);
    if (bloques == null || bloques.isEmpty) return null;
    final m = local.hour * 60 + local.minute;

    if (tipo == TipoMarcacion.entrada) {
      // Bloque en curso o el próximo por empezar.
      final b = bloques.where((b) => m < b.fin).firstOrNull;
      if (b == null) return const Puntualidad('Fuera de tu turno de hoy', aTiempo: false);
      final retraso = m - b.inicio;
      return retraso <= e.tolerancia
          ? const Puntualidad('A tiempo', aTiempo: true)
          : Puntualidad('Llegaste ${Formato.duracion(retraso)} tarde', aTiempo: false);
    }

    // Salida: el bloque que está terminando (el último que ya empezó).
    final b = bloques.where((b) => b.inicio <= m).lastOrNull;
    if (b == null) return const Puntualidad('Aún no empieza tu turno', aTiempo: false);
    final anticipo = b.fin - m;
    return anticipo <= e.tolerancia
        ? const Puntualidad('Salida a tiempo', aTiempo: true)
        : Puntualidad('Sales ${Formato.duracion(anticipo)} antes de lo programado', aTiempo: false);
  }

  Future<Marcacion> registrar(int empleadoId, TipoMarcacion tipo) async {
    final ahora = DateTime.now().toUtc();
    final marcacion = Marcacion(
      empleadoId: empleadoId,
      tipo: tipo,
      // Truncada a segundos: coincide con DATETIME del servidor (idempotencia).
      hora: DateTime.utc(ahora.year, ahora.month, ahora.day, ahora.hour, ahora.minute, ahora.second),
    );
    await _almacen.insertarMarcacion(marcacion);
    _sync.enviarPronto();
    return marcacion;
  }
}
