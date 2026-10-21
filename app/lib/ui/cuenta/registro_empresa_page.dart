import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../admin/acceso_admin.dart' show MensajeError;
import '../comun/widgets.dart';
import 'terminos.dart';

/// Registro de una empresa nueva en tres pasos: tú, tu empresa y tu primera
/// sede. Al terminar, la sesión queda iniciada como administrador y la
/// empresa en el plan Gratis.
///
/// Devuelve la [SesionAdmin] al cerrar (null si se canceló).
class RegistroEmpresaPage extends StatefulWidget {
  const RegistroEmpresaPage({super.key, required this.api});
  final Api api;

  @override
  State<RegistroEmpresaPage> createState() => _RegistroEmpresaPageState();
}

class _RegistroEmpresaPageState extends State<RegistroEmpresaPage> {
  static const _pasos = ['Tú', 'Tu empresa', 'Primera sede'];

  final _formularios = List.generate(3, (_) => GlobalKey<FormState>());
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  final _empresa = TextEditingController();
  final _nit = TextEditingController();
  final _telefono = TextEditingController();
  final _sede = TextEditingController(text: 'Sede principal');

  int _paso = 0;
  bool _ocultar = true;
  bool _acepta = false;
  bool _enviando = false;
  String? _error;
  String? _errorEmail;

  @override
  void dispose() {
    for (final c in [_nombre, _email, _clave, _empresa, _nit, _telefono, _sede]) {
      c.dispose();
    }
    super.dispose();
  }

  void _siguiente() {
    setState(() => _error = null);
    if (!_formularios[_paso].currentState!.validate()) return;
    if (_paso < 2) {
      setState(() => _paso++);
    } else {
      _crear();
    }
  }

  void _atras() {
    if (_paso == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _paso--;
        _error = null;
      });
    }
  }

  Future<void> _crear() async {
    if (!_acepta) {
      setState(() => _error = 'Para crear la empresa acepta los términos y el tratamiento de datos.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final sesion = await widget.api.registrarEmpresa(
        empresa: _empresa.text.trim(),
        nit: _nit.text.trim().isEmpty ? null : _nit.text.trim(),
        telefono: _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
        sede: _sede.text.trim(),
        nombre: _nombre.text.trim(),
        email: _email.text.trim().toLowerCase(),
        password: _clave.text,
      );
      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).pop(sesion);
    } on ApiError catch (e) {
      // El correo repetido se corrige en el paso 1: se lleva allá, junto al campo.
      final esCorreo = e.codigo == 'EMAIL_EN_USO' || (e.campo ?? '').contains('email');
      setState(() {
        if (esCorreo) {
          _paso = 0;
          _errorEmail = e.mensaje;
        } else {
          _error = e.mensaje;
        }
      });
      if (esCorreo) _formularios[0].currentState?.validate();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _paso == 0 && !_enviando,
      onPopInvokedWithResult: (salio, _) {
        if (!salio && !_enviando) _atras();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: _paso == 0 ? 'Cancelar' : 'Paso anterior',
            icon: Icon(_paso == 0 ? Icons.close_rounded : Icons.arrow_back_rounded),
            onPressed: _enviando ? null : _atras,
          ),
          title: const Text('Crear cuenta de empresa'),
        ),
        body: FondoTecnico(
          intensidad: 0.6,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Espacio.lg, Espacio.sm, Espacio.lg, Espacio.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Progreso(paso: _paso, nombres: _pasos),
                      const SizedBox(height: Espacio.lg),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(Espacio.lg),
                          child: AnimatedSwitcher(
                            duration: context.sinMovimiento ? Duration.zero : Duraciones.media,
                            child: KeyedSubtree(key: ValueKey(_paso), child: _contenido()),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: Espacio.md),
                        MensajeError(_error!),
                      ],
                      const SizedBox(height: Espacio.lg),
                      FilledButton.icon(
                        onPressed: _enviando ? null : _siguiente,
                        icon: _enviando
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : Icon(_paso < 2 ? Icons.arrow_forward_rounded : Icons.rocket_launch_outlined),
                        label: Text(_paso < 2 ? 'Continuar' : 'Crear empresa'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenido() => switch (_paso) {
        0 => _pasoTu(),
        1 => _pasoEmpresa(),
        _ => _pasoSede(),
      };

  Widget _encabezado(String titulo, String detalle) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: context.textos.titleLarge),
          const SizedBox(height: Espacio.xxs),
          Text(detalle, style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave)),
          const SizedBox(height: Espacio.md),
        ],
      );

  Widget _pasoTu() => Form(
        key: _formularios[0],
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _encabezado('Tus datos', 'Serás el administrador de la empresa en las apps de la plataforma.'),
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Tu nombre completo', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Escribe tu nombre completo' : null,
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email, AutofillHints.newUsername],
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_errorEmail != null) setState(() => _errorEmail = null);
                },
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  helperText: 'Con él entrarás a Presente y Ventario',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (v) {
                  if (_errorEmail != null) return _errorEmail;
                  final t = (v ?? '').trim();
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Escribe un correo válido';
                },
              ),
              const SizedBox(height: Espacio.md),
              TextFormField(
                controller: _clave,
                obscureText: _ocultar,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _siguiente(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
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
            ],
          ),
        ),
      );

  Widget _pasoEmpresa() => Form(
        key: _formularios[1],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _encabezado('Tu empresa', 'Así aparecerá en las apps y en los reportes.'),
            TextFormField(
              controller: _empresa,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.organizationName],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nombre de la empresa', prefixIcon: Icon(Icons.storefront_outlined)),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Escribe el nombre de la empresa' : null,
            ),
            const SizedBox(height: Espacio.md),
            TextFormField(
              controller: _nit,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'NIT o documento (opcional)',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
            ),
            const SizedBox(height: Espacio.md),
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _siguiente(),
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.call_outlined)),
            ),
          ],
        ),
      );

  Widget _pasoSede() => Form(
        key: _formularios[2],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _encabezado('Tu primera sede', 'El lugar donde trabaja tu equipo. Después podrás agregar más según tu plan.'),
            TextFormField(
              controller: _sede,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Nombre de la sede', prefixIcon: Icon(Icons.place_outlined)),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Ponle un nombre a la sede' : null,
            ),
            const SizedBox(height: Espacio.lg),
            const ResumenPlanGratis(),
            const SizedBox(height: Espacio.md),
            CheckboxListTile(
              value: _acepta,
              onChanged: _enviando ? null : (v) => setState(() => _acepta = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Acepto los términos de uso y el tratamiento de datos personales (Ley 1581 de 2012)'),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 40)),
                  onPressed: () => mostrarTerminos(context),
                  child: const Text('Leer términos y política de datos'),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Lo que incluye el plan Gratis, para decidir con información antes de crear.
class ResumenPlanGratis extends StatelessWidget {
  const ResumenPlanGratis({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    Widget item(IconData icono, String cifra, String texto) => Expanded(
          child: Semantics(
            label: '$cifra $texto',
            excludeSemantics: true,
            child: Column(
              children: [
                Icon(icono, color: c.primary),
                const SizedBox(height: 4),
                Text(cifra, style: context.textos.headlineSmall),
                Text(texto, style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave)),
              ],
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(Espacio.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Redondeo.md),
        border: Border.all(color: c.primary.withValues(alpha: 0.4)),
        color: c.primary.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Etiqueta('Plan Gratis · sin costo')),
              Icon(Icons.verified_outlined, size: 18, color: c.primary),
            ],
          ),
          const SizedBox(height: Espacio.sm),
          Row(
            children: [
              item(Icons.place_outlined, '1', 'sede'),
              item(Icons.groups_outlined, '3', 'personas'),
              item(Icons.inventory_2_outlined, '3', 'productos'),
            ],
          ),
          const SizedBox(height: Espacio.sm),
          Text(
            'Las personas incluyen al administrador y a los gerentes. Puedes usarlo sin límite de tiempo.',
            style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
          ),
        ],
      ),
    );
  }
}

