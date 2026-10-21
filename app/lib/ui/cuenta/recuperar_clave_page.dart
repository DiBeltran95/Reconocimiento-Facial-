import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../admin/acceso_admin.dart' show MensajeError;
import '../comun/widgets.dart';
import 'registro_empresa_page.dart' show FortalezaClave;

/// Recuperar la contraseña: se pide un código al correo y con él se crea una
/// nueva. Devuelve el correo al terminar (para dejarlo escrito en el acceso).
class RecuperarClavePage extends StatefulWidget {
  const RecuperarClavePage({super.key, required this.api, this.email = ''});
  final Api api;
  final String email;

  @override
  State<RecuperarClavePage> createState() => _RecuperarClavePageState();
}

class _RecuperarClavePageState extends State<RecuperarClavePage> {
  final _formCorreo = GlobalKey<FormState>();
  final _formCodigo = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _codigo = TextEditingController();
  final _clave = TextEditingController();

  bool _codigoEnviado = false;
  bool _ocultar = true;
  bool _cargando = false;
  int _vigencia = 15;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _codigo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await accion();
    } on ApiError catch (e) {
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _pedirCodigo() async {
    if (!_formCorreo.currentState!.validate()) return;
    await _ejecutar(() async {
      _vigencia = await widget.api.recuperarClave(_email.text.trim().toLowerCase());
      setState(() => _codigoEnviado = true);
    });
  }

  Future<void> _restablecer() async {
    if (!_formCodigo.currentState!.validate()) return;
    await _ejecutar(() async {
      await widget.api.restablecerClave(
        email: _email.text.trim().toLowerCase(),
        codigo: _codigo.text.trim(),
        password: _clave.text,
      );
      TextInput.finishAutofillContext();
      if (!mounted) return;
      avisar(context, 'Listo: ya puedes entrar con tu contraseña nueva');
      Navigator.of(context).pop(_email.text.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: FondoTecnico(
        intensidad: 0.6,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Espacio.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Espacio.lg),
                    child: AnimatedSwitcher(
                      duration: context.sinMovimiento ? Duration.zero : Duraciones.media,
                      child: _codigoEnviado ? _pasoCodigo() : _pasoCorreo(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _boton(String texto, VoidCallback accion) => FilledButton(
        onPressed: _cargando ? null : accion,
        child: _cargando
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Text(texto),
      );

  Widget _pasoCorreo() => Form(
        key: _formCorreo,
        child: Column(
          key: const ValueKey('correo'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('¿Con qué correo entras?', style: context.textos.titleLarge),
            const SizedBox(height: Espacio.xxs),
            Text(
              'Te enviaremos un código de 6 números para crear una contraseña nueva.',
              style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
            ),
            const SizedBox(height: Espacio.md),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.send,
              onFieldSubmitted: (_) => _pedirCodigo(),
              decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.alternate_email_rounded)),
              validator: (v) =>
                  RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Escribe un correo válido',
            ),
            if (_error != null) ...[const SizedBox(height: Espacio.md), MensajeError(_error!)],
            const SizedBox(height: Espacio.lg),
            _boton('Enviar código', _pedirCodigo),
          ],
        ),
      );

  Widget _pasoCodigo() => Form(
        key: _formCodigo,
        child: AutofillGroup(
          child: Column(
            key: const ValueKey('codigo'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Revisa tu correo', style: context.textos.titleLarge),
              const SizedBox(height: Espacio.xxs),
              Text(
                'Si ${_email.text.trim()} tiene una cuenta, le llegó un código que vence en $_vigencia minutos. '
                'Revisa también la carpeta de spam.',
                style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _codigo,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                textInputAction: TextInputAction.next,
                style: context.textos.headlineSmall?.copyWith(letterSpacing: 8),
                decoration: const InputDecoration(labelText: 'Código', prefixIcon: Icon(Icons.pin_outlined)),
                validator: (v) => (v ?? '').length == 6 ? null : 'El código tiene 6 números',
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _clave,
                obscureText: _ocultar,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _restablecer(),
                decoration: InputDecoration(
                  labelText: 'Contraseña nueva',
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  suffixIcon: IconButton(
                    tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                    icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: (v) => (v ?? '').length < 8 ? 'Usa al menos 8 caracteres' : null,
              ),
              const SizedBox(height: Espacio.xs),
              FortalezaClave(clave: _clave.text),
              if (_error != null) ...[const SizedBox(height: Espacio.md), MensajeError(_error!)],
              const SizedBox(height: Espacio.lg),
              _boton('Cambiar contraseña', _restablecer),
              TextButton(
                onPressed: _cargando ? null : () => setState(() => _codigoEnviado = false),
                child: const Text('No me llegó: pedir otro código'),
              ),
            ],
          ),
        ),
      );
}
