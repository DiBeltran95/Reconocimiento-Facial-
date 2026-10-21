import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import '../cuenta/plan_ui.dart';
import 'acceso_admin.dart' show MensajeError;
import 'contexto_admin.dart';

/// Sedes de la empresa (solo el administrador). Son las mismas de Inventario:
/// crear una aquí la crea allá. El cupo del plan se revisa antes de abrir el
/// formulario y lo exige el servidor.
class SedesPage extends StatefulWidget {
  const SedesPage({super.key});

  @override
  State<SedesPage> createState() => _SedesPageState();
}

class _SedesPageState extends State<SedesPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  Api get _api => _ctx.api;
  List<Sede>? _sedes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final s = await _api.sedes(todas: true);
      if (mounted) {
        setState(() {
          _sedes = s;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _abrir([Sede? sede]) async {
    if (sede == null && !await hayCupo(context, _api, RecursoLimitado.sedes)) return;
    if (!mounted) return;
    final guardada = await showModalBottomSheet<Sede>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FormSede(api: _api, sede: sede),
    );
    if (guardada == null || !mounted) return;
    avisar(context, sede == null ? 'Sede ${guardada.nombre} creada' : 'Cambios guardados');
    await _cargar();
    await _ctx.cargarSedes();
  }

  @override
  Widget build(BuildContext context) {
    final sedes = _sedes;
    return Scaffold(
      appBar: AppBar(title: const Text('Sedes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrir(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Nueva sede'),
      ),
      body: FondoTecnico(
        intensidad: 0.6,
        child: sedes == null
            ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudieron cargar', mensaje: _error, accion: _cargar))
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.sm, Espacio.md, 96),
                  itemCount: sedes.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: Espacio.xs),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Espacio.xs),
                        child: Text(
                          'Las sedes se comparten con Ventario: lo que cambies aquí se ve en las dos apps.',
                          style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
                        ),
                      );
                    }
                    final s = sedes[i - 1];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: Espacio.md, vertical: Espacio.xs),
                        leading: CircleAvatar(
                          backgroundColor: context.colores.primary.withValues(alpha: s.activo ? 0.14 : 0.05),
                          child: Text(
                            s.codigo,
                            style: context.textos.labelSmall?.copyWith(
                              color: s.activo ? context.colores.primary : context.sem.textoSuave,
                            ),
                          ),
                        ),
                        title: Text(s.nombre),
                        subtitle: Text(s.direccion ?? 'Sin dirección'),
                        trailing: Wrap(
                          spacing: Espacio.xs,
                          children: [
                            if (s.esPrincipal) Pildora(texto: 'Principal', color: context.colores.primary),
                            if (!s.activo) Pildora(texto: 'Inactiva', color: context.sem.textoSuave),
                          ],
                        ),
                        onTap: () => _abrir(s),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _FormSede extends StatefulWidget {
  const _FormSede({required this.api, this.sede});
  final Api api;
  final Sede? sede;

  @override
  State<_FormSede> createState() => _FormSedeState();
}

class _FormSedeState extends State<_FormSede> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.sede?.nombre ?? '');
  late final _codigo = TextEditingController(text: widget.sede?.codigo ?? '');
  late final _direccion = TextEditingController(text: widget.sede?.direccion ?? '');
  late final _telefono = TextEditingController(text: widget.sede?.telefono ?? '');
  late bool _activo = widget.sede?.activo ?? true;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_nombre, _codigo, _direccion, _telefono]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final s = await widget.api.guardarSede(
        id: widget.sede?.id,
        nombre: _nombre.text.trim(),
        codigo: _codigo.text.trim().toUpperCase(),
        direccion: _direccion.text.trim(),
        telefono: _telefono.text.trim(),
        activo: widget.sede == null ? null : _activo,
      );
      if (mounted) Navigator.of(context).pop(s);
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
    final principal = widget.sede?.esPrincipal ?? false;
    return Padding(
      padding: EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.sede == null ? 'Nueva sede' : 'Editar sede', style: context.textos.headlineSmall),
              const SizedBox(height: Espacio.lg),
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.place_outlined)),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Ponle un nombre a la sede' : null,
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _codigo,
                textCapitalization: TextCapitalization.characters,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: 'Código corto',
                  helperText: 'Para listas y tickets. Vacío: se sugiere del nombre (Sede Norte → NOR)',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty && widget.sede == null) return null;
                  return RegExp(r'^[A-Za-z0-9]{2,10}$').hasMatch(t) ? null : 'De 2 a 10 letras o números';
                },
              ),
              const SizedBox(height: Espacio.xs),
              TextFormField(
                controller: _direccion,
                decoration: const InputDecoration(labelText: 'Dirección (opcional)', prefixIcon: Icon(Icons.map_outlined)),
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _telefono,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.call_outlined)),
              ),
              if (widget.sede != null) ...[
                const SizedBox(height: Espacio.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _activo,
                  onChanged: principal ? null : (v) => setState(() => _activo = v),
                  title: const Text('Sede activa'),
                  subtitle: Text(principal
                      ? 'La sede principal no se puede desactivar'
                      : 'Inactiva: no aparece para vender ni para marcar, y libera su cupo del plan'),
                ),
              ],
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
      ),
    );
  }
}
