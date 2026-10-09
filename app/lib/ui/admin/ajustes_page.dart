import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../servicios/ajustes.dart';
import '../comun/widgets.dart';
import 'componentes_kiosco.dart';
import 'contexto_admin.dart';
import 'kioscos_page.dart';
import 'usuarios_page.dart';

/// Pestaña "Ajustes" del administrativo: kiosco, reconocimiento, cuentas y kioscos.
class AjustesPage extends StatelessWidget {
  const AjustesPage({super.key});

  @override
  Widget build(BuildContext context) {
    void abrir(Widget pagina) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(value: context.read<ContextoAdmin>(), child: pagina),
        ));
    return FondoTecnico(
      intensidad: 0.6,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.xxl),
        children: [
          Seccion(
            titulo: 'Administración',
            hijos: [
              _Enlace(
                icono: Icons.manage_accounts_outlined,
                titulo: 'Usuarios',
                detalle: 'Cuentas General (kioscos) y Administrativas',
                alTocar: () => abrir(const UsuariosPage()),
              ),
              const Divider(),
              _Enlace(
                icono: Icons.devices_other_rounded,
                titulo: 'Kioscos vinculados',
                detalle: 'Teléfonos y tablets de todas las sedes',
                alTocar: () => abrir(const KioscosPage()),
              ),
            ],
          ),
          const SizedBox(height: Espacio.md),
          const TarjetaEsteKiosco(),
          const SizedBox(height: Espacio.md),
          const TarjetaSincronizacion(permitirReprocesar: true),
          const SizedBox(height: Espacio.md),
          const _AjustesReconocimiento(),
          const SizedBox(height: Espacio.md),
          const _AjustesApariencia(),
          const SizedBox(height: Espacio.md),
          const TarjetaDesvincular(),
        ],
      ),
    );
  }
}

class _Enlace extends StatelessWidget {
  const _Enlace({required this.icono, required this.titulo, required this.detalle, required this.alTocar});
  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.colores.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Redondeo.md),
        ),
        child: Icon(icono, color: context.colores.primary),
      ),
      title: Text(titulo),
      subtitle: Text(detalle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: alTocar,
    );
  }
}

class _AjustesReconocimiento extends StatelessWidget {
  const _AjustesReconocimiento();

  @override
  Widget build(BuildContext context) {
    final a = context.watch<Ajustes>();
    final nivel = switch (a.umbral) {
      < 0.58 => 'Flexible',
      < 0.68 => 'Equilibrado',
      < 0.76 => 'Estricto',
      _ => 'Muy estricto',
    };
    return Seccion(
      titulo: 'Reconocimiento',
      hijos: [
        Row(
          children: [
            Expanded(child: Text('Exigencia de coincidencia', style: context.textos.titleMedium)),
            Pildora(texto: '$nivel · ${(a.umbral * 100).round()}%', color: context.colores.primary),
          ],
        ),
        Slider(
          value: a.umbral,
          min: 0.50,
          max: 0.85,
          divisions: 35,
          label: '${(a.umbral * 100).round()}%',
          onChanged: a.cambiarUmbral,
        ),
        Text(
          'Más estricto evita confusiones entre personas parecidas; más flexible reconoce mejor con poca luz o cambios de aspecto.',
          style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
        ),
        const Divider(height: Espacio.xl),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: a.pruebaDeVida,
          onChanged: a.cambiarPruebaDeVida,
          title: const Text('Prueba de vida (parpadeo)'),
          subtitle: const Text('Evita marcar con una foto o un video de otra persona.'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: a.sonido,
          onChanged: a.cambiarSonido,
          title: const Text('Sonido al registrar'),
        ),
        const Divider(height: Espacio.xl),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Espera entre marcaciones', style: context.textos.titleMedium),
                  Text(
                    'Evita registros dobles de la misma persona.',
                    style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
                  ),
                ],
              ),
            ),
            IconButton.outlined(
              tooltip: 'Menos minutos',
              onPressed: a.minutosEspera > 1 ? () => a.cambiarMinutosEspera(a.minutosEspera - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 56,
              child: Text('${a.minutosEspera} min', textAlign: TextAlign.center, style: context.textos.titleMedium),
            ),
            IconButton.outlined(
              tooltip: 'Más minutos',
              onPressed: a.minutosEspera < 30 ? () => a.cambiarMinutosEspera(a.minutosEspera + 1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _AjustesApariencia extends StatelessWidget {
  const _AjustesApariencia();

  @override
  Widget build(BuildContext context) {
    final a = context.watch<Ajustes>();
    return Seccion(
      titulo: 'Apariencia del panel',
      hijos: [
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Oscuro')),
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
          ],
          selected: {a.tema},
          onSelectionChanged: (s) => a.cambiarTema(s.first),
        ),
        const SizedBox(height: Espacio.xs),
        Text(
          'El kiosco siempre usa el modo oscuro para que la cámara sea protagonista.',
          style: context.textos.bodySmall?.copyWith(color: context.sem.textoSuave),
        ),
      ],
    );
  }
}
