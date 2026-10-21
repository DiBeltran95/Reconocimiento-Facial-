import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../../servicios/config_dispositivo.dart';
import '../../servicios/estado_app.dart';

/// Convierte ESTE teléfono en punto de marcación. Pide la sede si hay más de
/// una. Devuelve el registro, o null si la persona canceló.
///
/// Cada instalación tiene su propia identidad: con la misma cuenta Operario se
/// vinculan muchos teléfonos (casi siempre del mismo modelo) sin que uno
/// desvincule a otro. El servidor les pone «Sede · Teléfono N» y un código.
Future<DispositivoRegistrado?> vincularEsteTelefono(BuildContext context, EstadoApp estado) async {
  final sedes = await estado.api.sedes();
  if (sedes.isEmpty) {
    throw const ApiError(403, 'Tu empresa aún no tiene sedes en Presente. El administrador debe elegir una en «Sedes».');
  }
  if (!context.mounted) return null;
  final sede = sedes.length == 1 ? sedes.first : await elegirSedeDelTelefono(context, sedes);
  if (sede == null) return null;
  final registro = await estado.api.registrarDispositivo(sede.id, instalacion: await ConfigDispositivo.instalacion());
  await estado.vincular(registro);
  return registro;
}

/// Hoja para elegir en qué sede queda el teléfono.
Future<Sede?> elegirSedeDelTelefono(BuildContext context, List<Sede> sedes) => showModalBottomSheet<Sede>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _HojaSedes(sedes: sedes),
    );

class _HojaSedes extends StatefulWidget {
  const _HojaSedes({required this.sedes});
  final List<Sede> sedes;

  @override
  State<_HojaSedes> createState() => _HojaSedesState();
}

class _HojaSedesState extends State<_HojaSedes> {
  late Sede _sede = widget.sedes.first;

  @override
  Widget build(BuildContext context) {
    final c = context.colores;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('¿En qué sede queda este teléfono?', style: context.textos.headlineSmall),
          const SizedBox(height: Espacio.xxs),
          Text(
            'Aquí marcará el personal de esa sede. Recibirá un nombre y un código corto para reconocerlo.',
            style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
          ),
          const SizedBox(height: Espacio.md),
          RadioGroup<int>(
            groupValue: _sede.id,
            onChanged: (id) => setState(() => _sede = widget.sedes.firstWhere((s) => s.id == id)),
            child: Column(
              children: [
                for (final s in widget.sedes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.xs),
                    child: AnimatedContainer(
                      duration: Duraciones.rapida,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Redondeo.md),
                        border: Border.all(color: s.id == _sede.id ? c.primary : c.outlineVariant, width: s.id == _sede.id ? 2 : 1),
                        color: s.id == _sede.id ? c.primary.withValues(alpha: 0.08) : null,
                      ),
                      child: RadioListTile<int>(
                        value: s.id,
                        title: Text(s.nombre),
                        subtitle: s.direccion == null ? null : Text(s.direccion!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Redondeo.md)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Espacio.md),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_sede),
            icon: const Icon(Icons.link_rounded),
            label: Text('Marcar asistencia en ${_sede.nombre}'),
          ),
        ],
      ),
    );
  }
}
