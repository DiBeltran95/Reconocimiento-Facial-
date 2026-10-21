import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../servicios/estado_app.dart';
import '../comun/widgets.dart';
import '../cuenta/recuperar_clave_page.dart';
import '../cuenta/sin_acceso.dart';
import 'admin_shell.dart';
import 'operador_page.dart';

/// Pide credenciales (si no hay sesión activa) y abre el panel que
/// corresponde al rol: administrativo completo u operador del kiosco.
Future<void> abrirAdministracion(BuildContext context) async {
  final estado = context.read<EstadoApp>();
  if (!estado.sesion.activa) {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(value: estado, child: const HojaAccesoAdmin()),
    );
    if (ok != true || !context.mounted) return;
  }
  final administrativo = estado.sesion.sesion?.esAdministrativo ?? false;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: estado.sincronizador!,
        child: administrativo ? const AdminShell() : const OperadorPage(),
      ),
    ),
  );
}

class HojaAccesoAdmin extends StatefulWidget {
  const HojaAccesoAdmin({super.key});

  @override
  State<HojaAccesoAdmin> createState() => _HojaAccesoAdminState();
}

class _HojaAccesoAdminState extends State<HojaAccesoAdmin> {
  final _email = TextEditingController();
  final _clave = TextEditingController();
  final _formulario = GlobalKey<FormState>();
  bool _ocultar = true;
  bool _cargando = false;
  String? _error;
  ApiError? _sinAcceso;

  @override
  void dispose() {
    _email.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await context.read<EstadoApp>().sesion.iniciar(_email.text.trim().toLowerCase(), _clave.text);
      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      setState(() {
        if (e.sinAccesoApp) {
          _sinAcceso = e;
        } else {
          _error = e.mensaje;
        }
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _recuperar() async {
    final api = context.read<EstadoApp>().api;
    if (api == null) return;
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RecuperarClavePage(api: api, email: _email.text.trim())),
    );
    if (email != null && mounted) setState(() => _email.text = email);
  }

  @override
  Widget build(BuildContext context) {
    if (_sinAcceso != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
        child: PanelSinAcceso(
          error: _sinAcceso!,
          alUsarOtraCuenta: () => setState(() {
            _sinAcceso = null;
            _clave.clear();
          }),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
        child: Form(
          key: _formulario,
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Etiqueta('Acceso restringido'),
                const SizedBox(height: Espacio.xs),
                Text('Ingresar', style: context.textos.headlineMedium),
                const SizedBox(height: Espacio.xxs),
                Text(
                  'Operador: estado y sincronización del kiosco. '
                  'Administrador o gerente: personal, horarios, cumplimiento y reportes.',
                  style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
                ),
                const SizedBox(height: Espacio.lg),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().length < 3) ? 'Escribe tu correo' : null,
                ),
                const SizedBox(height: Espacio.md),
                TextFormField(
                  controller: _clave,
                  obscureText: _ocultar,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _entrar(),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _ocultar = !_ocultar),
                      tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                      icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _cargando ? null : _recuperar,
                    child: const Text('¿Olvidaste tu contraseña?'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Espacio.md),
                  MensajeError(_error!),
                ],
                const SizedBox(height: Espacio.lg),
                FilledButton(
                  onPressed: _cargando ? null : _entrar,
                  child: _cargando
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Ingresar'),
                ),
                const SizedBox(height: Espacio.xs),
                Text(
                  'La sesión se cierra sola tras 5 minutos sin uso.',
                  textAlign: TextAlign.center,
                  style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MensajeError extends StatelessWidget {
  const MensajeError(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Espacio.sm),
        decoration: BoxDecoration(
          color: sem.peligroFondo,
          borderRadius: BorderRadius.circular(Redondeo.sm),
          border: Border.all(color: sem.peligro.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: sem.peligro, size: 20),
            const SizedBox(width: Espacio.xs),
            Expanded(child: Text(texto, style: context.textos.bodyMedium?.copyWith(color: sem.peligro))),
          ],
        ),
      ),
    );
  }
}
