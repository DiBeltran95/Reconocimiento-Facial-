import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import 'contexto_admin.dart';

/// Kioscos vinculados en todas las sedes, con su última conexión.
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

  Future<void> _revocar(KioscoRegistrado k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Desvincular «${k.nombre}»?'),
        content: const Text('Ese teléfono dejará de registrar marcaciones hasta que se vuelva a vincular.'),
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
      if (mounted) avisar(context, 'Kiosco desvinculado');
      _cargar();
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista;
    final sem = context.sem;
    return Scaffold(
      appBar: AppBar(title: const Text('Kioscos vinculados')),
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
                      titulo: 'No hay kioscos',
                      mensaje: 'Instala la app en un teléfono y vincúlalo con una cuenta General.',
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(Espacio.md),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Espacio.xs),
                    itemBuilder: (_, i) {
                      final k = lista[i];
                      final minutos = k.ultimoSync == null ? null : DateTime.now().difference(k.ultimoSync!).inMinutes;
                      final (texto, color) = switch (minutos) {
                        null => ('Sin señal', sem.peligro),
                        < 15 => ('En línea', sem.entrada),
                        < 1440 => ('Inactivo', sem.alerta),
                        _ => ('Sin señal', sem.peligro),
                      };
                      return Card(
                        child: ListTile(
                          leading: Icon(Icons.phone_android_rounded, color: context.colores.primary),
                          title: Text(k.nombre),
                          subtitle: Text('${k.sede} · ${Formato.haceCuanto(k.ultimoSync)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Pildora(texto: texto, color: color),
                              IconButton(
                                tooltip: 'Desvincular ${k.nombre}',
                                onPressed: () => _revocar(k),
                                icon: Icon(Icons.link_off_rounded, color: sem.peligro),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
