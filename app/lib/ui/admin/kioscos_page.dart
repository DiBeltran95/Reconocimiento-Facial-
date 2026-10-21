import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import 'contexto_admin.dart';

/// Teléfonos de marcación agrupados por sede. Suelen ser del mismo modelo y
/// usar la misma cuenta Operario: el código corto (visible en su pantalla)
/// dice cuál es cuál, para renombrarlo o desvincularlo sin tocar los demás.
class KioscosPage extends StatefulWidget {
  const KioscosPage({super.key});

  @override
  State<KioscosPage> createState() => _KioscosPageState();
}

class _KioscosPageState extends State<KioscosPage> {
  late final Api _api = context.read<ContextoAdmin>().api;
  List<KioscoRegistrado>? _lista;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final l = await _api.kioscos();
      if (mounted) {
        setState(() {
          _lista = l;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _renombrar(KioscoRegistrado k) async {
    final nombre = await showDialog<String>(context: context, builder: (_) => _DialogoNombre(actual: k.nombre));
    if (nombre == null || nombre == k.nombre) return;
    try {
      await _api.renombrarKiosco(k.id, nombre);
      if (mounted) avisar(context, 'Ahora se llama «$nombre»');
      _cargar();
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    }
  }

  Future<void> _revocar(KioscoRegistrado k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Desvincular «${k.nombre}»?'),
        content: Text(
          'El teléfono${k.codigo == null ? '' : ' con código ${k.codigo}'} dejará de registrar marcaciones '
          'hasta que lo vuelvan a vincular. Los demás teléfonos siguen igual.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.sem.peligro, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.revocarKiosco(k.id);
      if (mounted) avisar(context, 'Teléfono desvinculado');
      _cargar();
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista;
    final porSede = <String, List<KioscoRegistrado>>{};
    for (final k in lista ?? const <KioscoRegistrado>[]) {
      porSede.putIfAbsent(k.sede, () => []).add(k);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Teléfonos de marcación')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: lista == null
            ? (_error != null
                ? ListView(children: [EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudo cargar', mensaje: _error, accion: _cargar)])
                : const Center(child: CircularProgressIndicator()))
            : lista.isEmpty
                ? ListView(children: const [
                    EstadoVacio(
                      icono: Icons.devices_other_rounded,
                      titulo: 'No hay teléfonos de marcación',
                      mensaje: 'Instala Presente en el teléfono de cada sede e inicia sesión con la cuenta Operario.',
                    ),
                  ])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.xxl),
                    children: [
                      for (final MapEntry(key: sede, value: telefonos) in porSede.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Espacio.xxs, Espacio.md, 0, Espacio.xs),
                          child: Etiqueta('$sede · ${telefonos.length}'),
                        ),
                        for (final k in telefonos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Espacio.xs),
                            child: _TarjetaTelefono(
                              k: k,
                              alRenombrar: () => _renombrar(k),
                              alRevocar: () => _revocar(k),
                            ),
                          ),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _TarjetaTelefono extends StatelessWidget {
  const _TarjetaTelefono({required this.k, required this.alRenombrar, required this.alRevocar});
  final KioscoRegistrado k;
  final VoidCallback alRenombrar;
  final VoidCallback alRevocar;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final minutos = k.ultimoSync == null ? null : DateTime.now().difference(k.ultimoSync!).inMinutes;
    final (texto, color) = switch (minutos) {
      null => ('Sin señal', sem.peligro),
      < 15 => ('En línea', sem.entrada),
      < 1440 => ('Inactivo', sem.alerta),
      _ => ('Sin señal', sem.peligro),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.sm, Espacio.xs, Espacio.sm),
        child: Row(
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: Espacio.xs),
              decoration: BoxDecoration(
                color: context.colores.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Redondeo.sm),
              ),
              child: Text(
                k.codigo ?? '—',
                textAlign: TextAlign.center,
                semanticsLabel: k.codigo == null ? 'Sin código' : 'Código ${k.codigo!.split('').join(' ')}',
                style: Hud.mono(tam: 15, color: context.colores.primary, peso: FontWeight.w700, espaciado: 1.5),
              ),
            ),
            const SizedBox(width: Espacio.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k.nombre, style: context.textos.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      'Última conexión ${Formato.haceCuanto(k.ultimoSync)}',
                      if (k.vinculadoPor != null) 'vinculó ${k.vinculadoPor}',
                    ].join(' · '),
                    style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                  ),
                  const SizedBox(height: Espacio.xxs),
                  Pildora(texto: texto, color: color),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Opciones de ${k.nombre}',
              onSelected: (v) => v == 'renombrar' ? alRenombrar() : alRevocar(),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'renombrar',
                  child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Renombrar')),
                ),
                PopupMenuItem(
                  value: 'revocar',
                  child: ListTile(
                    leading: Icon(Icons.link_off_rounded, color: sem.peligro),
                    title: Text('Desvincular', style: TextStyle(color: sem.peligro)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogoNombre extends StatefulWidget {
  const _DialogoNombre({required this.actual});
  final String actual;

  @override
  State<_DialogoNombre> createState() => _DialogoNombreState();
}

class _DialogoNombreState extends State<_DialogoNombre> {
  late final _nombre = TextEditingController(text: widget.actual);

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _aceptar() {
    final t = _nombre.text.trim();
    if (t.isNotEmpty) Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nombre del teléfono'),
      content: TextField(
        controller: _nombre,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _aceptar(),
        decoration: const InputDecoration(hintText: 'Recepción, Bodega…'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Guardar')),
      ],
    );
  }
}
