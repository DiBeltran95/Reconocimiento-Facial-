import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../../servicios/config_dispositivo.dart';
import '../../servicios/estado_app.dart';
import '../admin/acceso_admin.dart';
import '../comun/widgets.dart';
import '../cuenta/recuperar_clave_page.dart';
import '../cuenta/registro_empresa_page.dart';
import '../cuenta/sin_acceso.dart';

/// Primer arranque: entrar con la cuenta de la empresa (o crearla) y vincular
/// este teléfono a una sede como kiosco.
///
/// El servidor viene configurado de fábrica: quien instala desde la tienda no
/// escribe ninguna dirección. Cambiarlo queda como opción avanzada.
class BienvenidaPage extends StatefulWidget {
  const BienvenidaPage({super.key});

  @override
  State<BienvenidaPage> createState() => _BienvenidaPageState();
}

class _BienvenidaPageState extends State<BienvenidaPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  final _nombre = TextEditingController();

  int _paso = 0;
  bool _cargando = false;
  bool _ocultar = true;
  String? _error;
  ApiError? _sinAcceso;
  Api _api = Api(baseUrl: Api.urlPorDefecto);
  SesionAdmin? _sesion;
  List<Sede> _sedes = const [];
  Sede? _sede;

  @override
  void initState() {
    super.initState();
    ConfigDispositivo.ultimaUrl().then((u) {
      if (u != null && u.isNotEmpty && mounted) setState(() => _api = Api(baseUrl: u));
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _clave.dispose();
    _nombre.dispose();
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
      final sesion = await _api.login(_email.text.trim().toLowerCase(), _clave.text);
      TextInput.finishAutofillContext();
      await _continuarConSesion(sesion);
    });
  }

  Future<void> _crearEmpresa() async {
    final sesion = await Navigator.of(context).push<SesionAdmin>(
      MaterialPageRoute(builder: (_) => RegistroEmpresaPage(api: _api)),
    );
    if (sesion == null || !mounted) return;
    await _ejecutar(() => _continuarConSesion(sesion, nueva: true));
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

  Future<void> _continuarConSesion(SesionAdmin sesion, {bool nueva = false}) async {
    await ConfigDispositivo.recordarUrl(_api.baseUrl);
    final sedes = await _api.sedes();
    if (sedes.isEmpty) {
      throw const ApiError(403, 'Tu cuenta no tiene sedes asignadas. Pídele al administrador que te asigne una.');
    }
    setState(() {
      _sesion = sesion;
      _sedes = sedes;
      _sede = sedes.first;
      _nombre.text = 'Kiosco ${sedes.first.nombre}';
      _paso = 1;
    });
    if (nueva && mounted) avisar(context, '¡${sesion.empresa?.nombre ?? 'Tu empresa'} quedó creada!');
  }

  Future<void> _vincular() => _ejecutar(() async {
        final estado = context.read<EstadoApp>();
        final nombre = _nombre.text.trim();
        if (nombre.isEmpty) throw const ApiError(422, 'Ponle un nombre a este kiosco');
        final registro = await _api.registrarDispositivo(_sede!.id, nombre);
        await estado.vincular(ConfigDispositivo(
          url: _api.baseUrl,
          token: registro.token,
          sede: registro.sede,
          nombre: registro.nombre,
        ));
      });

  void _usarOtraCuenta() => setState(() {
        _sinAcceso = null;
        _clave.clear();
        _api.tokenAdmin = null;
      });

  Future<void> _cambiarServidor() async {
    final nueva = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoServidor(actual: _api.baseUrl),
    );
    if (nueva == null || !mounted) return;
    setState(() {
      _api = Api(baseUrl: nueva);
      _error = null;
    });
    await ConfigDispositivo.recordarUrl(nueva);
  }

  @override
  Widget build(BuildContext context) {
    final aviso = context.select<EstadoApp, String?>((e) => e.avisoDesvinculado);
    return Scaffold(
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
                    const _Logo(),
                    const SizedBox(height: Espacio.lg),
                    Etiqueta(_sesion?.empresa?.nombre ?? 'Control de personal'),
                    const SizedBox(height: Espacio.xs),
                    Text(_paso == 0 ? 'Bienvenido' : 'Configura este kiosco', style: context.textos.displaySmall),
                    const SizedBox(height: Espacio.xs),
                    Text(
                      _paso == 0
                          ? 'Registra entradas y salidas de tu equipo con reconocimiento facial, incluso sin internet.'
                          : 'Vincula el teléfono a una sede: solo el personal de esa sede podrá marcar aquí.',
                      style: context.textos.bodyLarge?.copyWith(color: context.sem.textoSuave),
                    ),
                    if (aviso != null) ...[
                      const SizedBox(height: Espacio.md),
                      MensajeError(aviso),
                    ],
                    const SizedBox(height: Espacio.lg),
                    _IndicadorPasos(paso: _paso),
                    const SizedBox(height: Espacio.lg),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Espacio.lg),
                        child: AnimatedSize(
                          duration: context.sinMovimiento ? Duration.zero : Duraciones.media,
                          curve: Curves.easeOutCubic,
                          child: AnimatedSwitcher(
                            duration: context.sinMovimiento ? Duration.zero : Duraciones.media,
                            child: KeyedSubtree(
                              key: ValueKey('$_paso-${_sinAcceso != null}'),
                              child: _sinAcceso != null
                                  ? PanelSinAcceso(error: _sinAcceso!, alUsarOtraCuenta: _usarOtraCuenta)
                                  : _contenidoPaso(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Espacio.md),
                      MensajeError(_error!),
                    ],
                    if (_paso == 0) ...[
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

  Widget _boton(String texto, VoidCallback accion, {IconData icono = Icons.arrow_forward_rounded}) => FilledButton.icon(
        onPressed: _cargando ? null : accion,
        icon: _cargando
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Icon(icono),
        label: Text(texto),
      );

  Widget _contenidoPaso() => _paso == 0 ? _pasoAcceso() : _pasoSede();

  Widget _pasoAcceso() => Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Entra con tu cuenta', style: context.textos.titleLarge),
              const SizedBox(height: Espacio.xxs),
              Text(
                'El mismo correo con el que entras a las apps de tu empresa.',
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
              _boton('Ingresar', _ingresar),
              const SizedBox(height: Espacio.md),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Espacio.sm),
                    child: Text('¿Tu empresa es nueva aquí?', style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave)),
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
            ],
          ),
        ),
      );

  Widget _pasoSede() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sede de este kiosco', style: context.textos.titleLarge),
          const SizedBox(height: Espacio.xxs),
          Text(
            'Solo el personal de esta sede podrá marcar aquí.',
            style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
          ),
          const SizedBox(height: Espacio.md),
          RadioGroup<int>(
            groupValue: _sede?.id,
            onChanged: (id) {
              final s = _sedes.firstWhere((x) => x.id == id);
              setState(() {
                _sede = s;
                _nombre.text = 'Kiosco ${s.nombre}';
              });
            },
            child: Column(
              children: [
                for (final s in _sedes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.xs),
                    child: _OpcionSede(sede: s, elegida: _sede?.id == s.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Espacio.sm),
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Nombre del kiosco', prefixIcon: Icon(Icons.phone_android_rounded)),
          ),
          const SizedBox(height: Espacio.md),
          _boton('Vincular y comenzar', _vincular, icono: Icons.link_rounded),
          TextButton(
            onPressed: _cargando
                ? null
                : () => setState(() {
                      _paso = 0;
                      _sesion = null;
                      _api.tokenAdmin = null;
                    }),
            child: const Text('Usar otra cuenta'),
          ),
        ],
      );
}

