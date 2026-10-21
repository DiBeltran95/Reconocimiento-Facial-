import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../comun/widgets.dart';
import '../cuenta/plan_ui.dart';
import '../horarios/plan_empleado.dart';
import 'acceso_admin.dart';
import 'contexto_admin.dart';
import 'enrolar_page.dart';

/// Alta / edición de un empleado y acceso al registro de su rostro.
class EmpleadoFormPage extends StatefulWidget {
  const EmpleadoFormPage({super.key, this.empleado});
  final Empleado? empleado;

  @override
  State<EmpleadoFormPage> createState() => _EmpleadoFormPageState();
}

class _EmpleadoFormPageState extends State<EmpleadoFormPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  final _formulario = GlobalKey<FormState>();
  late final _documento = TextEditingController(text: widget.empleado?.documento);
  late final _nombre = TextEditingController(text: widget.empleado?.nombre);
  late final _cargo = TextEditingController(text: widget.empleado?.cargo);
  late int _sedeId = widget.empleado?.sedeId ?? _ctx.sede.id;
  late Empleado? _empleado = widget.empleado;

  bool _guardando = false;
  bool _cambio = false;
  late bool _consentimiento = widget.empleado?.tieneConsentimiento ?? false;
  String? _error;
  String? _campoError;

  bool get _esNuevo => _empleado == null;

  @override
  void dispose() {
    _documento.dispose();
    _nombre.dispose();
    _cargo.dispose();
    super.dispose();
  }

  Future<bool> _guardar() async {
    if (!_formulario.currentState!.validate()) return false;
    setState(() {
      _guardando = true;
      _error = null;
      _campoError = null;
    });
    try {
      final cargo = _cargo.text.trim().isEmpty ? null : _cargo.text.trim();
      if (_esNuevo) {
        final r = await _ctx.api.crearEmpleado(
          sedeId: _sedeId,
          documento: _documento.text,
          nombre: _nombre.text,
          cargo: cargo,
          consentimiento: _consentimiento,
        );
        _empleado = r.empleado;
        if (mounted) avisar(context, r.reactivado ? 'Empleado reactivado' : 'Empleado creado');
      } else {
        _empleado = await _ctx.api.actualizarEmpleado(
          _empleado!.id,
          sedeId: _sedeId,
          documento: _documento.text,
          nombre: _nombre.text,
          cargo: cargo,
        );
        if (mounted) avisar(context, 'Cambios guardados');
      }
      _cambio = true;
      _actualizarKiosco();
      return true;
    } on ApiError catch (e) {
      // El plan no admite a nadie más: se explica en su hoja, no como error.
      if (!mounted) return false;
      if (await manejarLimite(context, _ctx.api, e)) return false;
      setState(() {
        _error = e.mensaje;
        _campoError = e.campo;
      });
      return false;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _actualizarKiosco() => context.read<EstadoApp>().sincronizador?.sincronizar();

  Future<void> _registrarRostro() async {
    if (_esNuevo && !await _guardar()) return;
    if (!mounted || _empleado == null) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EnrolarPage(empleado: _empleado!), fullscreenDialog: true),
    );
    if (ok == true) {
      _cambio = true;
      try {
        final actualizado = await _ctx.api.empleado(_empleado!.id);
        if (mounted) setState(() => _empleado = actualizado);
      } on ApiError catch (_) {}
    }
  }

  Future<void> _darDeBaja() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.person_remove_outlined, color: c.sem.peligro),
        title: const Text('¿Dar de baja?'),
        content: Text(
          '${_empleado!.nombre} ya no podrá marcar. Su historial de asistencia se conserva '
          'y sus fotos del rostro se eliminan del servidor y de los kioscos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.sem.peligro, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _guardando = true);
    try {
      await _ctx.api.desactivarEmpleado(_empleado!.id);
      _actualizarKiosco();
      if (mounted) {
        avisar(context, 'Empleado dado de baja');
        Navigator.of(context).pop(true);
      }
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String? _errorDe(String campo) => _campoError == campo ? _error : null;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) Navigator.of(context).pop(_cambio);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_esNuevo ? 'Nuevo empleado' : 'Editar empleado'),
          leading: BackButton(onPressed: () => Navigator.of(context).pop(_cambio)),
        ),
        body: Form(
          key: _formulario,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, 120),
            children: [
              const Etiqueta('Datos del empleado'),
              const SizedBox(height: Espacio.sm),
              TextFormField(
                controller: _documento,
                decoration: InputDecoration(
                  labelText: 'Documento de identidad',
                  helperText: 'Sin puntos ni espacios',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  errorText: _errorDe('documento'),
                ),
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final t = (v ?? '').replaceAll(RegExp(r'[\s.]'), '');
                  return RegExp(r'^[A-Za-z0-9-]{3,20}$').hasMatch(t) ? null : 'Entre 3 y 20 letras o números';
                },
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _nombre,
                decoration: InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  errorText: _errorDe('nombre'),
                ),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().length < 3 ? 'Escribe el nombre completo' : null,
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _cargo,
                decoration: InputDecoration(
                  labelText: 'Cargo (opcional)',
                  prefixIcon: const Icon(Icons.work_outline_rounded),
                  errorText: _errorDe('cargo'),
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 60,
              ),
              const SizedBox(height: Espacio.xs),
              DropdownButtonFormField<int>(
                initialValue: _ctx.sedes.any((s) => s.id == _sedeId) ? _sedeId : null,
                decoration: InputDecoration(
                  labelText: 'Sede',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  errorText: _errorDe('sede_id'),
                ),
                items: [for (final s in _ctx.sedes) DropdownMenuItem(value: s.id, child: Text(s.nombre))],
                onChanged: (v) => setState(() => _sedeId = v ?? _sedeId),
                validator: (v) => v == null ? 'Selecciona la sede' : null,
              ),
              if (_error != null && _campoError == null) ...[
                const SizedBox(height: Espacio.md),
                MensajeError(_error!),
              ],
              const SizedBox(height: Espacio.xl),
              const Etiqueta('Reconocimiento facial'),
              const SizedBox(height: Espacio.sm),
              _TarjetaRostro(
                empleado: _empleado,
                api: _ctx.api,
                consentimiento: _consentimiento,
                alConsentir: (v) => setState(() => _consentimiento = v),
                alRegistrar: _guardando || !_consentimiento ? null : _registrarRostro,
              ),
              if (_empleado != null) ...[
                const SizedBox(height: Espacio.xl),
                const Etiqueta('Horario'),
                const SizedBox(height: Espacio.sm),
                TarjetaHorarioEmpleado(key: ValueKey(_empleado!.id), empleado: _empleado!),
              ],
              if (!_esNuevo) ...[
                const SizedBox(height: Espacio.xl),
                OutlinedButton.icon(
                  onPressed: _guardando ? null : _darDeBaja,
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('Dar de baja'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: sem.peligro,
                    side: BorderSide(color: sem.peligro.withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(Espacio.md),
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.save_outlined),
            label: Text(_esNuevo ? 'Crear empleado' : 'Guardar cambios'),
          ),
        ),
      ),
    );
  }
}

