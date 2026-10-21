import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../servicios/asistencia.dart';
import '../../servicios/estado_app.dart';
import '../../servicios/sincronizador.dart';
import '../admin/acceso_admin.dart';
import '../comun/widgets.dart';
import '../cuenta/iniciar_sesion_page.dart';
import '../cuenta/registro_empresa_page.dart';
import '../kiosco/kiosco_page.dart';

/// Pantalla inicial de Presente. Dos botones: «Marcar asistencia» e
/// «Iniciar sesión / Crear cuenta».
///
/// Presente es pública en la tienda: cualquiera la instala, pero solo se marca
/// en un teléfono que la empresa vinculó a una sede con su cuenta Operario.
/// La cámara se enciende solo al tocar «Marcar asistencia».
class InicioPage extends StatelessWidget {
  const InicioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    return Theme(
      data: construirTema(Brightness.dark),
      child: estado.configurado
          ? ChangeNotifierProvider.value(
              // La clave fuerza una vista nueva si el teléfono se vuelve a vincular.
              key: ObjectKey(estado.sincronizador),
              value: estado.sincronizador!,
              child: const _InicioVinculado(),
            )
          : VistaInicioSinVincular(
              aviso: estado.avisoDesvinculado,
              alIniciarSesion: () => _iniciarSesion(context),
              alCrearCuenta: () => _crearCuenta(context),
            ),
    );
  }
}

/// Inicia sesión y, si la cuenta administra, abre el panel.
Future<void> _iniciarSesion(BuildContext context) async {
  final alPanel = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
  );
  if (alPanel == true && context.mounted) await abrirPanel(context);
}

Future<void> _crearCuenta(BuildContext context) async {
  final estado = context.read<EstadoApp>();
  final sesion = await Navigator.of(context).push<SesionAdmin>(
    MaterialPageRoute(builder: (_) => RegistroEmpresaPage(api: estado.api)),
  );
  if (sesion == null || !context.mounted) return;
  estado.sesion.adoptar(sesion);
  avisar(context, '¡${sesion.empresa?.nombre ?? 'Tu empresa'} quedó creada!');
  await abrirPanel(context);
}

// ---------------------------------------------------------------------------
// Teléfono sin vincular
// ---------------------------------------------------------------------------

class VistaInicioSinVincular extends StatelessWidget {
  const VistaInicioSinVincular({
    super.key,
    required this.alIniciarSesion,
    required this.alCrearCuenta,
    this.aviso,
  });

  final VoidCallback alIniciarSesion;
  final VoidCallback alCrearCuenta;

  /// Por qué el teléfono dejó de marcar (lo desvincularon), si aplica.
  final String? aviso;

