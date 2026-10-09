import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import 'acceso_admin.dart';
import 'contexto_admin.dart';

/// Cuentas de la app: General (opera kioscos) y Administrativo (gestiona todo).
class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  late final Api _api = context.read<ContextoAdmin>().api;
  List<Usuario>? _usuarios;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await _api.usuarios();
      if (mounted) {
        setState(() {
          _usuarios = lista;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _abrir([Usuario? u]) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormUsuario(api: _api, usuario: u),
    );
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _usuarios;
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrir(),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Nuevo usuario'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: lista == null
            ? (_error != null
                ? ListView(children: [EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudo cargar', mensaje: _error, accion: _cargar)])
                : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, 96),
                children: [
                  _Explicacion(),
                  const SizedBox(height: Espacio.md),
                  if (lista.isEmpty)
                    const EstadoVacio(
                      icono: Icons.group_outlined,
                      titulo: 'Aún no hay cuentas propias',
                      mensaje: 'Crea una cuenta General para operar kioscos en las sedes.',
                    ),
                  for (final u in lista)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espacio.xs),
                      child: Card(
                        child: ListTile(
                          onTap: () => _abrir(u),
                          leading: AvatarEmpleado(nombre: u.nombre, tam: 44),
                          title: Text(u.nombre),
                          subtitle: Text('@${u.usuario}${u.activo ? '' : ' · inactivo'}'),
                          trailing: Pildora(
                            texto: u.rol.etiqueta,
                            color: u.rol == Rol.administrativo ? context.colores.primary : context.sem.salida,
                            icono: u.rol == Rol.administrativo ? Icons.shield_outlined : Icons.phone_android_rounded,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Explicacion extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget fila(IconData i, Color c, String t, String d) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacio.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, color: c, size: 20),
              const SizedBox(width: Espacio.sm),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$t: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: d),
                ])),
              ),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.md),
        child: Column(
          children: [
            fila(Icons.phone_android_rounded, context.sem.salida, 'General',
                'vincula y opera kioscos en cualquier sede. Solo registra asistencia por reconocimiento facial.'),
            fila(Icons.shield_outlined, context.colores.primary, 'Administrativo',
                'registra al personal, asigna y rota horarios, ve el cumplimiento, reportes y cuentas.'),
          ],
        ),
      ),
    );
  }
}

class _FormUsuario extends StatefulWidget {
  const _FormUsuario({required this.api, this.usuario});
  final Api api;
  final Usuario? usuario;

  @override
  State<_FormUsuario> createState() => _FormUsuarioState();
}

class _FormUsuarioState extends State<_FormUsuario> {
  late final _nombre = TextEditingController(text: widget.usuario?.nombre);
  late final _usuario = TextEditingController(text: widget.usuario?.usuario);
  final _clave = TextEditingController();
  late Rol _rol = widget.usuario?.rol ?? Rol.general;
  late bool _activo = widget.usuario?.activo ?? true;
  bool _guardando = false;
  bool _ocultar = true;
  String? _error;

  bool get _nuevo => widget.usuario == null;

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.api.guardarUsuario(
        id: widget.usuario?.id,
        nombre: _nombre.text.trim(),
        usuario: _nuevo ? _usuario.text.trim() : null,
        password: _clave.text,
        rol: _rol,
        activo: _activo,
      );
      if (mounted) {
        avisar(context, _nuevo ? 'Usuario creado' : 'Cambios guardados');
        Navigator.pop(context, true);
      }
    } on ApiError catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_nuevo ? 'Nuevo usuario' : 'Editar usuario', style: context.textos.headlineSmall),
            const SizedBox(height: Espacio.lg),
            SegmentedButton<Rol>(
              segments: const [
                ButtonSegment(value: Rol.general, icon: Icon(Icons.phone_android_rounded), label: Text('General')),
                ButtonSegment(value: Rol.administrativo, icon: Icon(Icons.shield_outlined), label: Text('Administrativo')),
              ],
              selected: {_rol},
              onSelectionChanged: (s) => setState(() => _rol = s.first),
            ),
            const SizedBox(height: Espacio.md),
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre completo', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: Espacio.md),
            TextField(
              controller: _usuario,
              enabled: _nuevo,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Usuario para ingresar',
                helperText: 'Ej.: kiosco.centro · sin espacios',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: Espacio.md),
            TextField(
              controller: _clave,
              obscureText: _ocultar,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: _nuevo ? 'Contraseña' : 'Nueva contraseña (opcional)',
                helperText: 'Mínimo 8 caracteres',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                  onPressed: () => setState(() => _ocultar = !_ocultar),
                  icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (!_nuevo)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
                title: const Text('Cuenta activa'),
                subtitle: const Text('Si la desactivas, ya no podrá ingresar.'),
              ),
            if (_error != null) ...[
              const SizedBox(height: Espacio.md),
              MensajeError(_error!),
            ],
            const SizedBox(height: Espacio.lg),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_nuevo ? 'Crear usuario' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
