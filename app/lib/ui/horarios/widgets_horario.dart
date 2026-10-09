import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';

/// Color estable por turno (para reconocerlos de un vistazo en listas y planes).
Color colorTurno(BuildContext context, int id) {
  final oscuro = Theme.of(context).brightness == Brightness.dark;
  const oscuros = [Color(0xFF22D3EE), Color(0xFFA78BFA), Color(0xFFFBBF24), Color(0xFF34D399), Color(0xFFF472B6), Color(0xFF60A5FA)];
  const claros = [Color(0xFF0E7490), Color(0xFF6D28D9), Color(0xFFB45309), Color(0xFF047857), Color(0xFFBE185D), Color(0xFF1D4ED8)];
  final lista = oscuro ? oscuros : claros;
  return lista[id % lista.length];
}

/// Línea de tiempo del día (5:00 → 23:00) con los bloques del turno.
class BarraTurno extends StatelessWidget {
  const BarraTurno({super.key, required this.bloques, required this.color, this.alto = 26, this.marcas = true});

  final List<Bloque> bloques;
  final Color color;
  final double alto;
  final bool marcas;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Horario: ${bloques.map((b) => '${hhmm(b.inicio)} a ${hhmm(b.fin)}').join(' y ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: alto + (marcas ? 16 : 0),
        child: CustomPaint(
          size: Size.infinite,
          painter: _PintorBarra(
            bloques: bloques,
            color: color,
            pista: context.colores.outlineVariant,
            texto: context.sem.textoSuave,
            alto: alto,
            marcas: marcas,
          ),
        ),
      ),
    );
  }
}

class _PintorBarra extends CustomPainter {
  _PintorBarra({
    required this.bloques,
    required this.color,
    required this.pista,
    required this.texto,
    required this.alto,
    required this.marcas,
  });

  final List<Bloque> bloques;
  final Color color;
  final Color pista;
  final Color texto;
  final double alto;
  final bool marcas;

  static const _desde = 5 * 60;
  static const _hasta = 23 * 60;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int min) => (min.clamp(_desde, _hasta) - _desde) / (_hasta - _desde) * size.width;
    final pistaRect = RRect.fromRectAndRadius(Rect.fromLTWH(0, alto / 2 - 3, size.width, 6), const Radius.circular(3));
    canvas.drawRRect(pistaRect, Paint()..color = pista);

    for (final b in bloques) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(x(b.inicio), 2, x(b.fin), alto - 2),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        r,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.22));
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color,
      );
    }

    if (marcas) {
      for (final h in [6, 9, 12, 15, 18, 21]) {
        final px = x(h * 60);
        canvas.drawLine(Offset(px, alto), Offset(px, alto + 3), Paint()..color = texto..strokeWidth = 1);
        final tp = TextPainter(
          text: TextSpan(text: '$h', style: Hud.mono(tam: 9.5, color: texto, espaciado: 0)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(px - tp.width / 2, alto + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_PintorBarra v) => v.bloques != bloques || v.color != color || v.pista != pista;
}

/// Selector de días (L M X J V S D) como chips accesibles.
class SelectorDias extends StatelessWidget {
  const SelectorDias({super.key, required this.mascara, required this.alCambiar});
  final int mascara;
  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Espacio.xs,
      runSpacing: Espacio.xs,
      children: [
        for (var i = 0; i < 7; i++)
          Semantics(
            label: DiasSemana.nombres[i],
            child: FilterChip(
              label: Text(DiasSemana.letras[i]),
              selected: DiasSemana.incluye(mascara, i),
              showCheckmark: false,
              onSelected: (v) => alCambiar(v ? mascara | (1 << i) : mascara & ~(1 << i)),
            ),
          ),
      ],
    );
  }
}

/// Resumen de un turno en una línea: "Turno A · 08:30–12:00 · 14:00–18:00".
class EtiquetaTurno extends StatelessWidget {
  const EtiquetaTurno({super.key, required this.nombre, required this.bloques, required this.color, this.estilo});
  final String nombre;
  final String bloques;
  final Color color;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$nombre · ${Formato.bloques(bloques)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: estilo ?? context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
          ),
        ),
      ],
    );
  }
}
