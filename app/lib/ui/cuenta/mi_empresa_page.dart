import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../admin/acceso_admin.dart' show MensajeError;
import '../admin/componentes_kiosco.dart' show Seccion;
import '../comun/widgets.dart';
import 'plan_ui.dart';

/// Mi empresa: datos, plan y uso, apps habilitadas y eliminar la cuenta.
///
/// Todos los administrativos la ven; solo el administrador edita los datos y
/// puede eliminar la empresa. Cualquier persona puede eliminar su propia
/// cuenta (lo exige Google Play).
class MiEmpresaPage extends StatefulWidget {
  const MiEmpresaPage({super.key});

  @override
  State<MiEmpresaPage> createState() => _MiEmpresaPageState();
}

class _MiEmpresaPageState extends State<MiEmpresaPage> {
  late final EstadoApp _estado = context.read<EstadoApp>();
  Api get _api => _estado.api!;
  EmpresaInfo? _empresa;
  String? _error;

  bool get _esAdmin => _estado.sesion.sesion?.esAdminEmpresa ?? false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final e = await _api.empresa();
      if (mounted) {
        setState(() {
          _empresa = e;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _editar() async {
    final e = _empresa!;
    final cambiada = await showModalBottomSheet<EmpresaInfo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FormEmpresa(api: _api, empresa: e),
    );
    if (cambiada != null && mounted) {
      setState(() => _empresa = cambiada);
      avisar(context, 'Datos de la empresa guardados');
    }
  }

  Future<void> _eliminar() async {
    final eliminada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FormEliminar(api: _api, empresa: _empresa!, esAdmin: _esAdmin),
    );
    if (eliminada == true && mounted) {
      // La cuenta ya no existe: se cierra la sesión y se vuelve al kiosco.
      _estado.sesion.cerrar();
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _empresa;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi empresa')),
      body: FondoTecnico(
        intensidad: 0.6,
        child: e == null
            ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudo cargar', mensaje: _error, accion: _cargar))
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.xxl),
                  children: [
                    Seccion(
                      titulo: 'Empresa',
                      hijos: [
                        Text(e.nombre, style: context.textos.headlineSmall),
                        const SizedBox(height: Espacio.xxs),
                        Text(
                          [if (e.nit != null) 'NIT ${e.nit}', if (e.telefono != null) e.telefono!, if (e.email != null) e.email!]
                              .join(' · '),
                          style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
                        ),
                        if (_esAdmin) ...[
                          const SizedBox(height: Espacio.md),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _editar,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar datos'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Espacio.md),
                    if (e.plan != null) TarjetaPlan(plan: e.plan!),
                    const SizedBox(height: Espacio.md),
                    Seccion(
                      titulo: 'Apps de la plataforma',
                      hijos: [
                        _App(
                          icono: Icons.face_unlock_outlined,
                          nombre: 'Presente',
                          detalle: 'Asistencia con reconocimiento facial',
                          habilitada: e.aplicativos.contains('ASISTENCIA'),
                        ),
                        const Divider(),
                        _App(
                          icono: Icons.point_of_sale_outlined,
                          nombre: 'Ventario',
                          detalle: 'Ventas, stock y caja. Mismo correo y contraseña.',
                          habilitada: e.tieneInventario,
                        ),
                      ],
                    ),
                    const SizedBox(height: Espacio.md),
                    Seccion(
                      titulo: 'Zona de cuidado',
                      colorTitulo: context.sem.peligro,
                      hijos: [
                        Text(
                          _esAdmin
                              ? 'Eliminar la empresa cierra el acceso de todas sus cuentas en las dos apps y desvincula sus kioscos.'
                              : 'Eliminar tu cuenta cierra tu acceso a las apps de la empresa.',
                          style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
                        ),
                        const SizedBox(height: Espacio.md),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.sem.peligro,
                              side: BorderSide(color: context.sem.peligro.withValues(alpha: 0.6)),
                            ),
                            onPressed: _eliminar,
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: Text(_esAdmin ? 'Eliminar empresa' : 'Eliminar mi cuenta'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _App extends StatelessWidget {
  const _App({required this.icono, required this.nombre, required this.detalle, required this.habilitada});
  final IconData icono;
  final String nombre;
  final String detalle;
  final bool habilitada;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icono, color: habilitada ? context.colores.primary : sem.textoSuave),
      title: Text(nombre),
      subtitle: Text(habilitada ? detalle : 'No habilitada para tu empresa'),
      trailing: Pildora(
        texto: habilitada ? 'Activa' : 'Inactiva',
        color: habilitada ? sem.entrada : sem.textoSuave,
        icono: habilitada ? Icons.check_rounded : Icons.remove_rounded,
      ),
    );
  }
}

class _FormEmpresa extends StatefulWidget {
  const _FormEmpresa({required this.api, required this.empresa});
  final Api api;
  final EmpresaInfo empresa;

  @override
  State<_FormEmpresa> createState() => _FormEmpresaState();
}

class _FormEmpresaState extends State<_FormEmpresa> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.empresa.nombre);
  late final _nit = TextEditingController(text: widget.empresa.nit ?? '');
  late final _telefono = TextEditingController(text: widget.empresa.telefono ?? '');
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _nit.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final e = await widget.api.editarEmpresa(nombre: _nombre.text.trim(), nit: _nit.text.trim(), telefono: _telefono.text.trim());
      if (mounted) Navigator.of(context).pop(e);
    } on ApiError catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Datos de la empresa', style: context.textos.headlineSmall),
            const SizedBox(height: Espacio.xxs),
            Text(
              'Se ven en las dos apps, en los reportes y en el ticket de venta.',
              style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
            ),
            const SizedBox(height: Espacio.lg),
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.storefront_outlined)),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Escribe el nombre de la empresa' : null,
            ),
            const SizedBox(height: Espacio.md),
            TextFormField(
              controller: _nit,
              decoration: const InputDecoration(labelText: 'NIT o documento (opcional)', prefixIcon: Icon(Icons.numbers_rounded)),
            ),
            const SizedBox(height: Espacio.md),
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.call_outlined)),
            ),
            if (_error != null) ...[const SizedBox(height: Espacio.md), MensajeError(_error!)],
            const SizedBox(height: Espacio.lg),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmación fuerte: contraseña siempre y, para la empresa, su nombre