  @override
  Widget build(BuildContext context) {
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
                    const LogoPresente(),
                    const SizedBox(height: Espacio.lg),
                    Text('Presente', style: Hud.titulo(tam: 44)),
                    const SizedBox(height: Espacio.xs),
                    Text(
                      'Entradas y salidas de tu equipo con reconocimiento facial, incluso sin internet.',
                      style: context.textos.bodyLarge?.copyWith(color: Hud.textoSuave),
                    ),
                    if (aviso != null) ...[
                      const SizedBox(height: Espacio.md),
                      MensajeError(aviso!),
                    ],
                    const SizedBox(height: Espacio.xl),
                    const BotonMarcar(alTocar: null),
                    const SizedBox(height: Espacio.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 18, color: Hud.textoSuave),
                        const SizedBox(width: Espacio.xs),
                        Expanded(
                          child: Text(
                            'Este teléfono aún no es un punto de marcación: inicia sesión con la cuenta '
                            'Operario de tu empresa.',
                            style: context.textos.bodyMedium?.copyWith(color: Hud.textoSuave),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Espacio.xl),
                    FilledButton.icon(
                      onPressed: alIniciarSesion,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Iniciar sesión'),
                    ),
                    const SizedBox(height: Espacio.sm),
                    OutlinedButton.icon(
                      onPressed: alCrearCuenta,
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Crear cuenta de empresa gratis'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teléfono de marcación
// ---------------------------------------------------------------------------

/// Última marca de hoy de una persona.
typedef MarcaDeHoy = ({String nombre, Marcacion marcacion});

/// Deja solo la marca más reciente de cada persona, de la más nueva a la más vieja.
List<MarcaDeHoy> ultimaMarcaPorPersona(Iterable<MarcaDeHoy> marcas) {
  final porPersona = <int, MarcaDeHoy>{};
  for (final m in marcas) {
    final previa = porPersona[m.marcacion.empleadoId];
    if (previa == null || m.marcacion.hora.isAfter(previa.marcacion.hora)) porPersona[m.marcacion.empleadoId] = m;
  }
  return porPersona.values.toList()..sort((a, b) => b.marcacion.hora.compareTo(a.marcacion.hora));
}

class _InicioVinculado extends StatefulWidget {
  const _InicioVinculado();

  @override
  State<_InicioVinculado> createState() => _InicioVinculadoState();
}

class _InicioVinculadoState extends State<_InicioVinculado> with WidgetsBindingObserver {
  late final EstadoApp _estado = context.read<EstadoApp>();
  late final Sincronizador _sync = context.read<Sincronizador>();
  late Future<List<MarcaDeHoy>> _marcas = _cargarMarcas();
  late final Timer _medianoche;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Queda a la vista en recepción: la pantalla no se apaga.
    WakelockPlus.enable();
    _sync.addListener(_refrescar);
    // Al cambiar el día, la lista empieza de cero.
    _medianoche = Timer.periodic(const Duration(minutes: 1), (_) => _refrescar());
  }

  @override
  void dispose() {
    _medianoche.cancel();
    _sync.removeListener(_refrescar);
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _sync.sincronizar();
  }

  Future<List<MarcaDeHoy>> _cargarMarcas() async =>
      ultimaMarcaPorPersona(await _estado.almacen.marcacionesDesde(Asistencia.inicioDelDia()));

  void _refrescar() {
    if (mounted) setState(() => _marcas = _cargarMarcas());
  }

  Future<void> _marcar() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: _sync, child: const KioscoPage()),
      ),
    );
    _refrescar();
  }

  Future<void> _administrar() async {
    if (_estado.sesion.activa) {
      await abrirPanel(context);
    } else {
      await _iniciarSesion(context);
    }
    _refrescar();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<Sincronizador>();
    final config = _estado.config!;
    return FutureBuilder<List<MarcaDeHoy>>(
      future: _marcas,
      builder: (context, snap) => VistaInicioVinculado(
        sede: config.sede.nombre,
        telefono: config.nombre,
        codigo: config.codigo,
        marcas: snap.data ?? const [],
        estadoSync: EstadoSync(sync: sync),
        aviso: sync.relojDesfasado ? AvisoReloj(desfase: sync.desfaseReloj!) : null,
        puedeMarcar: _estado.motor != null,
        alMarcar: _marcar,
        alAdministrar: _administrar,
      ),
    );
  }
}

/// Teléfono vinculado: sede, reloj, el botón grande y quién marcó hoy. No hay
/// cerrar sesión ni opciones de cuenta: solo «Administrar», que pide la
/// cuenta de un administrador, gerente o talento humano.
class VistaInicioVinculado extends StatelessWidget {
  const VistaInicioVinculado({
    super.key,
    required this.sede,
    required this.telefono,
    required this.marcas,
    required this.estadoSync,
    required this.alMarcar,
    required this.alAdministrar,
    this.codigo,
    this.aviso,
    this.puedeMarcar = true,
    this.reloj = const RelojVivo(),
  });

