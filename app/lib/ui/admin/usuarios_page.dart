import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import '../cuenta/plan_ui.dart';
import 'acceso_admin.dart';
import 'contexto_admin.dart';

/// Cuentas de acceso a Presente. El empleado es uno solo para las dos apps (se
/// registra en «Personal» o en Ventario); aquí se le da acceso a Presente con
/// un rol de Presente: gerente, talento humano u operario. Su acceso a Ventario
/// lo decide Ventario. El operario es una cuenta técnica (los teléfonos de
/// marcación), sin empleado. Solo el administrador gestiona las cuentas.
class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  Api get _api => _ctx.api;
  EquipoEmpresa? _equipo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final equipo = await _api.usuarios();
      if (mounted) {
        setState(() {
          _equipo = equipo;
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
      showDragHandle: true,
      builder: (_) => u == null
          ? _FormNuevaCuenta(api: _api, sedes: _ctx.sedes)
          : _FormCuenta(api: _api, usuario: u, sedes: _ctx.sedes),
    );
    if (ok == true) _cargar();
  }

  String _sedesDe(Usuario u) {
    if (u.rolAsistencia != RolAsistencia.gerente) return 'Todas las sedes';
    if (u.sedes.isEmpty) return 'Sin sedes asignadas';
    return u.sedes.map((id) => _ctx.sedes.where((s) => s.id == id).firstOrNull?.nombre ?? 'Sede $id').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final equipo = _equipo;
    final sem = context.sem;
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas de Presente')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: equipo == null ? null : () => _abrir(),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Dar acceso'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: equipo == null
            ? (_error != null
                ? ListView(children: [EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudo cargar', mensaje: _error, accion: _cargar)])
                : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, 96),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Espacio.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Quién entra a Presente y con qué rol. Los empleados se registran en «Personal» '
                            '(o en Ventario); aquí solo se les da acceso.',
                            style: context.textos.bodyMedium,
                          ),
                          if (equipo.plan != null) ...[
                            const SizedBox(height: Espacio.md),
                            MedidorUso(recurso: RecursoLimitado.personas, uso: equipo.plan!.personas),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Espacio.md),
                  for (final u in equipo.usuarios)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espacio.xs),
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Redondeo.lg),
                          onTap: () => _abrir(u),
                          child: Padding(
                            padding: const EdgeInsets.all(Espacio.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AvatarEmpleado(nombre: u.nombre, tam: 44),
                                const SizedBox(width: Espacio.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(u.nombre, style: context.textos.titleMedium),
                                      Text(u.email, style: context.textos.bodySmall?.copyWith(color: sem.textoSuave)),
                                      const SizedBox(height: Espacio.xs),
                                      Wrap(
                                        spacing: Espacio.xs,
                                        runSpacing: Espacio.xxs,
                                        children: [
                                          if (!u.activo) Pildora(texto: 'Inactiva', color: sem.peligro),
                                          Pildora(
                                            texto: u.rolAsistencia?.etiqueta ?? 'Sin rol',
                                            color: context.colores.primary,
                                          ),
                                          if (u.pausaAsistencia) Pildora(texto: 'En pausa', color: sem.alerta),
                                          if (u.empleadoId == null && u.rolAsistencia == RolAsistencia.operario)
                                            Pildora(texto: 'Cuenta técnica', color: sem.textoSuave),
                                        ],
                                      ),
                                      const SizedBox(height: Espacio.xxs),
                                      Text(_sedesDe(u), style: context.textos.bodySmall?.copyWith(color: sem.textoSuave)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
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

/// Roles que se dan desde Presente (el administrador es el dueño de la empresa).
const _rolesAsignables = [RolAsistencia.gerente, RolAsistencia.talentoHumano, RolAsistencia.operario];

// ─── Nueva cuenta ───────────────────────────────────────────────────────────

class _FormNuevaCuenta extends StatefulWidget {
  const _FormNuevaCuenta({required this.api, required this.sedes});
  final Api api;
  final List<Sede> sedes;

  @override
  State<_FormNuevaCuenta> createState() => _FormNuevaCuentaState();
}

class _FormNuevaCuentaState extends State<_FormNuevaCuenta> {
  final _form = GlobalKey<FormState>();
  final _buscar = TextEditingController();
  final _email = TextEditingController();
  final _nombre = TextEditingController();

  /// true = cuenta técnica del operario (sin empleado).
  bool _tecnica = false;
  CandidatoCuenta? _empleado;
  RolAsistencia _rol = RolAsistencia.gerente;
  final Set<int> _sedes = {};
  List<CandidatoCuenta>? _candidatos;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCandidatos();
  }

  @override
  void dispose() {
    _buscar.dispose();
    _email.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _cargarCandidatos() async {
    try {
      final l = await widget.api.candidatosCuenta(q: _buscar.text.trim());
      if (mounted) setState(() => _candidatos = l);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  void _elegir(CandidatoCuenta c) => setState(() {
        _empleado = c;
        _email.text = c.email ?? '';
        _sedes
          ..clear()
          ..add(c.sedeId);
        _error = null;
      });

  bool get _pideSedes => !_tecnica && _rol == RolAsistencia.gerente && !(_empleado?.conCuenta ?? false);
  /// El correo es el del EMPLEADO: solo se pide si su ficha aún no tiene
  /// (o para la cuenta técnica del operario). Si ya tiene, se muestra fijo.
  bool get _pideCorreo =>
      _tecnica || (!(_empleado?.conCuenta ?? true) && (_empleado?.email ?? '').isEmpty);
  String? get _correoFicha =>
      !_tecnica && !(_empleado?.conCuenta ?? true) && (_empleado?.email ?? '').isNotEmpty ? _empleado!.email : null;

  Future<void> _guardar() async {
    // Un segundo toque mientras guarda no envía otra alta.
    if (_guardando) return;
    if (!_tecnica && _empleado == null) return setState(() => _error = 'Elige el empleado al que le das acceso');
    if (!_form.currentState!.validate()) return;
    if (_pideSedes && _sedes.isEmpty) return setState(() => _error = 'Un gerente necesita al menos una sede');
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final r = await widget.api.crearCuenta(
        rol: _tecnica ? RolAsistencia.operario : _rol,
        empleadoId: _tecnica ? null : _empleado!.id,
        sedes: _pideSedes ? _sedes.toList() : const [],
        email: _pideCorreo ? _email.text.trim().toLowerCase() : null,
        nombre: _tecnica ? _nombre.text.trim() : null,
      );
      if (!mounted) return;
      avisar(
        context,
        r.cuentaExistente
            ? '${r.usuario.nombre} ya entra a Presente con su cuenta de Ventario'
            : r.avisoEnviado
                ? 'Listo: le enviamos un correo para que cree su contraseña'
                : 'Cuenta creada: que entre con «¿Olvidaste tu contraseña?» para crear la suya',
      );
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (await manejarLimite(context, widget.api, e)) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final empleado = _empleado;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Dar acceso a Presente', style: context.textos.headlineSmall),
              const SizedBox(height: Espacio.md),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.badge_outlined), label: Text('Un empleado')),
                  ButtonSegment(value: true, icon: Icon(Icons.phone_android_rounded), label: Text('Operario')),
                ],
                selected: {_tecnica},
                onSelectionChanged: (v) => setState(() {
                  _tecnica = v.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: Espacio.md),
              if (_tecnica) ...[
                Text(
                  'Cuenta técnica para dejar los teléfonos de marcación listos: una para todas las sedes. '
                  'No ocupa cupo de personas.',
                  style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                ),
                const SizedBox(height: Espacio.md),
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Operario · Sedes', prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) => (v ?? '').trim().length < 3 ? 'Ponle un nombre a la cuenta' : null,
                ),
                const SizedBox(height: Espacio.md),
              ] else if (empleado == null) ...[
                TextField(
                  controller: _buscar,
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre o documento',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (_) => _cargarCandidatos(),
                ),
                const SizedBox(height: Espacio.sm),
                if (_candidatos == null)
                  const Padding(padding: EdgeInsets.all(Espacio.lg), child: Center(child: CircularProgressIndicator()))
                else if (_candidatos!.isEmpty)
                  Text(
                    'No hay empleados sin acceso. Regístralo primero en «Personal» (con su correo) y vuelve aquí.',
                    style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
                  )
                else
                  for (final c in _candidatos!.take(30))
                    Card(
                      margin: const EdgeInsets.only(bottom: Espacio.xs),
                      child: ListTile(
                        leading: AvatarEmpleado(nombre: c.nombre, tam: 40),
                        title: Text(c.nombre),
                        subtitle: Text([c.documento, c.sede, if (c.conCuenta) 'ya entra a Ventario'].join(' · ')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _elegir(c),
                      ),
                    ),
              ] else ...[
                Card(
                  child: ListTile(
                    leading: AvatarEmpleado(nombre: empleado.nombre, tam: 40),
                    title: Text(empleado.nombre),
                    subtitle: Text([empleado.documento, empleado.sede].join(' · ')),
                    trailing: TextButton(onPressed: () => setState(() => _empleado = null), child: const Text('Cambiar')),
                  ),
                ),
                if (empleado.conCuenta)
                  Padding(
                    padding: const EdgeInsets.only(top: Espacio.xs),
                    child: Text(
                      'Ya entra a Ventario: usará el mismo correo y contraseña.',
                      style: context.textos.bodySmall?.copyWith(color: sem.entrada),
                    ),
                  ),
                const SizedBox(height: Espacio.md),
                Etiqueta('Rol en Presente'),
                const SizedBox(height: Espacio.xs),
                RadioGroup<RolAsistencia>(
                  groupValue: _rol,
                  onChanged: (r) => setState(() => _rol = r ?? _rol),
                  child: Column(
                    children: [
                      for (final r in _rolesAsignables)
                        RadioListTile<RolAsistencia>(
                          value: r,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(r.etiqueta),
                          subtitle: Text(r.descripcion),
                        ),
                    ],
                  ),
                ),
                if (_pideSedes) ...[
                  const SizedBox(height: Espacio.xs),
                  Text('Sedes que gestiona', style: context.textos.titleSmall),
                  const SizedBox(height: Espacio.xs),
                  Wrap(
                    spacing: Espacio.xs,
                    runSpacing: Espacio.xs,
                    children: [
                      for (final s in widget.sedes)
                        FilterChip(
                          label: Text(s.nombre),
                          selected: _sedes.contains(s.id),
                          onSelected: (v) => setState(() => v ? _sedes.add(s.id) : _sedes.remove(s.id)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Espacio.md),
              ],
              if (_pideCorreo && (_tecnica || empleado != null))
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    helperText: 'Con él entra. Le llegará un aviso para crear su contraseña.',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (v) =>
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Escribe un correo válido',
                ),
              if (_correoFicha != null)
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Entrará con el correo de su ficha',
                    helperText: 'Para cambiarlo, edítalo en Personal. Le llegará un aviso para crear su contraseña.',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                    suffixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                  ),
                  child: Text(_correoFicha!, style: context.textos.bodyLarge),
                ),
              if (_error != null) ...[
                const SizedBox(height: Espacio.md),
                MensajeError(_error!),
              ],
              if (_tecnica || empleado != null) ...[
                const SizedBox(height: Espacio.lg),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Dar acceso'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cuenta existente ───────────────────────────────────────────────────────

class _FormCuenta extends StatefulWidget {
  const _FormCuenta({required this.api, required this.usuario, required this.sedes});
  final Api api;
  final Usuario usuario;
  final List<Sede> sedes;

  @override
  State<_FormCuenta> createState() => _FormCuentaState();
}

class _FormCuentaState extends State<_FormCuenta> {
  late RolAsistencia? _rol = widget.usuario.rolAsistencia;
  late final Set<int> _sedes = {...widget.usuario.sedes};
  late bool _activo = widget.usuario.activo;
  late bool _pausa = widget.usuario.pausaAsistencia;
  bool _guardando = false;
  String? _error;

  Usuario get u => widget.usuario;
  bool get _esAdmin => u.rolAsistencia == RolAsistencia.admin;

  /// Si también entra a Ventario, sus sedes se gestionan allá.
  bool get _sedesAqui => _rol == RolAsistencia.gerente && !u.tieneVentario;

  Future<void> _guardar() async {
    if (_guardando) return;
    if (_sedesAqui && _sedes.isEmpty) return setState(() => _error = 'Un gerente necesita al menos una sede');
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.api.actualizarCuenta(
        u.id,
        rol: _esAdmin || _rol == u.rolAsistencia ? null : _rol,
        sedes: _sedesAqui ? _sedes.toList() : (_rol != RolAsistencia.gerente && !u.tieneVentario ? const [] : null),
        activo: _activo == u.activo ? null : _activo,
      );
      if (_pausa != u.pausaAsistencia) await widget.api.pausarUsuario(u.id, pausada: _pausa);
      if (mounted) {
        avisar(context, 'Cambios guardados');
        Navigator.pop(context, true);
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      if (await manejarLimite(context, widget.api, e)) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _quitar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Quitar el acceso a Presente de ${u.nombre}?'),
        content: Text(
          u.tieneVentario
              ? 'Ya no podrá entrar a Presente. Su acceso a Ventario sigue igual.'
              : 'Ya no podrá entrar a Presente. Si es un empleado, sigue registrado en «Personal» y puede marcar asistencia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.sem.peligro, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Quitar acceso'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      await widget.api.quitarAcceso(u.id);
      if (mounted) {
        avisar(context, 'Acceso a Presente retirado');
        Navigator.pop(context, true);
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(u.nombre, style: context.textos.headlineSmall),
            Text(u.email, style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave)),
            if (u.tieneVentario)
              Padding(
                padding: const EdgeInsets.only(top: Espacio.xxs),
                child: Text('También entra a Ventario (ese acceso se gestiona allá).',
                    style: context.textos.bodySmall?.copyWith(color: sem.textoSuave)),
              ),
            const SizedBox(height: Espacio.md),
            if (_esAdmin)
              Text(
                'Administrador de la empresa en las dos apps.',
                style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
              )
            else ...[
              Etiqueta('Rol en Presente'),
              const SizedBox(height: Espacio.xs),
              RadioGroup<RolAsistencia>(
                groupValue: _rol,
                onChanged: (r) => setState(() => _rol = r ?? _rol),
                child: Column(
                  children: [
                    for (final r in _rolesAsignables)
                      RadioListTile<RolAsistencia>(
                        value: r,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(r.etiqueta),
                        subtitle: Text(r.descripcion),
                      ),
                  ],
                ),
              ),
              if (_sedesAqui) ...[
                Text('Sedes que gestiona', style: context.textos.titleSmall),
                const SizedBox(height: Espacio.xs),
                Wrap(
                  spacing: Espacio.xs,
                  runSpacing: Espacio.xs,
                  children: [
                    for (final s in widget.sedes)
                      FilterChip(
                        label: Text(s.nombre),
                        selected: _sedes.contains(s.id),
                        onSelected: (v) => setState(() => v ? _sedes.add(s.id) : _sedes.remove(s.id)),
                      ),
                  ],
                ),
              ] else if (_rol == RolAsistencia.gerente && u.tieneVentario)
                Text('Sus sedes se asignan en Ventario.', style: context.textos.bodySmall?.copyWith(color: sem.textoSuave)),
              const SizedBox(height: Espacio.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
                title: const Text('Cuenta activa'),
                subtitle: const Text('Inactiva: no entra a ninguna de las dos apps.'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _pausa,
                onChanged: (v) => setState(() => _pausa = v),
                title: const Text('En pausa en Presente'),
                subtitle: const Text('No entra a Presente ni ocupa su cupo; en Ventario sigue igual.'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Espacio.md),
              MensajeError(_error!),
            ],
            if (!_esAdmin) ...[
              const SizedBox(height: Espacio.lg),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Guardar'),
              ),
              const SizedBox(height: Espacio.xs),
              TextButton.icon(
                onPressed: _guardando ? null : _quitar,
                icon: Icon(Icons.person_remove_outlined, color: sem.peligro),
                label: Text('Quitar acceso a Presente', style: TextStyle(color: sem.peligro)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
