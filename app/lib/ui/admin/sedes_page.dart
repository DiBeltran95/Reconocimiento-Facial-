import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import '../cuenta/plan_ui.dart';
import 'acceso_admin.dart' show MensajeError;
import 'contexto_admin.dart';

/// Sedes de la empresa (solo el administrador). Son las mismas de Ventario:
/// crear una aquí la crea allá. Cada app trabaja solo en las sedes que se
/// eligen para ella, hasta el límite de SU plan, y la elección no se puede
/// deshacer. Crear una sede aquí la elige para Presente.
class SedesPage extends StatefulWidget {
  const SedesPage({super.key});

  @override
  State<SedesPage> createState() => _SedesPageState();
}

class _SedesPageState extends State<SedesPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  Api get _api => _ctx.api;
  List<Sede>? _sedes;
  PlanEmpresa? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final s = await _api.sedes(todas: true);
      PlanEmpresa? plan;
      try {
        plan = await _api.plan();
      } on ApiError {
        plan = null;
      }
      if (mounted) {
        setState(() {
          _sedes = s;
          _plan = plan;
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

  Future<void> _elegir(Sede sede) async {
    final elegida = await confirmarSedeParaPresente(context, _api, sede, plan: _plan);
    if (elegida == null || !mounted) return;
    avisar(context, '${sede.nombre} ya está en Presente');
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Las sedes se comparten con Ventario, pero cada app usa solo las que eliges para ella, '
                              'hasta el límite de su plan.',
                              style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
                            ),
                            if (_plan != null) ...[
                              const SizedBox(height: Espacio.md),
                              MedidorUso(recurso: RecursoLimitado.sedes, uso: _plan!.sedes),
                            ],
                          ],
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
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: Espacio.xxs),
                          child: Wrap(
                            spacing: Espacio.xs,
                            runSpacing: Espacio.xxs,
                            children: [
                              if (s.esPrincipal) Pildora(texto: 'Principal', color: context.colores.primary),
                              if (!s.activo) Pildora(texto: 'Inactiva', color: context.sem.textoSuave),
                              if (s.elegida)
                                Pildora(texto: 'En Presente', color: context.sem.entrada, icono: Icons.face_unlock_outlined),
                              if (s.elegidaVentario ?? false)
                                Pildora(texto: 'En Ventario', color: context.sem.salida, icono: Icons.point_of_sale_outlined),
                            ],
                          ),
                        ),
                        trailing: !s.elegida && s.activo
                            ? TextButton(onPressed: () => _elegir(s), child: const Text('Usar en Presente'))
                            : null,
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

/// Confirma (es irrevocable) y elige [sede] para Presente. Devuelve la sede
/// elegida o null si se canceló o el plan no alcanza.
Future<Sede?> confirmarSedeParaPresente(BuildContext context, Api api, Sede sede, {PlanEmpresa? plan}) async {
  final sedes = plan?.sedes;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.place_outlined, color: c.colores.primary),
      title: Text('¿Usar ${sede.nombre} en Presente?'),
      content: Text(
        [
          'Presente empezará a trabajar en esta sede: personal, teléfonos de marcación y reportes.',
          'Esta elección no se puede deshacer.',
          if (sedes != null && sedes.maximo != null)
            'Tu plan de Presente permite ${sedes.maximo} sede${sedes.maximo == 1 ? '' : 's'} y ya usas ${sedes.usados}.',
        ].join('\n\n'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, usarla')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  try {
    return await api.elegirSede(sede.id);
  } on ApiError catch (e) {
    if (!context.mounted) return null;
    if (!await manejarLimite(context, api, e) && context.mounted) avisar(context, e.mensaje, error: true);
    return null;
  }
}

/// Sin ninguna sede para Presente: el administrador elige la primera.
Future<Sede?> pedirPrimeraSede(BuildContext context, Api api) async {
  final activas = (await api.sedes(todas: true)).where((s) => s.activo).toList();
  if (activas.isEmpty || !context.mounted) return null;
  final sede = await showModalBottomSheet<Sede>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
      children: [
        Text('¿En qué sede usarás Presente?', style: c.textos.headlineSmall),
        const SizedBox(height: Espacio.xxs),
        Text(
          'Tu empresa aún no tiene sedes en Presente. Elige una para empezar.',
          style: c.textos.bodyMedium?.copyWith(color: c.sem.textoSuave),
        ),
        const SizedBox(height: Espacio.md),
        for (final s in activas)
          Card(
            child: ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(s.nombre),
              subtitle: s.direccion == null ? null : Text(s.direccion!),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(c, s),
            ),
          ),
      ],
    ),
  );
  if (sede == null || !context.mounted) return null;
  return confirmarSedeParaPresente(context, api, sede);
}