class _TarjetaRostro extends StatelessWidget {
  const _TarjetaRostro({
    required this.empleado,
    required this.api,
    required this.consentimiento,
    required this.alConsentir,
    required this.alRegistrar,
  });

  final Empleado? empleado;
  final Api api;
  final bool consentimiento;
  final ValueChanged<bool> alConsentir;
  final VoidCallback? alRegistrar;

  static String _fecha(DateTime f) {
    final l = f.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final fotos = empleado?.fotos ?? const <FotoRef>[];
    final tiene = fotos.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  tiene ? Icons.verified_user_rounded : Icons.face_retouching_off_rounded,
                  color: tiene ? sem.entrada : sem.alerta,
                ),
                const SizedBox(width: Espacio.sm),
                Expanded(
                  child: Text(
                    tiene ? 'Rostro registrado (${fotos.length} fotos)' : 'Rostro sin registrar',
                    style: context.textos.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espacio.xxs),
            Text(
              tiene
                  ? 'Los kioscos de la sede ya pueden reconocer a esta persona.'
                  : 'Necesario para que pueda marcar entrada y salida.',
              style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
            ),
            if (tiene) ...[
              const SizedBox(height: Espacio.md),
              Row(
                children: [
                  for (final f in fotos)
                    Padding(
                      padding: const EdgeInsets.only(right: Espacio.xs),
                      child: Builder(builder: (context) {
                        final ref = api.foto(empleado!.id, f.n, f.v);
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(Redondeo.md),
                          child: Image.network(
                            ref.url,
                            headers: ref.cabeceras,
                            width: 76,
                            height: 96,
                            fit: BoxFit.cover,
                            semanticLabel: 'Foto ${f.n} del rostro',
                            errorBuilder: (_, _, _) => Container(
                              width: 76,
                              height: 96,
                              color: context.colores.surfaceContainer,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        );
                      }),
                    ),
                ],
              ),
            ],
            if (empleado?.cuentaEmail != null) ...[
              const SizedBox(height: Espacio.sm),
              Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: context.colores.primary),
                  const SizedBox(width: Espacio.xs),
                  Expanded(
                    child: Text(
                      empleado!.cuentaActiva
                          ? 'Tiene cuenta (${empleado!.cuentaEmail}): también entra a las apps.'
                          : 'Su cuenta (${empleado!.cuentaEmail}) está inactiva: no puede marcar.',
                      style: context.textos.bodySmall?.copyWith(color: empleado!.cuentaActiva ? null : sem.peligro),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Espacio.sm),
            if (empleado?.consentimientoEn != null)
              // Ya quedó registrada (quién y cuándo, en el servidor): no se vuelve a pedir.
              Row(
                children: [
                  Icon(Icons.verified_outlined, size: 18, color: sem.entrada),
                  const SizedBox(width: Espacio.xs),
                  Expanded(
                    child: Text(
                      'Autorización de datos biométricos registrada el ${_fecha(empleado!.consentimientoEn!)}.',
                      style: context.textos.bodySmall,
                    ),
                  ),
                ],
              )
            else
              CheckboxListTile(
                value: consentimiento,
                onChanged: (v) => alConsentir(v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'El empleado autorizó el tratamiento de sus datos biométricos (Ley 1581 de 2012).',
                  style: context.textos.bodyMedium,
                ),
                subtitle: Text(
                  'Queda registrado quién lo confirmó y cuándo.',
                  style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                ),
              ),
            const SizedBox(height: Espacio.xs),
            FilledButton.tonalIcon(
              onPressed: alRegistrar,
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: Text(
                empleado == null
                    ? 'Guardar y registrar rostro'
                    : tiene
                        ? 'Volver a registrar rostro'
                        : 'Registrar rostro',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
