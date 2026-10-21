import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import '../cuenta/plan_ui.dart';
import '../cuenta/registro_empresa_page.dart' show FortalezaClave;
import 'acceso_admin.dart';
import 'contexto_admin.dart';

/// Equipo: las cuentas de la empresa. Una cuenta es UNA persona para las dos
/// apps de la plataforma, con UN rol que decide a cuál entra: administrador y
/// gerente en las dos; vendedor y auxiliar solo en Ventario; talento humano y
/// operario solo en Presente. Solo el administrador la gestiona.
class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  Api get _api => _ctx.api;
  EquipoEmpresa? _equipo;
  List<Sede> _sedes = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final equipo = await _api.usuarios();
      // Las sedes de Presente (el servidor valida contra ellas). Las que solo
      // usa Ventario se asignan desde Ventario.
      final sedes = await _api.sedes();
      if (mounted) {
        setState(() {
          _equipo = equipo;
          _sedes = sedes;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _abrir([Usuario? u]) async {
    final equipo = _equipo;
    if (equipo == null) return;
    // Una cuenta nueva ocupa un cupo de «personas»: se avisa antes de llenar el formulario.
    if (u == null && !await hayCupo(context, _api, RecursoLimitado.personas)) return;
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FormUsuario(
        api: _api,
        usuario: u,
        sedes: _sedes,
        conInventario: equipo.aplicativos.contains('INVENTARIO'),
      ),
    );
    if (ok == true) _cargar();
  }

  String _sedesDe(Usuario u) {
    final rol = u.rolCuenta;
    if (rol == RolCuenta.admin) return 'Todas las sedes';
    if (rol == RolCuenta.talentoHumano || rol == RolCuenta.operario) return 'Todas las sedes de Presente';
    if (u.sedes.isEmpty) return 'Sin sedes asignadas';
    return u.sedes.map((id) => _sedes.where((s) => s.id == id).firstOrNull?.nombre ?? 'Sede $id').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final equipo = _equipo;
    final sem = context.sem;
    return Scaffold(
      appBar: AppBar(title: const Text('Equipo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: equipo == null ? null : () => _abrir(),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Nueva cuenta'),
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
                            'Cada cuenta entra con su correo a las apps que le da su rol.',
                            style: context.textos.bodyMedium,
                          ),
                          if (equipo.plan != null) ...[
                            const SizedBox(height: Espacio.md),
                            MedidorUso(recurso: RecursoLimitado.personas, uso: equipo.plan!.personas),
                            const SizedBox(height: Espacio.xxs),
                            Text(
                              'Personas en el plan de Presente. Si no alcanza, pausa a quien no la use: '
                              'su cuenta sigue en Ventario.',
                              style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                            ),
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
                                            texto: u.rolCuenta?.etiqueta ?? 'Sin rol',
                                            color: context.colores.primary,
                                          ),
                                          if (u.rolAsistencia != null)
                                            Pildora(
                                              texto: u.pausaAsistencia ? 'Presente · en pausa' : 'Presente',
                                              color: u.pausaAsistencia ? sem.alerta : sem.entrada,
                                              icono: Icons.face_unlock_outlined,
                                            ),
                                          if (u.rolInventario != null)
                                            Pildora(texto: 'Ventario', color: sem.salida, icono: Icons.point_of_sale_outlined),
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

class _FormUsuario extends StatefulWidget {
  const _FormUsuario({required this.api, required this.sedes, required this.conInventario, this.usuario});
  final Api api;
  final Usuario? usuario;
  final List<Sede> sedes;
  final bool conInventario;

  @override
  State<_FormUsuario> createState() => _FormUsuarioState();
}

class _FormUsuarioState extends State<_FormUsuario> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.usuario?.nombre);
  late final _email = TextEditingController(text: widget.usuario?.email);
  late final _documento = TextEditingController(text: widget.usuario?.documento);
  final _clave = TextEditingController();
  late RolCuenta? _rol = widget.usuario?.rolCuenta;
  late final Set<int> _sedes = {...?widget.usuario?.sedes};
  late bool _activo = widget.usuario?.activo ?? true;
  late bool _pausa = widget.usuario?.pausaAsistencia ?? false;
  bool _guardando = false;
  bool _ocultar = true;
  String? _error;
  String? _errorRol;

  bool get _nuevo => widget.usuario == null;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _documento.dispose();
    _clave.dispose();
    super.dispose();
  }

  void _elegirRol(RolCuenta r) => setState(() {
        _rol = r;
        if (!r.conSedes) _sedes.clear();
        if (r.unaSede && _sedes.length > 1) _sedes.removeAll(_sedes.skip(1).toList());
        if (r.asistencia == null || r == RolCuenta.admin) _pausa = false;
        _errorRol = null;
      });

  void _alternarSede(int id) => setState(() {
        if (_rol?.unaSede ?? false) {
          _sedes
            ..clear()
            ..add(id);
        } else if (!_sedes.remove(id)) {
          _sedes.add(id);
        }
        _errorRol = null;
      });

  /// Las mismas reglas que exigen los dos servidores.
  String? _validarRol() {
    final r = _rol;
    if (r == null) return 'Elige un rol para la cuenta';
    if (r.unaSede && _sedes.length != 1) return 'Vendedores y auxiliares pertenecen a exactamente una sede';
    if (r == RolCuenta.gerente && _sedes.isEmpty) return 'Un gerente necesita al menos una sede';
    return null;
  }

  Future<void> _guardar() async {
    final errorRol = _validarRol();
    final valido = _form.currentState!.validate();
    setState(() => _errorRol = errorRol);
    if (!valido || errorRol != null) return;
    final rol = _rol!;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final guardado = await widget.api.guardarUsuario(
        id: widget.usuario?.id,
        nombre: _nombre.text.trim(),
        email: _nuevo ? _email.text.trim().toLowerCase() : null,
        password: _clave.text,
        rolAsistencia: rol.asistencia,
        rolInventario: rol.inventario,
        sedes: rol.conSedes ? _sedes.toList() : const [],
        documento: _documento.text.trim().isEmpty ? null : _documento.text.trim(),
        activo: _nuevo ? null : _activo,
      );
      if (!_nuevo && rol.asistencia != null && _pausa != guardado.pausaAsistencia) {
        await widget.api.pausarUsuario(guardado.id, pausada: _pausa);
      }
      if (mounted) {
        avisar(context, _nuevo ? 'Cuenta creada: ya puede entrar con su correo' : 'Cambios guardados');
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

  Widget _titulo(String texto, IconData icono) => Padding(
        padding: const EdgeInsets.only(top: Espacio.lg, bottom: Espacio.xs),
        child: Row(
          children: [
            Icon(icono, size: 18, color: context.colores.primary),
            const SizedBox(width: Espacio.xs),
            Etiqueta(texto),
          ],
        ),
      );

  String get _ayudaSedes => (_rol?.unaSede ?? false) ? 'Elige la sede donde trabaja.' : 'Elige una o varias sedes a su cargo.';

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final rol = _rol;
    final grupos = <(String, IconData, List<RolCuenta>)>[
      ('En las dos apps', Icons.apps_rounded, const [RolCuenta.admin, RolCuenta.gerente]),
      if (widget.conInventario)
        ('Solo Ventario', Icons.point_of_sale_outlined, const [RolCuenta.vendedor, RolCuenta.auxiliar]),
      ('Solo Presente', Icons.face_unlock_outlined, const [RolCuenta.talentoHumano, RolCuenta.operario]),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_nuevo ? 'Nueva cuenta' : 'Editar cuenta', style: context.textos.headlineSmall),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre completo', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Escribe el nombre completo' : null,
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _email,
                enabled: _nuevo,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  helperText: 'Con él entra a las apps. No se puede cambiar después.',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (v) => !_nuevo || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                    ? null
                    : 'Escribe un correo válido',
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _documento,
                decoration: const InputDecoration(
                  labelText: 'Documento (opcional)',
                  helperText: 'Si ya marca asistencia, el mismo documento une su ficha a esta cuenta.',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.credit_card_outlined),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  return t.isEmpty || RegExp(r'^[A-Za-z0-9.-]{3,20}$').hasMatch(t) ? null : 'De 3 a 20 letras o números';
                },
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _clave,
                obscureText: _ocultar,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _nuevo ? 'Contraseña' : 'Nueva contraseña (opcional)',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                    icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: (v) {
                  final p = v ?? '';
                  if (_nuevo || p.isNotEmpty) return p.length < 8 ? 'Usa al menos 8 caracteres' : null;
                  return null;
                },
              ),
              const SizedBox(height: Espacio.xs),
              FortalezaClave(clave: _clave.text),

              for (final (titulo, icono, roles) in grupos) ...[
                _titulo(titulo, icono),
                _Opciones<RolCuenta>(
                  valor: rol,
                  opciones: [for (final r in roles) (r, r.etiqueta, r.descripcion)],
                  alElegir: _elegirRol,
                ),
              ],

              if (rol != null && rol.conSedes) ...[
                _titulo('Sedes', Icons.place_outlined),
                Text(_ayudaSedes, style: context.textos.bodySmall?.copyWith(color: sem.textoSuave)),
                const SizedBox(height: Espacio.xs),
                Wrap(
                  spacing: Espacio.xs,
                  runSpacing: Espacio.xs,
                  children: [
                    for (final s in widget.sedes)
                      FilterChip(
                        label: Text(s.nombre),
                        selected: _sedes.contains(s.id),
                        onSelected: (_) => _alternarSede(s.id),
                      ),
                  ],
                ),
              ] else if (rol != null) ...[
                const SizedBox(height: Espacio.sm),
                Text(
                  rol == RolCuenta.admin
                      ? 'El administrador ve todas las sedes.'
                      : 'Trabaja en todas las sedes de Presente: no se le asignan sedes.',
                  style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                ),
              ],
              if (_errorRol != null) ...[
                const SizedBox(height: Espacio.xs),
                Text(_errorRol!, style: context.textos.bodySmall?.copyWith(color: sem.peligro)),
              ],

              if (!_nuevo) ...[
                const SizedBox(height: Espacio.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                  title: const Text('Cuenta activa'),
                  subtitle: const Text('Inactiva: no entra a ninguna app y libera su cupo del plan.'),
                ),
                if (rol?.asistencia != null && rol != RolCuenta.admin)
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
              const SizedBox(height: Espacio.lg),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_nuevo ? 'Crear cuenta' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opciones excluyentes con título y explicación (más claras que un menú para
/// decidir qué puede hacer alguien).
class _Opciones<T> extends StatelessWidget {
  const _Opciones({required this.valor, required this.opciones, required this.alElegir});
  final T? valor;
  final List<(T, String, String)> opciones;
  final ValueChanged<T> alElegir;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Column(
      children: [
        for (final (v, titulo, detalle) in opciones)
          Padding(
            padding: const EdgeInsets.only(bottom: Espacio.xxs),
            child: Material(
              color: v == valor ? c.primary.withValues(alpha: 0.08) : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Redondeo.md),
                side: BorderSide(color: v == valor ? c.primary : c.outlineVariant, width: v == valor ? 1.5 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(Redondeo.md),
                onTap: () => alElegir(v),
                child: Semantics(
                  selected: v == valor,
                  inMutuallyExclusiveGroup: true,
                  button: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Espacio.sm, vertical: Espacio.xs),
                    child: Row(
                      children: [
                        Icon(v == valor ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: v == valor ? c.primary : context.sem.textoSuave, size: 22),
                        const SizedBox(width: Espacio.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(titulo, style: context.textos.titleSmall),
                              Text(detalle, style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
