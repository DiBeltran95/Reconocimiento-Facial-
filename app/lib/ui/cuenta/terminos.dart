import 'package:flutter/material.dart';

import '../../core/tema.dart';

/// Dirección pública de la política completa (la exige Google Play). Se fija
/// al compilar: `--dart-define=URL_PRIVACIDAD=https://…`.
const urlPrivacidad = String.fromEnvironment(
  'URL_PRIVACIDAD',
  defaultValue: 'https://agendaservi.com/privacidad/',
);

/// Resumen de los términos y del tratamiento de datos en lenguaje claro, con
/// la dirección de la versión completa.
Future<void> mostrarTerminos(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.xl),
        children: [
          Text('Términos y tratamiento de datos', style: ctx.textos.headlineSmall),
          const SizedBox(height: Espacio.md),
          for (final (titulo, texto) in _puntos) ...[
            Text(titulo, style: ctx.textos.titleMedium),
            const SizedBox(height: Espacio.xxs),
            Text(texto, style: ctx.textos.bodyMedium?.copyWith(color: ctx.sem.textoSuave)),
            const SizedBox(height: Espacio.md),
          ],
          Text('Versión completa', style: ctx.textos.titleMedium),
          const SizedBox(height: Espacio.xxs),
          SelectableText(urlPrivacidad, style: ctx.textos.bodyMedium?.copyWith(color: ctx.colores.primary)),
          const SizedBox(height: Espacio.lg),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
        ],
      ),
    ),
  );
}

const _puntos = [
  (
    'Qué datos guardamos',
    'De la empresa: nombre, NIT y teléfono. De cada persona: nombre, correo o documento y su rol. '
        'Para la asistencia: la hora de cada entrada y salida, y hasta tres fotos del rostro de quien marca.',
  ),
  (
    'Datos biométricos',
    'El reconocimiento facial se calcula en el teléfono del kiosco. Las fotos se guardan cifradas en '
        'tránsito y en un espacio privado del servidor, solo para que los kioscos de tu empresa reconozcan '
        'a su personal. Se registra quién autorizó cada registro facial y cuándo. Al dar de baja a una '
        'persona, sus fotos se borran.',
  ),
  (
    'Quién es responsable',
    'Tu empresa es la responsable de los datos de su personal y debe contar con su autorización '
        '(Ley 1581 de 2012). La plataforma los trata solo por cuenta de tu empresa.',
  ),
  (
    'Tus derechos',
    'Puedes conocer, actualizar, rectificar y suprimir los datos. El administrador de la empresa puede '
        'eliminar la empresa y sus cuentas desde Ajustes → Mi empresa.',
  ),
  (
    'Planes',
    'El plan Gratis no tiene costo. Los planes con más capacidad se contratan directamente con el equipo '
        'de la plataforma, fuera de la app.',
  ),
];
