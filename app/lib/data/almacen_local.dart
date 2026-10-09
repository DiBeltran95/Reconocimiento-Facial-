import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constantes.dart';
import 'modelos.dart';

/// Base de datos del teléfono. Aquí vive todo lo necesario para reconocer y
/// registrar sin conexión: empleados, fotos, vectores faciales y la cola de
/// marcaciones pendientes por enviar.
class AlmacenLocal {
  AlmacenLocal._(this._db, this.carpetaFotos);

  final Database _db;
  final Directory carpetaFotos;

  static Future<AlmacenLocal> abrir() async {
    final docs = await getApplicationDocumentsDirectory();
    final fotos = Directory(p.join(docs.path, 'rostros'));
    if (!fotos.existsSync()) fotos.createSync(recursive: true);

    final db = await openDatabase(
      p.join(docs.path, 'control_personal.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        final b = db.batch()
          ..execute('''
            CREATE TABLE empleados(
              id INTEGER PRIMARY KEY,
              documento TEXT NOT NULL,
              nombre TEXT NOT NULL,
              cargo TEXT,
              firma_fotos TEXT NOT NULL DEFAULT '',
              turno_hoy TEXT,
              turno_fecha TEXT,
              tolerancia INTEGER NOT NULL DEFAULT 10
            )''')
          ..execute('''
            CREATE TABLE fotos(
              empleado_id INTEGER NOT NULL REFERENCES empleados(id) ON DELETE CASCADE,
              n INTEGER NOT NULL,
              v INTEGER NOT NULL,
              ruta TEXT NOT NULL,
              con_rostro INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (empleado_id, n)
            )''')
          ..execute('''
            CREATE TABLE vectores(
              empleado_id INTEGER NOT NULL REFERENCES empleados(id) ON DELETE CASCADE,
              n INTEGER NOT NULL,
              espejo INTEGER NOT NULL,
              vector BLOB NOT NULL,
              PRIMARY KEY (empleado_id, n, espejo)
            )''')
          ..execute('''
            CREATE TABLE marcaciones(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              empleado_id INTEGER NOT NULL,
              tipo TEXT NOT NULL,
              hora TEXT NOT NULL,
              enviada INTEGER NOT NULL DEFAULT 0,
              UNIQUE (empleado_id, hora)
            )''')
          ..execute('CREATE INDEX idx_marc_pend ON marcaciones(enviada, id)')
          ..execute('CREATE INDEX idx_marc_hora ON marcaciones(hora)')
          ..execute('CREATE TABLE ajustes(clave TEXT PRIMARY KEY, valor TEXT NOT NULL)');
        await b.commit(noResult: true);
      },
    );
    return AlmacenLocal._(db, fotos);
  }

  // -------------------------------------------------------------------------
  // Empleados y fotos
  // -------------------------------------------------------------------------

  Future<List<EmpleadoLocal>> empleados() async {
    final filas = await _db.rawQuery('''
      SELECT e.id, e.documento, e.nombre, e.cargo, e.turno_hoy, e.turno_fecha, e.tolerancia,
             (SELECT ruta FROM fotos f WHERE f.empleado_id = e.id ORDER BY f.n LIMIT 1) AS ruta_foto,
             (SELECT COUNT(*) FROM vectores v WHERE v.empleado_id = e.id) AS vectores
        FROM empleados e
       ORDER BY e.nombre COLLATE NOCASE''');
    return filas.map(_empleadoDesdeFila).toList();
  }

  Future<EmpleadoLocal?> empleado(int id) async {
    final filas = await _db.rawQuery('''
      SELECT e.id, e.documento, e.nombre, e.cargo, e.turno_hoy, e.turno_fecha, e.tolerancia,
             (SELECT ruta FROM fotos f WHERE f.empleado_id = e.id ORDER BY f.n LIMIT 1) AS ruta_foto,
             (SELECT COUNT(*) FROM vectores v WHERE v.empleado_id = e.id) AS vectores
        FROM empleados e WHERE e.id = ?''', [id]);
    return filas.isEmpty ? null : _empleadoDesdeFila(filas.first);
  }