  final String sede;
  final String telefono;
  final String? codigo;
  final List<MarcaDeHoy> marcas;
  final Widget estadoSync;
  final Widget? aviso;
  final bool puedeMarcar;
  final VoidCallback alMarcar;
  final VoidCallback alAdministrar;
  final Widget reloj;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Hud.fondo,
        body: FondoTecnico(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(Espacio.lg, Espacio.md, Espacio.lg, 0),
                      sliver: SliverList.list(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SEDE · ${sede.toUpperCase()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Hud.mono(tam: 12, color: Hud.cian, peso: FontWeight.w700, espaciado: 2),
                                    ),
                                    const SizedBox(height: Espacio.xxs),
                                    reloj,
                                  ],
                                ),
                              ),
                              estadoSync,
                            ],
                          ),
                          if (aviso != null) ...[const SizedBox(height: Espacio.sm), aviso!],
                          const SizedBox(height: Espacio.lg),
                          BotonMarcar(alTocar: puedeMarcar ? alMarcar : null),
                          if (!puedeMarcar) ...[
                            const SizedBox(height: Espacio.xs),
                            Text(
                              'Falta el modelo de reconocimiento en esta instalación.',
                              style: Hud.cuerpo(tam: 13, color: Hud.alerta, peso: FontWeight.w500),
                            ),
                          ],
                          const SizedBox(height: Espacio.xl),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'MARCARON HOY EN ${sede.toUpperCase()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Hud.mono(tam: 12, color: Hud.textoSuave, peso: FontWeight.w700, espaciado: 1.6),
                                ),
                              ),
                              Text('${marcas.length}', style: Hud.mono(tam: 14, color: Hud.cian, peso: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: Espacio.xs),
                        ],
                      ),
                    ),
                    if (marcas.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: Espacio.lg, vertical: Espacio.md),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            'Aún nadie ha marcado hoy en esta sede.',
                            style: Hud.cuerpo(tam: 15, color: Hud.textoSuave, peso: FontWeight.w500),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: Espacio.lg),
                        sliver: SliverList.separated(
                          itemCount: marcas.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, color: Hud.linea),
                          itemBuilder: (_, i) => _FilaMarca(marca: marcas[i]),
                        ),
                      ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Espacio.lg, Espacio.xl, Espacio.sm, Espacio.sm),
                          child: Row(
                            children: [
                              const Icon(Icons.phone_android_rounded, size: 16, color: Hud.textoSuave),
                              const SizedBox(width: Espacio.xxs),
                              Expanded(
                                child: Text(
                                  [telefono, if (codigo != null && codigo!.isNotEmpty) codigo!].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Hud.mono(tam: 11, color: Hud.textoSuave, espaciado: 0.8),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: alAdministrar,
                                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                                label: const Text('Administrar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilaMarca extends StatelessWidget {
  const _FilaMarca({required this.marca});
  final MarcaDeHoy marca;

  @override
  Widget build(BuildContext context) {
    final m = marca.marcacion;
    final entrada = m.tipo == TipoMarcacion.entrada;
    final color = entrada ? Hud.entrada : Hud.salida;
    return Semantics(
      label: '${marca.nombre}: ${m.tipo.etiqueta.toLowerCase()} a las ${Formato.hora(m.hora)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Espacio.sm),
        child: Row(
          children: [
            AvatarEmpleado(nombre: marca.nombre, tam: 40, anillo: color),
            const SizedBox(width: Espacio.sm),
            Expanded(
              child: Text(
                marca.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Hud.cuerpo(tam: 16, peso: FontWeight.w600),
              ),
            ),
            const SizedBox(width: Espacio.xs),
            Pildora(
              texto: m.tipo.etiqueta,
              color: color,
              fondo: color.withValues(alpha: 0.12),
              icono: entrada ? Icons.login_rounded : Icons.logout_rounded,
            ),
            const SizedBox(width: Espacio.sm),
            Text(
              Formato.hora(m.hora),
              style: Hud.mono(tam: 14, color: Hud.texto, peso: FontWeight.w700, espaciado: 0),
            ),
            if (!m.enviada) ...[
              const SizedBox(width: Espacio.xxs),
              const Icon(Icons.cloud_upload_outlined, size: 16, color: Hud.alerta, semanticLabel: 'Pendiente por enviar'),
            ],
          ],
        ),
      ),
    );
  }
}

/// El botón protagonista. Sin [alTocar] se ve bloqueado (teléfono sin vincular).
class BotonMarcar extends StatelessWidget {
  const BotonMarcar({super.key, required this.alTocar});
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final activo = alTocar != null;
    final borde = BorderRadius.circular(Redondeo.xl);
    return Semantics(
      button: true,
      enabled: activo,
      label: activo ? 'Marcar asistencia' : 'Marcar asistencia, no disponible en este teléfono',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borde,
          boxShadow: activo ? [BoxShadow(color: Hud.cian.withValues(alpha: 0.35), blurRadius: 32, spreadRadius: -4)] : null,
        ),
        child: Material(
          borderRadius: borde,
          clipBehavior: Clip.antiAlias,
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: borde,
              gradient: activo
                  ? const LinearGradient(colors: [Hud.cian, Hud.azul], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              color: activo ? null : Hud.panel,
              border: activo ? null : Border.all(color: Hud.textoSuave.withValues(alpha: 0.35)),
            ),
            child: InkWell(
              onTap: alTocar,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.lg, vertical: Espacio.lg),
                child: Row(
                  children: [
                    Icon(
                      activo ? Icons.face_retouching_natural_rounded : Icons.lock_outline_rounded,
                      size: 44,
                      color: activo ? Hud.fondo : Hud.textoSuave,
                    ),
                    const SizedBox(width: Espacio.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Marcar asistencia',
                            style: Hud.titulo(tam: 26, color: activo ? Hud.fondo : Hud.textoSuave),
                          ),
                          const SizedBox(height: Espacio.xxs),
                          Text(
                            activo ? 'Mira a la cámara: entrada o salida se detecta sola' : 'Disponible en los teléfonos de tu empresa',
                            style: Hud.cuerpo(
                              tam: 14,
                              color: activo ? Hud.fondo.withValues(alpha: 0.8) : Hud.textoSuave,
                              peso: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (activo) const Icon(Icons.arrow_forward_rounded, color: Hud.fondo),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LogoPresente extends StatelessWidget {
  const LogoPresente({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Redondeo.lg),
          gradient: const LinearGradient(colors: [Hud.cian, Hud.azul], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: Hud.cian.withValues(alpha: 0.45), blurRadius: 24)],
        ),
        child: const Icon(Icons.face_unlock_outlined, size: 34, color: Colors.white, semanticLabel: 'Presente'),
      ),
    );
  }
}
