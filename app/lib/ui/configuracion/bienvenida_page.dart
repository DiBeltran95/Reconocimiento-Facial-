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

/// Asistente de 3 pasos para vincular este teléfono a una sede:
/// servidor → cuenta de administrador → sede y nombre del kiosco.
class BienvenidaPage extends StatefulWidget {
  const BienvenidaPage({super.key});

  @override
  State<BienvenidaPage> createState() => _BienvenidaPageState();
}

class _BienvenidaPageState extends State<BienvenidaPage> {
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  final _nombre = TextEditingController();

  int _paso = 0;
  bool _cargando = false;
  bool _ocultar = true;
  String? _error;
  String _negocio = '';
  Api? _api;
  List<Sede> _sedes = const [];
  Sede? _sede;

  @override
  void initState() {
    super.initState();
    ConfigDispositivo.ultimaUrl().then((u) {
      if (u != null && mounted && _url.text.isEmpty) _url.text = u;
    });
  }

  @override
  void dispose() {
    _url.dispose();
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
      setState(() => _error = e.mensaje);
    } on FormatException {
      setState(() => _error = 'La dirección no es válida');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _conectar() => _ejecutar(() async {
        final url = Api.normalizarUrl(_url.text);
        if (url.isEmpty) throw const ApiError(0, 'Escribe la dirección del servidor');
        final api = Api(baseUrl: url);
        final salud = await api.salud();
        _api = api;
        _url.text = url;
        setState(() {
          _negocio = salud.negocio;
          _paso = 1;
        });
      });

  Future<void> _ingresar() => _ejecutar(() async {
        if (_email.text.trim().length < 3 || _clave.text.isEmpty) {
          throw const ApiError(422, 'Escribe tu usuario y contraseña');
        }
        await _api!.login(_email.text.trim(), _clave.text);
        TextInput.finishAutofillContext();
        final sedes = await _api!.sedes();
        if (sedes.isEmpty) throw const ApiError(403, 'Tu usuario no tiene sedes asignadas');
        setState(() {
          _sedes = sedes;
          _sede = sedes.first;
          _nombre.text = 'Kiosco ${sedes.first.nombre}';
          _paso = 2;
        });
      });

  Future<void> _vincular() => _ejecutar(() async {
        final estado = context.read<EstadoApp>();
        final nombre = _nombre.text.trim();
        if (nombre.isEmpty) throw const ApiError(422, 'Ponle un nombre a este kiosco');
        final registro = await _api!.registrarDispositivo(_sede!.id, nombre);
        await estado.vincular(ConfigDispositivo(
          url: _api!.baseUrl,
          token: registro.token,
          sede: registro.sede,
          nombre: registro.nombre,
        ));
      });

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
                    Etiqueta(_negocio.isEmpty ? 'Control de personal' : _negocio),
                    const SizedBox(height: Espacio.xs),
                    Text('Configura este kiosco', style: context.textos.displaySmall),
                    const SizedBox(height: Espacio.xs),
                    Text(
                      'Vincula el teléfono a una sede para registrar entradas y salidas con reconocimiento facial.',
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
                          duration: Duraciones.media,
                          curve: Curves.easeOutCubic,
                          child: AnimatedSwitcher(
                            duration: Duraciones.media,
                            child: KeyedSubtree(key: ValueKey(_paso), child: _contenidoPaso()),
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Espacio.md),
                      MensajeError(_error!),
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

  Widget _contenidoPaso() {
    switch (_paso) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Servidor', style: context.textos.titleLarge),
            const SizedBox(height: Espacio.xxs),
            Text('Dirección donde está instalado el backend.', style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave)),
            const SizedBox(height: Espacio.md),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _conectar(),
              decoration: const InputDecoration(
                labelText: 'URL del servidor',
                hintText: 'https://asistencia.tuempresa.com',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: Espacio.lg),
            _boton('Conectar', _conectar),
          ],
        );
      case 1:
        return AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tu cuenta', style: context.textos.titleLarge),
              const SizedBox(height: Espacio.xxs),
              Text('Usa una cuenta General (kioscos) o Administrativa.',
                  style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave)),
              const SizedBox(height: Espacio.md),
              TextField(
                controller: _email,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Usuario o correo', prefixIcon: Icon(Icons.person_outline_rounded)),
              ),
              const SizedBox(height: Espacio.md),
              TextField(
                controller: _clave,
                obscureText: _ocultar,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _ingresar(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                    icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: Espacio.lg),
              _boton('Ingresar', _ingresar),
              TextButton(
                onPressed: _cargando ? null : () => setState(() => _paso = 0),
                child: const Text('Cambiar servidor'),
              ),
            ],
          ),
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sede de este kiosco', style: context.textos.titleLarge),
            const SizedBox(height: Espacio.xxs),
            Text('Solo el personal de esta sede podrá marcar aquí.',
                style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave)),
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
          ],
        );
    }
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

  static const _nombres = ['Servidor', 'Acceso', 'Sede'];

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Semantics(
      label: 'Paso ${paso + 1} de 3: ${_nombres[paso]}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: Duraciones.media,
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
            if (i < 2) const SizedBox(width: Espacio.xs),
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