  EmpleadoLocal _empleadoDesdeFila(Map<String, Object?> f) => EmpleadoLocal(
        id: f['id']! as int,
        documento: f['documento']! as String,
        nombre: f['nombre']! as String,
        cargo: f['cargo'] as String?,
        rutaFoto: f['ruta_foto'] as String?,
        vectores: (f['vectores'] as int?) ?? 0,
        turnoHoy: f['turno_hoy'] as String?,
        turnoFecha: f['turno_fecha'] as String?,
        tolerancia: (f['tolerancia'] as int?) ?? 10,
      );

  /// Firmas de fotos ya procesadas: {empleadoId: "1:1728400000,2:..."}.
  Future<Map<int, String>> firmasFotos() async {
    final filas = await _db.query('empleados', columns: ['id', 'firma_fotos']);
    return {for (final f in filas) f['id']! as int: f['firma_fotos']! as String};
  }

  Future<Map<int, int>> versionesFotos(int empleadoId) async {
    final filas = await _db.query('fotos', columns: ['n', 'v'], where: 'empleado_id = ?', whereArgs: [empleadoId]);
    return {for (final f in filas) f['n']! as int: f['v']! as int};
  }

  /// Inserta o actualiza los datos (y el turno del día [fecha]) sin tocar sus rostros.
  Future<void> guardarDatosEmpleado(EmpleadoRemoto e, {String? fecha}) async {
    final datos = {
      'documento': e.documento,
      'nombre': e.nombre,
      'cargo': e.cargo,
      if (fecha != null) ...{'turno_hoy': e.turnoHoy, 'turno_fecha': fecha, 'tolerancia': e.tolerancia},
    };
    final insertado = await _db.insert('empleados', {'id': e.id, ...datos}, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (insertado == 0) await _db.update('empleados', datos, where: 'id = ?', whereArgs: [e.id]);
  }

  /// Reemplaza fotos y vectores de un empleado en una sola transacción.
  Future<void> guardarRostro({
    required int empleadoId,
    required String firma,
    required List<({int n, int v, String ruta, List<Float32List> vectores})> fotos,
  }) async {
    await _db.transaction((tx) async {
      await tx.delete('vectores', where: 'empleado_id = ?', whereArgs: [empleadoId]);
      await tx.delete('fotos', where: 'empleado_id = ?', whereArgs: [empleadoId]);
      for (final f in fotos) {
        await tx.insert('fotos', {
          'empleado_id': empleadoId,
          'n': f.n,
          'v': f.v,
          'ruta': f.ruta,
          'con_rostro': f.vectores.isEmpty ? 0 : 1,
        });
        for (var i = 0; i < f.vectores.length; i++) {
          await tx.insert('vectores', {
            'empleado_id': empleadoId,
            'n': f.n,
            'espejo': i,
            'vector': f.vectores[i].buffer.asUint8List(),
          });
        }
      }
      await tx.update('empleados', {'firma_fotos': firma}, where: 'id = ?', whereArgs: [empleadoId]);
    });
  }

  /// Elimina del teléfono a quien ya no está en la sede (y borra sus fotos).
  Future<void> borrarEmpleados(Iterable<int> ids) async {
    for (final id in ids) {
      final carpeta = carpetaDe(id);
      if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
      await _db.delete('empleados', where: 'id = ?', whereArgs: [id]);
    }
  }

  Directory carpetaDe(int empleadoId) => Directory(p.join(carpetaFotos.path, '$empleadoId'));

  Future<List<VectorRostro>> vectores() async {
    final filas = await _db.query('vectores', columns: ['empleado_id', 'vector']);
    return filas.map((f) {
      final bytes = f['vector']! as Uint8List;
      // Copia alineada: el blob puede no estar alineado a 4 bytes.
      final copia = Uint8List.fromList(bytes);
      return VectorRostro(f['empleado_id']! as int, copia.buffer.asFloat32List());
    }).toList();
  }

  Future<({int empleados, int reconocibles})> conteos() async {
    final e = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM empleados')) ?? 0;
    final r = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(DISTINCT empleado_id) FROM vectores')) ??
        0;
    return (empleados: e, reconocibles: r);
  }

  // -------------------------------------------------------------------------
  // Marcaciones
  // -------------------------------------------------------------------------

  Future<bool> insertarMarcacion(Marcacion m) async {
    final id = await _db.insert(
      'marcaciones',
      {
        'empleado_id': m.empleadoId,
        'tipo': m.tipo.api,
        'hora': m.hora.toUtc().toIso8601String(),
        'enviada': m.enviada ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  /// Incorpora las marcaciones de hoy hechas en otros kioscos de la sede.
  Future<void> fusionarRemotas(List<Marcacion> remotas) async {
    final b = _db.batch();
    for (final m in remotas) {
      b.insert(
        'marcaciones',
        {'empleado_id': m.empleadoId, 'tipo': m.tipo.api, 'hora': m.hora.toUtc().toIso8601String(), 'enviada': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await b.commit(noResult: true);
  }

  Future<List<Marcacion>> pendientes({int limite = 200}) async {
    final filas = await _db.query('marcaciones', where: 'enviada = 0', orderBy: 'id', limit: limite);
    return filas.map(_marcacionDesdeFila).toList();
  }

  Future<int> contarPendientes() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM marcaciones WHERE enviada = 0')) ?? 0;

  Future<void> marcarEnviadas(Iterable<int> idsLocales) async {
    if (idsLocales.isEmpty) return;
    final ids = idsLocales.toList();
    await _db.update(
      'marcaciones',
      {'enviada': 1},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<void> descartar(Iterable<int> idsLocales) async {
    if (idsLocales.isEmpty) return;
    final ids = idsLocales.toList();
    await _db.delete('marcaciones', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  /// Última marcación del empleado desde [desde] (inicio del día local).
  Future<Marcacion?> ultimaMarcacion(int empleadoId, DateTime desde) async {
    final filas = await _db.query(
      'marcaciones',
      where: 'empleado_id = ? AND hora >= ?',
      whereArgs: [empleadoId, desde.toUtc().toIso8601String()],
      orderBy: 'hora DESC',
      limit: 1,
    );
    return filas.isEmpty ? null : _marcacionDesdeFila(filas.first);
  }

  /// Marcaciones del día con nombre del empleado (para la lista del kiosco).
  Future<List<({Marcacion marcacion, String nombre})>> marcacionesDesde(DateTime desde) async {
    final filas = await _db.rawQuery('''
      SELECT m.*, e.nombre FROM marcaciones m
        JOIN empleados e ON e.id = m.empleado_id
       WHERE m.hora >= ? ORDER BY m.hora DESC''', [desde.toUtc().toIso8601String()]);
    return filas.map((f) => (marcacion: _marcacionDesdeFila(f), nombre: f['nombre']! as String)).toList();
  }

  /// Limpia historial ya enviado: el teléfono no es un archivo histórico.
  Future<void> limpiarHistorial() async {
    final limite = DateTime.now().subtract(const Duration(days: Constantes.diasHistorialLocal));
    await _db.delete('marcaciones', where: 'enviada = 1 AND hora < ?', whereArgs: [limite.toUtc().toIso8601String()]);
  }

  Marcacion _marcacionDesdeFila(Map<String, Object?> f) => Marcacion(
        idLocal: f['id']! as int,
        empleadoId: f['empleado_id']! as int,
        tipo: TipoMarcacion.desdeApi(f['tipo']! as String),
        hora: DateTime.parse(f['hora']! as String),
        enviada: f['enviada'] == 1,
      );

  // -------------------------------------------------------------------------
  // Ajustes y limpieza total
  // -------------------------------------------------------------------------

  Future<String?> ajuste(String clave) async {
    final filas = await _db.query('ajustes', where: 'clave = ?', whereArgs: [clave]);
    return filas.isEmpty ? null : filas.first['valor'] as String;
  }

  Future<void> guardarAjuste(String clave, String? valor) async {
    if (valor == null) {
      await _db.delete('ajustes', where: 'clave = ?', whereArgs: [clave]);
    } else {
      await _db.insert('ajustes', {'clave': clave, 'valor': valor}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Borra todos los datos locales (al desvincular el dispositivo).
  Future<void> borrarTodo() async {
    await _db.transaction((tx) async {
      for (final t in ['vectores', 'fotos', 'empleados', 'marcaciones', 'ajustes']) {
        await tx.delete(t);
      }
    });
    if (carpetaFotos.existsSync()) {
      carpetaFotos.deleteSync(recursive: true);
      carpetaFotos.createSync(recursive: true);
    }
  }
}
