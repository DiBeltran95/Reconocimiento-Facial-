import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import 'componentes_kiosco.dart' show Aviso, Dato, Seccion;
import 'contexto_admin.dart';

/// Solicitudes de los empleados (permisos, incapacidades, citas médicas…) que
/// llegan por WhatsApp. El administrador, talento humano o el gerente (sus
/// sedes) las aprueban o rechazan; al empleado se le avisa por WhatsApp.
class NovedadesPage extends StatefulWidget {
  const NovedadesPage({super.key, this.alCambiarPendientes, this.visitas = 0});

  /// Cuántas esperan respuesta (para el globo de la barra inferior).
  final ValueChanged<int>? alCambiarPendientes;

  /// Sube cada vez que se abre la pestaña: la lista se vuelve a pedir.
  final int visitas;

  @override
  State<NovedadesPage> createState() => _NovedadesPageState();
}

class _NovedadesPageState extends State<NovedadesPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  bool _pendientes = true;
  BandejaNovedades? _bandeja;
  int _totalPendientes = 0;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(NovedadesPage anterior) {
    super.didUpdateWidget(anterior);
    if (widget.visitas != anterior.visitas) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final pendientes = _pendientes;
    try {
      final b = await _ctx.api.novedades(pendientes: pendientes);
      if (!mounted || pendientes != _pendientes) return;
      setState(() {
        _bandeja = b;
        _totalPendientes = b.pendientes;
        _error = null;
      });
      widget.alCambiarPendientes?.call(b.pendientes);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _verLista(bool pendientes) {
    if (pendientes == _pendientes) return;
    setState(() {
      _pendientes = pendientes;
      _bandeja = null;
    });
    _cargar();
  }

  Future<void> _abrir(Novedad n) async {
    final resultado = await showModalBottomSheet<({Novedad novedad, bool avisado})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HojaNovedad(novedad: n, api: _ctx.api, veSoportes: _bandeja?.veSoportes ?? false),
    );
    if (resultado == null || !mounted) return;
    final r = resultado.novedad;
    final nombre = Formato.primerNombre(r.empleado);
    final hecho = r.estado == EstadoNovedad.aprobada ? 'aprobada' : 'rechazada';
    avisar(
      context,
      resultado.avisado
          ? 'Solicitud $hecho. Se le avisó a $nombre por WhatsApp.'
          : 'Solicitud $hecho, pero no se pudo avisar a $nombre por WhatsApp.',
      error: !resultado.avisado,
    );
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _bandeja?.novedades ?? const <Novedad>[];
    final variasSedes = _ctx.sedes.length > 1;
    return FondoTecnico(
      intensidad: 0.6,
      child: RefreshIndicator(
        onRefresh: _cargar,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.sm),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.inbox_outlined),
                      label: Text(_totalPendientes > 0 ? 'Por responder ($_totalPendientes)' : 'Por responder'),
                    ),
                    const ButtonSegment(value: false, icon: Icon(Icons.history_rounded), label: Text('Resueltas')),
                  ],
                  selected: {_pendientes},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _verLista(s.first),
                ),
              ),
            ),
            if (_cargando && _bandeja == null)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _bandeja == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudo cargar', mensaje: _error, accion: _cargar),
              )
            else if (lista.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EstadoVacio(
                  icono: _pendientes ? Icons.mark_email_read_outlined : Icons.history_rounded,
                  titulo: _pendientes ? 'Todo al día' : 'Aún no hay solicitudes resueltas',
                  mensaje: _pendientes
                      ? 'Los empleados piden permisos, incapacidades y vacaciones por WhatsApp. '
                          'Aquí aparecerán para que las apruebes o rechaces.'
                      : 'Las solicitudes que apruebes o rechaces quedarán aquí.',
                  color: _pendientes ? context.sem.entrada : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Espacio.md, 0, Espacio.md, Espacio.xxl),
                sliver: SliverList.separated(
                  itemCount: lista.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Espacio.xs),
                  itemBuilder: (_, i) => TarjetaNovedad(
                    novedad: lista[i],
                    mostrarSede: variasSedes,
                    alTocar: () => _abrir(lista[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Presentación
// ---------------------------------------------------------------------------

IconData iconoNovedad(TipoNovedad t) => switch (t) {
      TipoNovedad.permiso => Icons.event_busy_outlined,
      TipoNovedad.incapacidad => Icons.medical_services_outlined,
      TipoNovedad.citaMedica => Icons.local_hospital_outlined,
      TipoNovedad.calamidad => Icons.crisis_alert_outlined,
      TipoNovedad.vacaciones => Icons.beach_access_outlined,
      TipoNovedad.licencia => Icons.family_restroom_outlined,
      TipoNovedad.otro => Icons.description_outlined,
    };

Color colorEstadoNovedad(BuildContext context, EstadoNovedad e) => switch (e) {
      EstadoNovedad.pendiente => context.sem.alerta,
      EstadoNovedad.aprobada => context.sem.entrada,
      EstadoNovedad.rechazada => context.sem.peligro,
      EstadoNovedad.anulada => context.sem.textoSuave,
    };

final _dia = DateFormat("EEE d 'de' MMM", 'es_CO');
final _diaAnio = DateFormat("EEE d 'de' MMM y", 'es_CO');

String _fecha(DateTime f) {
  final texto = (f.year == DateTime.now().year ? _dia : _diaAnio).format(f).replaceAll('.', '');
  return texto[0].toUpperCase() + texto.substring(1);
}

String _hora(String hhmm) {
  final p = hhmm.split(':');
  return Formato.hora(DateTime(2000, 1, 1, int.parse(p[0]), int.parse(p[1])));
}

/// «Lun 3 de nov · 8:00 a. m. – 12:00 p. m.», «Lun 3 de nov» o «Lun 3 – Mié 5 de nov».
String periodoNovedad(Novedad n) {
  if (n.porHoras) return '${_fecha(n.desde)} · ${_hora(n.horaDesde!)} – ${_hora(n.horaHasta!)}';
  if (n.dias == 1) return _fecha(n.desde);
  return '${_fecha(n.desde)} – ${_fecha(n.hasta)}';
}

/// «4 h 30 min» o «3 días».
String duracionNovedad(Novedad n) {
  if (n.porHoras) {
    int minutos(String h) => int.parse(h.split(':')[0]) * 60 + int.parse(h.split(':')[1]);
    return Formato.duracion(minutos(n.horaHasta!) - minutos(n.horaDesde!));
  }
  return n.dias == 1 ? '1 día' : '${n.dias} días';
}

class TarjetaNovedad extends StatelessWidget {
  const TarjetaNovedad({super.key, required this.novedad, required this.alTocar, this.mostrarSede = false});
  final Novedad novedad;
  final VoidCallback alTocar;
  final bool mostrarSede;

  @override
  Widget build(BuildContext context) {
    final n = novedad;
    final sem = context.sem;
    final colorEstado = colorEstadoNovedad(context, n.estado);
    return Card(
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(Redondeo.lg),
        child: Padding(
          padding: const EdgeInsets.all(Espacio.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarEmpleado(nombre: n.empleado, tam: 44),
              const SizedBox(width: Espacio.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(n.empleado, style: context.textos.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: Espacio.xs),
                        if (n.pendiente)
                          Text(
                            Formato.haceCuanto(n.creada),
                            style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                          )
                        else
                          Pildora(texto: n.estado.etiqueta, color: colorEstado),
                      ],
                    ),
                    if (mostrarSede || (n.cargo ?? '').isNotEmpty)
                      Text(
                        [if ((n.cargo ?? '').isNotEmpty) n.cargo!, if (mostrarSede) n.sede].join(' · '),
                        style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: Espacio.xs),
                    Wrap(
                      spacing: Espacio.xs,
                      runSpacing: Espacio.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Pildora(texto: n.tipo.etiqueta, color: context.colores.primary, icono: iconoNovedad(n.tipo)),
                        if (n.soportes > 0)
                          Pildora(
                            texto: n.soportes == 1 ? 'Soporte' : '${n.soportes} soportes',
                            color: sem.textoSuave,
                            icono: Icons.attach_file_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: Espacio.xs),
                    Row(
                      children: [
                        Icon(Icons.event_outlined, size: 16, color: sem.textoSuave),
                        const SizedBox(width: Espacio.xxs),
                        Expanded(
                          child: Text(
                            '${periodoNovedad(n)} · ${duracionNovedad(n)}',
                            style: context.textos.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if ((n.motivo ?? '').isNotEmpty) ...[
                      const SizedBox(height: Espacio.xxs),
                      Text(
                        n.motivo!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detalle: ver y resolver
// ---------------------------------------------------------------------------

class HojaNovedad extends StatefulWidget {
  const HojaNovedad({super.key, required this.novedad, required this.api, required this.veSoportes});
  final Novedad novedad;
  final Api api;
  final bool veSoportes;

  @override
  State<HojaNovedad> createState() => _HojaNovedadState();
}

class _HojaNovedadState extends State<HojaNovedad> {
  final _comentario = TextEditingController();
  late final Future<List<SoporteNovedad>>? _soportes =
      widget.veSoportes && widget.novedad.soportes > 0 ? widget.api.soportesNovedad(widget.novedad.id) : null;
  bool? _enviando; // true = aprobando, false = rechazando
  String? _errorComentario;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _resolver({required bool aprobar}) async {
    if (_enviando != null) return;
    final comentario = _comentario.text.trim();
    if (!aprobar && comentario.length < 3) {
      setState(() => _errorComentario = 'Escribe el motivo del rechazo: se le enviará al empleado');
      return;
    }
    setState(() => _errorComentario = null);
    final n = widget.novedad;
    final nombre = Formato.primerNombre(n.empleado);
    // Ninguna de las dos se puede deshacer: se confirma con lo que recibirá.
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(
          aprobar ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
          color: aprobar ? c.sem.entrada : c.sem.peligro,
        ),
        title: Text(aprobar ? '¿Aprobar la solicitud?' : '¿Rechazar la solicitud?'),
        content: Text(
          '${n.tipo.etiqueta} de ${n.empleado}: ${periodoNovedad(n)}.\n\n'
          'Se le avisará a $nombre por WhatsApp. No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: aprobar ? null : FilledButton.styleFrom(backgroundColor: c.sem.peligro, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _enviando = aprobar);
    try {
      final r = await widget.api.resolverNovedad(n.id, aprobar: aprobar, comentario: comentario.isEmpty ? null : comentario);
      if (mounted) Navigator.of(context).pop(r);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _enviando = null);
      if (e.campo == 'comentario') {
        setState(() => _errorComentario = e.mensaje);
      } else {
        avisar(context, e.mensaje, error: true);
        // Otra persona ya la resolvió: no hay nada más que hacer aquí.
        if (e.codigo == 'YA_RESUELTA') Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.novedad;
    final sem = context.sem;
    final ocupado = _enviando != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Espacio.lg, 0, Espacio.lg, Espacio.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Etiqueta('Solicitud #${n.id} · ${n.canal == 'WHATSAPP' ? 'WhatsApp' : n.canal.toLowerCase()}'),
            const SizedBox(height: Espacio.xs),
            Row(
              children: [
                AvatarEmpleado(nombre: n.empleado, tam: 52),
                const SizedBox(width: Espacio.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.empleado, style: context.textos.titleLarge),
                      Text(
                        [if (n.documento.isNotEmpty) 'CC ${n.documento}', if ((n.cargo ?? '').isNotEmpty) n.cargo!, n.sede]
                            .join(' · '),
                        style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espacio.md),
            Seccion(
              titulo: n.tipo.etiqueta,
              colorTitulo: context.colores.primary,
              hijos: [
                Dato(icono: iconoNovedad(n.tipo), etiqueta: 'Estado', valor: n.estado.etiqueta),
                Dato(icono: Icons.event_outlined, etiqueta: n.porHoras ? 'Horario' : 'Fechas', valor: periodoNovedad(n)),
                Dato(icono: Icons.timelapse_rounded, etiqueta: 'Duración', valor: duracionNovedad(n)),
                if (n.creada != null)
                  Dato(
                    icono: Icons.schedule_send_outlined,
                    etiqueta: 'Recibida',
                    valor: '${Formato.fechaCorta(n.creada!)}, ${Formato.hora(n.creada!)}',
                  ),
                if ((n.motivo ?? '').isNotEmpty) ...[
                  const Divider(height: Espacio.lg),
                  Text('Motivo', style: context.textos.labelLarge?.copyWith(color: sem.textoSuave)),
                  const SizedBox(height: Espacio.xxs),
                  SelectableText(n.motivo!, style: context.textos.bodyLarge),
                ],
              ],
            ),
            if (n.soportes > 0) ...[
              const SizedBox(height: Espacio.md),
              _soportes == null
                  ? Aviso(
                      icono: Icons.lock_outline_rounded,
                      texto: n.soportes == 1
                          ? 'Trae un soporte. Es un dato de salud: solo lo ven el administrador y talento humano.'
                          : 'Trae ${n.soportes} soportes. Son datos de salud: solo los ven el administrador y talento humano.',
                    )
                  : _ListaSoportes(api: widget.api, novedadId: n.id, soportes: _soportes),
            ],
            if (!n.pendiente) ...[
              const SizedBox(height: Espacio.md),
              _Resolucion(novedad: n),
            ] else ...[
              const SizedBox(height: Espacio.lg),
              TextField(
                controller: _comentario,
                enabled: !ocupado,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  if (_errorComentario != null) setState(() => _errorComentario = null);
                },
                decoration: InputDecoration(
                  labelText: 'Mensaje para ${Formato.primerNombre(n.empleado)}',
                  helperText: 'Opcional al aprobar. Obligatorio al rechazar.',
                  errorText: _errorComentario,
                  errorMaxLines: 2,
                  prefixIcon: const Icon(Icons.chat_outlined),
                ),
              ),
              const SizedBox(height: Espacio.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ocupado ? null : () => _resolver(aprobar: false),
                      icon: _enviando == false ? const _Girando() : const Icon(Icons.close_rounded),
                      label: const Text('Rechazar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: sem.peligro,
                        side: BorderSide(color: sem.peligro.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: Espacio.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: ocupado ? null : () => _resolver(aprobar: true),
                      icon: _enviando == true ? const _Girando() : const Icon(Icons.check_rounded),
                      label: const Text('Aprobar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Espacio.xs),
              Text(
                'Al responder, el empleado recibe el resultado por WhatsApp.',
                textAlign: TextAlign.center,
                style: context.textos.bodySmall?.copyWith(color: sem.textoSuave),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Girando extends StatelessWidget {
  const _Girando();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5));
}

class _Resolucion extends StatelessWidget {
  const _Resolucion({required this.novedad});
  final Novedad novedad;

  @override
  Widget build(BuildContext context) {
    final n = novedad;
    final color = colorEstadoNovedad(context, n.estado);
    return Container(
      padding: const EdgeInsets.all(Espacio.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Redondeo.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pildora(texto: n.estado.etiqueta, color: color),
          if (n.resueltoPor != null || n.resueltoEn != null) ...[
            const SizedBox(height: Espacio.xs),
            Text(
              [
                if (n.resueltoPor != null) 'Por ${n.resueltoPor}',
                if (n.resueltoEn != null) '${Formato.fechaCorta(n.resueltoEn!)}, ${Formato.hora(n.resueltoEn!)}',
              ].join(' · '),
              style: context.textos.bodyMedium,
            ),
          ],
          if ((n.comentario ?? '').isNotEmpty) ...[
            const SizedBox(height: Espacio.xs),
            Text('«${n.comentario}»', style: context.textos.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

/// Fotos (se ven aquí y se amplían) y PDF (se abren con el visor del teléfono).
class _ListaSoportes extends StatelessWidget {
  const _ListaSoportes({required this.api, required this.novedadId, required this.soportes});
  final Api api;
  final int novedadId;
  final Future<List<SoporteNovedad>>? soportes;

  Future<void> _abrirPdf(BuildContext context, SoporteNovedad s) async {
    try {
      final bytes = await api.descargarSoporte(novedadId, s.id);
      final dir = await getTemporaryDirectory();
      final archivo = File('${dir.path}/soporte_${novedadId}_${s.id}.pdf');
      await archivo.writeAsBytes(bytes, flush: true);
      final r = await OpenFilex.open(archivo.path, type: 'application/pdf');
      if (r.type != ResultType.done && context.mounted) {
        avisar(context, 'No hay una app para abrir PDF en este teléfono', error: true);
      }
    } on ApiError catch (e) {
      if (context.mounted) avisar(context, e.mensaje, error: true);
    }
  }

  void _ampliar(BuildContext context, SoporteNovedad s) {
    final foto = api.soporteNovedad(novedadId, s.id);
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(s.nombre)),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.network(foto.url, headers: foto.cabeceras, semanticLabel: 'Soporte ${s.nombre}')),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SoporteNovedad>>(
      future: soportes,
      builder: (context, snap) {
        final lista = snap.data;
        return Seccion(
          titulo: 'Soportes',
          hijos: [
            if (snap.hasError)
              Text(
                snap.error is ApiError ? (snap.error! as ApiError).mensaje : 'No se pudieron cargar los soportes',
                style: context.textos.bodyMedium?.copyWith(color: context.sem.peligro),
              )
            else if (lista == null)
              const Center(child: Padding(padding: EdgeInsets.all(Espacio.sm), child: CircularProgressIndicator()))
            else
              for (final s in lista)
                if (s.esImagen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.xs),
                    child: Semantics(
                      button: true,
                      label: 'Ampliar ${s.nombre}',
                      child: InkWell(
                        onTap: () => _ampliar(context, s),
                        borderRadius: BorderRadius.circular(Redondeo.md),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Redondeo.md),
                          child: Builder(builder: (context) {
                            final foto = api.soporteNovedad(novedadId, s.id);
                            return Image.network(
                              foto.url,
                              headers: foto.cabeceras,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              cacheWidth: 900,
                              errorBuilder: (_, _, _) => const SizedBox(
                                height: 80,
                                child: Center(child: Icon(Icons.broken_image_outlined)),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(s.esPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,
                        color: context.colores.primary),
                    title: Text(s.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${(s.tamano / 1024).ceil()} KB'),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _abrirPdf(context, s),
                  ),
          ],
        );
      },
    );
  }
}
