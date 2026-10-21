import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import 'contexto_admin.dart';

/// Selector de sede: solo aparece si el usuario administra más de una.
class SelectorSede extends StatelessWidget {
  const SelectorSede({super.key});

  @override
  Widget build(BuildContext context) {
    final ctx = context.watch<ContextoAdmin>();
    if (ctx.sedes.length <= 1) {
      return Row(
        children: [
          Icon(Icons.location_on_outlined, size: 18, color: context.colores.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              ctx.sede.nombre,
              style: context.textos.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return DropdownMenu<int>(
      initialSelection: ctx.sede.id,
      expandedInsets: EdgeInsets.zero,
      leadingIcon: const Icon(Icons.location_on_outlined),
      label: const Text('Sede'),
      onSelected: (id) {
        if (id != null) ctx.elegirSede(ctx.sedes.firstWhere((s) => s.id == id));
      },
      dropdownMenuEntries: [
        for (final s in ctx.sedes)
          DropdownMenuEntry(
            value: s.id,
            label: s.nombre,
            trailingIcon: s.id == ctx.sedeDispositivo?.id
                ? Tooltip(message: 'Sede de este teléfono', child: Icon(Icons.phone_android_rounded, size: 18, color: context.colores.primary))
                : null,
          ),
      ],
    );
  }
}
