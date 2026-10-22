import 'package:control_personal/data/api.dart';
import 'package:control_personal/data/modelos.dart';
import 'package:control_personal/servicios/sesion_admin.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

SesionAdmin _sesion({Duration vence = const Duration(days: 30)}) => SesionAdmin(
      token: 'tok',
      nombre: 'Diana',
      email: 'diana@ej.co',
      rol: Rol.administrativo,
      rolAsistencia: RolAsistencia.admin,
      empresa: const EmpresaRef(uuid: 'e-1', nombre: 'Krenovapp'),
      expira: DateTime.now().add(vence),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('la sesión se guarda y vuelve al abrir la app otra vez (sin internet)', () async {
    final antes = SesionAdminCtrl()..api = Api(baseUrl: 'https://ejemplo.invalid');
    antes.adoptar(_sesion());
    await Future<void>.delayed(Duration.zero);

    // «Cerrar y abrir la app»: un controlador nuevo, sin red.
    final despues = SesionAdminCtrl()..api = Api(baseUrl: 'https://ejemplo.invalid');
    await despues.restaurar();
    expect(despues.activa, isTrue);
    expect(despues.sesion!.nombre, 'Diana');
    expect(despues.sesion!.esAdminEmpresa, isTrue);
    expect(despues.api!.tokenAdmin, 'tok');
  });

  test('cerrar sesión la olvida', () async {
    final s = SesionAdminCtrl()..adoptar(_sesion());
    await Future<void>.delayed(Duration.zero);
    s.cerrar();
    await Future<void>.delayed(Duration.zero);
    final otra = SesionAdminCtrl();
    await otra.restaurar();
    expect(otra.activa, isFalse);
  });

  test('una sesión vencida no se restaura', () async {
    SesionAdminCtrl().adoptar(_sesion(vence: const Duration(seconds: -1)));
    await Future<void>.delayed(Duration.zero);
    final otra = SesionAdminCtrl();
    await otra.restaurar();
    expect(otra.activa, isFalse);
  });

  test('en un teléfono de marcación la sesión no se guarda', () async {
    final s = SesionAdminCtrl()
      ..recordada = false
      ..adoptar(_sesion());
    await Future<void>.delayed(Duration.zero);
    expect(s.activa, isTrue);
    final otra = SesionAdminCtrl();
    await otra.restaurar();
    expect(otra.activa, isFalse, reason: 'el teléfono es público: al cerrar la app no queda sesión');
    s.cerrar();
  });

  test('vincular el teléfono olvida la sesión que estaba guardada', () async {
    final s = SesionAdminCtrl()..adoptar(_sesion());
    await Future<void>.delayed(Duration.zero);
    s.recordada = false;
    await Future<void>.delayed(Duration.zero);
    final otra = SesionAdminCtrl();
    await otra.restaurar();
    expect(otra.activa, isFalse);
    s.cerrar();
  });

  test('las sedes del panel quedan guardadas para abrir sin internet', () async {
    final s = SesionAdminCtrl();
    await s.guardarSedes(const [Sede(id: 1, nombre: 'Centro', codigo: 'CEN')]);
    final sedes = await SesionAdminCtrl().sedesGuardadas();
    expect(sedes.single.nombre, 'Centro');
  });

  test('la sesión se puede guardar y leer', () {
    final copia = SesionAdmin.desdeJson(_sesion().aJson())!;
    expect(copia.email, 'diana@ej.co');
    expect(copia.empresa!.nombre, 'Krenovapp');
    expect(copia.esAdministrativo, isTrue);
    expect(SesionAdmin.desdeJson({'token': 1}), isNull);
  });
}