/// escrito tal cual (borrar no puede ser un toque accidental).
class _FormEliminar extends StatefulWidget {
  const _FormEliminar({required this.api, required this.empresa, required this.esAdmin});
  final Api api;
  final EmpresaInfo empresa;
  final bool esAdmin;

  @override
  State<_FormEliminar> createState() => _FormEliminarState();
}

class _FormEliminarState extends State<_FormEliminar> {
  final _form = GlobalKey<FormState>();
  final _confirmacion = TextEditingController();
  final _clave = TextEditingController();
  bool _enviando = false;
  bool _ocultar = true;
  String? _error;

  @override
  void dispose() {
    _confirmacion.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _eliminar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await widget.api.eliminarCuenta(
        password: _clave.text,
        confirmacion: widget.esAdmin ? _confirmacion.text.trim() : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Padding(
      padding: EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.warning_amber_rounded, color: sem.peligro, size: 36),
            const SizedBox(height: Espacio.sm),
            Text(widget.esAdmin ? 'Eliminar ${widget.empresa.nombre}' : 'Eliminar mi cuenta', style: context.textos.headlineSmall),
            const SizedBox(height: Espacio.xs),
            Text(
              widget.esAdmin
                  ? 'Nadie de la empresa podrá volver a entrar a Presente ni a Ventario, y sus kioscos quedarán '
                      'desvinculados. Los registros se conservan el tiempo que exige la ley y luego se eliminan.'
                  : 'Ya no podrás entrar a las apps de tu empresa con este correo.',
              style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
            ),
            const SizedBox(height: Espacio.lg),
            if (widget.esAdmin) ...[
              TextFormField(
                controller: _confirmacion,
                decoration: InputDecoration(
                  labelText: 'Escribe «${widget.empresa.nombre}» para confirmar',
                  prefixIcon: const Icon(Icons.keyboard_outlined),
                ),
                validator: (v) => (v ?? '').trim().toLowerCase() == widget.empresa.nombre.trim().toLowerCase()
                    ? null
                    : 'El nombre no coincide',
              ),
              const SizedBox(height: Espacio.md),
            ],
            TextFormField(
              controller: _clave,
              obscureText: _ocultar,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Tu contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                  onPressed: () => setState(() => _ocultar = !_ocultar),
                  icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña' : null,
            ),
            if (_error != null) ...[const SizedBox(height: Espacio.md), MensajeError(_error!)],
            const SizedBox(height: Espacio.lg),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: sem.peligro, foregroundColor: Colors.white),
              onPressed: _enviando ? null : _eliminar,
              child: _enviando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(widget.esAdmin ? 'Eliminar empresa' : 'Eliminar mi cuenta'),
            ),
            TextButton(onPressed: _enviando ? null : () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          ],
        ),
      ),
    );
  }
}
