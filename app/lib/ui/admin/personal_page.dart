import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/api.dart';
import '../../data/modelos.dart';
import '../comun/widgets.dart';
import '../horarios/widgets_horario.dart';
import 'contexto_admin.dart';
import 'empleado_form_page.dart';
import 'selector_sede.dart';

/// Personal de la sede: alta, edición, baja y registro del rostro.
class PersonalPage extends StatefulWidget {
  const PersonalPage({super.key});

  @override
  State<PersonalPage> createState() => _PersonalPageState();
}

class _PersonalPageState extends State<PersonalPage> {
  late final ContextoAdmin _ctx = context.read<ContextoAdmin>();
  List<Empleado>? _empleados;
  String? _error;
  bool _cargando = true;
  String _busqueda = '';
  bool _soloSinRostro = false;

  @override
  void initState() {
    super.initState();
    _ctx.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    _ctx.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final lista = await _ctx.api.empleados(sedeId: _ctx.sede.id);
      if (mounted) {
        setState(() {
          _empleados = lista;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir([Empleado? e]) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: _ctx, child: EmpleadoFormPage(empleado: e)),
      ),
    );
    if (cambio == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = (_empleados ?? const <Empleado>[])
        .where((e) => !_soloSinRostro || !e.tieneRostro)
        .where((e) =>
            _busqueda.isEmpty ||
            e.nombre.toLowerCase().contains(_busqueda) ||
            e.documento.toLowerCase().contains(_busqueda) ||
            (e.cargo ?? '').toLowerCase().contains(_busqueda))
        .toList();
    final sinRostro = (_empleados ?? const <Empleado>[]).where((e) => !e.tieneRostro).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrir(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo empleado'),
      ),
      body: FondoTecnico(
        intensidad: 0.6,
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SelectorSede(),
                      const SizedBox(height: Espacio.sm),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nombre, documento o cargo',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: Espacio.sm),
                      Row(
                        children: [
                          Text(
                            '${_empleados?.length ?? 0} empleados',
                            style: context.textos.labelLarge?.copyWith(color: context.sem.textoSuave),
                          ),
                          const Spacer(),
                          if (sinRostro > 0)
                            FilterChip(
                              avatar: Icon(Icons.face_retouching_off_rounded, size: 18, color: context.sem.alerta),
                              label: Text('Sin rostro ($sinRostro)'),
                              selected: _soloSinRostro,
                              onSelected: (v) => setState(() => _soloSinRostro = v),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_cargando && _empleados == null)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (_error != null && _empleados == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EstadoVacio(icono: Icons.cloud_off_rounded, titulo: 'No se pudo cargar', mensaje: _error, accion: _cargar),
                )
              else if (lista.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EstadoVacio(
                    icono: Icons.groups_outlined,
                    titulo: (_empleados?.isEmpty ?? true) ? 'Aún no hay personal' : 'Sin resultados',
                    mensaje: (_empleados?.isEmpty ?? true)
                        ? 'Agrega al primer empleado y registra su rostro.'
                        : 'Prueba con otra búsqueda.',
                    accion: (_empleados?.isEmpty ?? true) ? () => _abrir() : null,
                    etiquetaAccion: 'Agregar empleado',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Espacio.md, 0, Espacio.md, 96),
                  sliver: SliverList.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Espacio.xs),
                    itemBuilder: (_, i) => _TarjetaEmpleado(empleado: lista[i], api: _ctx.api, alTocar: () => _abrir(lista[i])),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaEmpleado extends StatelessWidget {
  const _TarjetaEmpleado({required this.empleado, required this.api, required this.alTocar});
  final Empleado empleado;
  final Api api;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final foto = empleado.fotos.isEmpty ? null : api.foto(empleado.id, empleado.fotos.first.n, empleado.fotos.first.v);
    return Card(
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(Redondeo.lg),
        child: Padding(
          padding: const EdgeInsets.all(Espacio.sm),
          child: Row(
            children: [
              AvatarEmpleado(nombre: empleado.nombre, url: foto?.url, cabeceras: foto?.cabeceras, tam: 48),
              const SizedBox(width: Espacio.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(empleado.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textos.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      [empleado.documento, if (empleado.cargo != null) empleado.cargo!].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textos.bodyMedium?.copyWith(color: sem.textoSuave),
                    ),
                    const SizedBox(height: 2),
                    if (empleado.turnoSemana == null)
                      Text('Sin horario', style: context.textos.bodySmall?.copyWith(color: sem.alerta))
                    else
                      EtiquetaTurno(
                        nombre: empleado.turnoSemana!.nombre,
                        bloques: empleado.turnoSemana!.bloques,
                        color: context.colores.primary,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Espacio.xs),
              empleado.tieneRostro
                  ? Pildora(texto: 'Rostro', color: sem.entrada, fondo: sem.entradaFondo, icono: Icons.verified_rounded)
                  : Pildora(texto: 'Sin rostro', color: sem.alerta, fondo: sem.alertaFondo, icono: Icons.face_retouching_off_rounded),
              const SizedBox(width: Espacio.xxs),
              Icon(Icons.chevron_right_rounded, color: sem.textoSuave),
            ],
          ),
        ),
      ),
    );
  }
}
