import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../../servicios/estado_app.dart';
import '../admin/acceso_admin.dart' show MensajeError;
import '../comun/vincular_telefono.dart';
import '../comun/widgets.dart';
import 'recuperar_clave_page.dart';
import 'registro_empresa_page.dart';
import 'sin_acceso.dart';

/// Iniciar sesión, crear la cuenta de la empresa o recuperar la contraseña.
///
/// Es la misma cuenta de Ventario: quien se registró allá entra aquí sin
/// activar nada. Según el rol:
///  - Operario: el teléfono queda como punto de marcación (elige la sede) y su
///    sesión no se guarda: nunca ve ni cambia credenciales.
///  - Administrador, gerente o talento humano: devuelve `true` y quien abrió
///    esta página lleva al panel.
class IniciarSesionPage extends StatefulWidget {
  const IniciarSesionPage({super.key});

  @override
  State<IniciarSesionPage> createState() => _IniciarSesionPageState();
}

class _IniciarSesionPageState extends State<IniciarSesionPage> {
  late final EstadoApp _estado = context.read<EstadoApp>();
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _clave = TextEditingController();

  bool _cargando = false;
  bool _ocultar = true;
  String? _error;
  ApiError? _sinAcceso;

  Api get _api => _estado.api;

  @override
  void dispose() {
    _email.dispose();
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
      if (!mounted) return;
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

  Future<void> _ingresar() async {
    if (!_form.currentState!.validate()) return;
    await _ejecutar(() async {
      final sesion = await _estado.sesion.iniciar(_email.text.trim().toLowerCase(), _clave.text);
      TextInput.finishAutofillContext();
      await _continuar(sesion);
    });
  }

  Future<void> _continuar(SesionAdmin sesion) async {
    if (!sesion.esOperario) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    try {
      if (!mounted) return;
      final config = _estado.config;
      if (config != null) {
        throw ApiError(
          409,
          'Este teléfono ya marca asistencia en ${config.sede.nombre}. '
          'Para cambiarlo de sede, un administrador o talento humano debe desvincularlo primero.',
        );
      }
      final registro = await vincularEsteTelefono(context, _estado);
      if (registro == null || !mounted) return;
      avisar(context, 'Listo: este teléfono marca asistencia en ${registro.sede.nombre}');
      Navigator.of(context).pop(false);
    } finally {
      // La cuenta Operario solo vincula: su sesión no se queda en el teléfono.
      _estado.sesion.cerrar();
    }
  }

  Future<void> _crearEmpresa() async {
    final sesion = await Navigator.of(context).push<SesionAdmin>(
      MaterialPageRoute(builder: (_) => RegistroEmpresaPage(api: _api)),
    );
    if (sesion == null || !mounted) return;
    _estado.sesion.adoptar(sesion);
    avisar(context, '¡${sesion.empresa?.nombre ?? 'Tu empresa'} quedó creada!');
    Navigator.of(context).pop(true);
  }

  Future<void> _recuperar() async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RecuperarClavePage(api: _api, email: _email.text.trim())),
    );
    if (email != null && mounted) {
      setState(() {
        _email.text = email;
        _clave.clear();
      });
    }
  }

  void _usarOtraCuenta() => setState(() {
        _sinAcceso = null;
        _clave.clear();
        _estado.sesion.cerrar();
      });

  Future<void> _cambiarServidor() async {
    final nueva = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoServidor(actual: _api.baseUrl),
    );
    if (nueva == null || !mounted) return;
    await _estado.cambiarServidor(nueva);
    if (mounted) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final vinculado = context.select<EstadoApp, bool>((e) => e.configurado);
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: FondoTecnico(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Espacio.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Etiqueta('Presente'),
                    const SizedBox(height: Espacio.xs),
                    Text('Iniciar sesión', style: context.textos.displaySmall),
                    const SizedBox(height: Espacio.xs),
                    Text(
                      vinculado
                          ? 'Para administrar: personal, horarios, reportes y teléfonos.'
                          : 'Con la cuenta Operario de tu empresa este teléfono queda listo para marcar asistencia.',
                      style: context.textos.bodyLarge?.copyWith(color: context.sem.textoSuave),
                    ),
                    const SizedBox(height: Espacio.lg),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Espacio.lg),
                        child: AnimatedSwitcher(
                          duration: context.sinMovimiento ? Duration.zero : Duraciones.media,
                          child: _sinAcceso != null
                              ? PanelSinAcceso(
                                  key: const ValueKey('sin-acceso'),
                                  error: _sinAcceso!,
                                  alUsarOtraCuenta: _usarOtraCuenta,
                                )
                              : _formulario(vinculado),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Espacio.md),
                      MensajeError(_error!),
                    ],
                    if (!vinculado) ...[
                      const SizedBox(height: Espacio.md),
                      Center(
                        child: TextButton.icon(
                          onPressed: _cargando ? null : _cambiarServidor,
                          icon: const Icon(Icons.dns_outlined, size: 18),
                          label: Text('Servidor: ${Uri.tryParse(_api.baseUrl)?.host ?? _api.baseUrl}'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formulario(bool vinculado) => Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'El mismo correo y contraseña de Ventario.',
                style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.alternate_email_rounded)),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Escribe tu correo' : null,
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _clave,
                obscureText: _ocultar,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _ingresar(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                    icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _cargando ? null : _recuperar,
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              FilledButton.icon(
                onPressed: _cargando ? null : _ingresar,
                icon: _cargando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.arrow_forward_rounded),
                label: const Text('Ingresar'),
              ),
              if (!vinculado) ...[
                const SizedBox(height: Espacio.md),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Espacio.sm),
                      child: Text(
                        '¿Tu empresa es nueva aquí?',
                        style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: Espacio.md),
                OutlinedButton.icon(
                  onPressed: _cargando ? null : _crearEmpresa,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Crear cuenta de empresa gratis'),
                ),
              ] else ...[
                const SizedBox(height: Espacio.xs),
                Text(
                  'La sesión se cierra sola tras 5 minutos sin uso.',
                  textAlign: TextAlign.center,
                  style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
                ),
              ],
            ],
          ),
        ),
      );
}

/// Opción avanzada: apuntar la app a otro servidor (instalaciones propias).
class _DialogoServidor extends StatefulWidget {
  const _DialogoServidor({required this.actual});
  final String actual;

  @override
  State<_DialogoServidor> createState() => _DialogoServidorState();
}

class _DialogoServidorState extends State<_DialogoServidor> {
  late final _url = TextEditingController(text: widget.actual);
  bool _probando = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _probar() async {
    final url = Api.normalizarUrl(_url.text);
    if (url.isEmpty) return setState(() => _error = 'Escribe la dirección del servidor');
    setState(() {
      _probando = true;
      _error = null;
    });
    try {
      await Api(baseUrl: url).salud();
      if (mounted) Navigator.of(context).pop(url);
    } on ApiError catch (e) {
      setState(() => _error = 'No responde: ${e.mensaje}');
    } on FormatException {
      setState(() => _error = 'La dirección no es válida');
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Servidor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Solo cámbialo si tu empresa tiene una instalación propia.',
            style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
          ),
          const SizedBox(height: Espacio.md),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => _probar(),
            decoration: InputDecoration(labelText: 'URL del servidor', errorText: _error, errorMaxLines: 3),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _probando ? null : () => Navigator.of(context).pop(Api.urlPorDefecto),
          child: const Text('Restablecer'),
        ),
        FilledButton(
          onPressed: _probando ? null : _probar,
          child: _probando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Conectar'),
        ),
      ],
    );
  }
}
