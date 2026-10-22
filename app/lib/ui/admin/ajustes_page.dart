import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../servicios/ajustes.dart';
import '../../servicios/estado_app.dart';
import '../comun/vincular_telefono.dart';
import '../comun/widgets.dart';
import '../cuenta/mi_empresa_page.dart';
import 'componentes_kiosco.dart';
import 'contexto_admin.dart';
import 'kioscos_page.dart';
import 'sedes_page.dart';
import 'usuarios_page.dart';

/// Pestaña "Ajustes" del administrativo: empresa, sedes, equipo, kioscos y
/// los ajustes de este kiosco.
class AjustesPage extends StatelessWidget {
  const AjustesPage({super.key});

  @override
  Widget build(BuildContext context) {
    void abrir(Widget pagina) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(value: context.read<ContextoAdmin>(), child: pagina),
        ));
    // Sedes y equipo los gestiona solo el administrador de la empresa; el
    // gerente y talento humano ven su empresa y los teléfonos de marcación.
    final estado = context.read<EstadoApp>();
    final esAdmin = estado.sesion.sesion?.esAdminEmpresa ?? false;
    final vinculado = estado.configurado;
    return FondoTecnico(
      intensidad: 0.6,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.xxl),
        children: [
          Seccion(
            titulo: 'Administración',
            hijos: [
              _Enlace(
                icono: Icons.business_outlined,
                titulo: 'Mi empresa',
                detalle: esAdmin ? 'Planes de Presente y Ventario, uso y datos' : 'Datos de la empresa y tu cuenta',
                alTocar: () => abrir(const MiEmpresaPage()),
              ),
              if (esAdmin) ...[
                const Divider(),
                _Enlace(
                  icono: Icons.place_outlined,
                  titulo: 'Sedes',
                  detalle: 'Compartidas con Ventario; elige cuáles usa Presente',
                  alTocar: () => abrir(const SedesPage()),
                ),
                const Divider(),
                _Enlace(
                  icono: Icons.manage_accounts_outlined,
                  titulo: 'Cuentas de Presente',
                  detalle: 'Quién entra a Presente y con qué rol',
                  alTocar: () => abrir(const UsuariosPage()),
                ),
              ],
              const Divider(),
              _Enlace(
                icono: Icons.devices_other_rounded,
                titulo: 'Teléfonos de marcación',
                detalle: 'Por sede, con su código; renombrar o desvincular',
                alTocar: () => abrir(const KioscosPage()),
              ),
            ],
          ),
          const SizedBox(height: Espacio.md),
          if (vinculado) ...[
            const TarjetaEsteKiosco(),
            const SizedBox(height: Espacio.md),
            const TarjetaSincronizacion(permitirReprocesar: true),
            const SizedBox(height: Espacio.md),
            const _AjustesReconocimiento(),
          ] else
            const _UsarEsteTelefono(),
          const SizedBox(height: Espacio.md),
          const _AjustesApariencia(),
          if (vinculado) ...[
            const SizedBox(height: Espacio.md),
            const TarjetaDesvincular(),
          ],
        ],
      ),
    );
  }
}

/// En un teléfono sin vincular: dejarlo como punto de marcación de una sede.
class _UsarEsteTelefono extends StatefulWidget {
  const _UsarEsteTelefono();

  @override
  State<_UsarEsteTelefono> createState() => _UsarEsteTelefonoState();
}

class _UsarEsteTelefonoState extends State<_UsarEsteTelefono> {
  bool _cargando = false;

  Future<void> _vincular() async {
    setState(() => _cargando = true);
    try {
      final registro = await vincularEsteTelefono(context, context.read<EstadoApp>());
      if (registro == null || !mounted) return;
      avisar(context, 'Listo: este teléfono marca asistencia en ${registro.sede.nombre}');
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Seccion(
      titulo: 'Este teléfono',
      hijos: [
        Text(
          'Úsalo como punto de marcación de una sede: el personal marcará aquí con su rostro. '
          'Normalmente se hace con la cuenta Operario, pero también puedes hacerlo tú.',
          style: context.textos.bodyMedium?.copyWith(color: context.sem.textoSuave),
        ),
        const SizedBox(height: Espacio.md),
        FilledButton.tonalIcon(
          onPressed: _cargando ? null : _vincular,
          icon: _cargando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.phonelink_ring_outlined),
          label: const Text('Usar este teléfono para marcar asistencia'),
        ),
      ],
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