/// Opción avanzada: apuntar el kiosco a otro servidor (instalaciones propias).
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

class _OpcionSede extends StatelessWidget {
  const _OpcionSede({required this.sede, required this.elegida});
  final Sede sede;
  final bool elegida;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return AnimatedContainer(
      duration: Duraciones.rapida,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Redondeo.md),
        border: Border.all(color: elegida ? c.primary : c.outlineVariant, width: elegida ? 2 : 1),
        color: elegida ? c.primary.withValues(alpha: 0.08) : null,
      ),
      child: RadioListTile<int>(
        value: sede.id,
        title: Text(sede.nombre),
        subtitle: sede.direccion == null ? null : Text(sede.direccion!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Redondeo.md)),
      ),
    );
  }
}

class _IndicadorPasos extends StatelessWidget {
  const _IndicadorPasos({required this.paso});
  final int paso;

  static const _nombres = ['Acceso', 'Sede'];

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Semantics(
      label: 'Paso ${paso + 1} de 2: ${_nombres[paso]}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < _nombres.length; i++) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: context.sinMovimiento ? Duration.zero : Duraciones.media,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i <= paso ? c.primary : c.outlineVariant,
                      boxShadow: i == paso ? [BoxShadow(color: c.primary.withValues(alpha: 0.6), blurRadius: 10)] : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '0${i + 1} ${_nombres[i].toUpperCase()}',
                    style: context.textos.labelSmall?.copyWith(color: i <= paso ? c.primary : context.sem.textoSuave),
                  ),
                ],
              ),
            ),
            if (i < _nombres.length - 1) const SizedBox(width: Espacio.xs),
          ],
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Redondeo.lg),
          gradient: LinearGradient(colors: sem.degradado, begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: sem.degradado.first.withValues(alpha: 0.45), blurRadius: 24)],
        ),
        child: const Icon(Icons.face_unlock_outlined, size: 34, color: Colors.white, semanticLabel: 'Control de personal'),
      ),
    );
  }
}