/// Indicador de fortaleza: orienta sin imponer reglas de símbolos (que empujan
/// a patrones predecibles). Texto + barra: nunca solo color.
class FortalezaClave extends StatelessWidget {
  const FortalezaClave({super.key, required this.clave});
  final String clave;

  int get _puntos {
    if (clave.isEmpty) return 0;
    var p = 0;
    if (clave.length >= 8) p++;
    if (clave.length >= 12) p++;
    if (RegExp(r'[A-Z]').hasMatch(clave) && RegExp(r'[a-z]').hasMatch(clave)) p++;
    if (RegExp(r'\d').hasMatch(clave) && RegExp(r'[^A-Za-z0-9]').hasMatch(clave)) p++;
    return p;
  }

  @override
  Widget build(BuildContext context) {
    if (clave.isEmpty) return const SizedBox.shrink();
    final sem = context.sem;
    final p = _puntos;
    final (texto, color) = switch (p) {
      <= 1 => ('Débil: usa al menos 8 caracteres', sem.peligro),
      2 => ('Aceptable', sem.alerta),
      3 => ('Buena', context.colores.primary),
      _ => ('Muy buena', sem.entrada),
    };
    return Semantics(
      label: 'Fortaleza de la contraseña: $texto',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: i < p ? color : sem.borde,
                ),
              ),
            ),
            if (i < 3) const SizedBox(width: 4),
          ],
          const SizedBox(width: Espacio.sm),
          Text(texto, style: context.textos.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _Progreso extends StatelessWidget {
  const _Progreso({required this.paso, required this.nombres});
  final int paso;
  final List<String> nombres;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return Semantics(
      label: 'Paso ${paso + 1} de ${nombres.length}: ${nombres[paso]}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < nombres.length; i++) ...[
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
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '0${i + 1} ${nombres[i].toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textos.labelSmall?.copyWith(color: i <= paso ? c.primary : context.sem.textoSuave),
                  ),
                ],
              ),
            ),
            if (i < nombres.length - 1) const SizedBox(width: Espacio.xs),
          ],
        ],
      ),
    );
  }
}
