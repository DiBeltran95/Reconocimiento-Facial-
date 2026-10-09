import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../servicios/estado_app.dart';
import '../comun/widgets.dart';
import 'componentes_kiosco.dart';

/// Panel del usuario GENERAL: solo lo necesario para operar el kiosco.
class OperadorPage extends StatefulWidget {
  const OperadorPage({super.key});

  @override
  State<OperadorPage> createState() => _OperadorPageState();
}

class _OperadorPageState extends State<OperadorPage> {
  late final EstadoApp _estado = context.read<EstadoApp>();

  @override
  void initState() {
    super.initState();
    _estado.sesion.addListener(_vigilarSesion);
  }

  @override
  void dispose() {
    _estado.sesion.removeListener(_vigilarSesion);
    super.dispose();
  }

  void _vigilarSesion() {
    if (!_estado.sesion.activa && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final sesion = _estado.sesion.sesion;
    return Listener(
      onPointerDown: (_) => _estado.sesion.tocar(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Volver al kiosco',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OPERADOR · ${sesion?.nombre.toUpperCase() ?? ''}',
                style: context.textos.labelSmall?.copyWith(color: context.colores.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Text('Kiosco'),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: _estado.sesion.cerrar,
              icon: const Icon(Icons.lock_outline_rounded, size: 20),
              label: const Text('Cerrar sesión'),
            ),
            const SizedBox(width: Espacio.xs),
          ],
        ),
        body: FondoTecnico(
          intensidad: 0.6,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Espacio.md, Espacio.xs, Espacio.md, Espacio.xxl),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: context.colores.primary),
                  title: const Text('Cuenta General'),
                  subtitle: const Text(
                    'Puedes sincronizar este kiosco, revisar las marcaciones de hoy y cambiarlo de sede. '
                    'El personal, los horarios y los reportes los gestiona un usuario Administrativo.',
                  ),
                ),
              ),
              const SizedBox(height: Espacio.md),
              const TarjetaEsteKiosco(),
              const SizedBox(height: Espacio.md),
              const TarjetaSincronizacion(),
              const SizedBox(height: Espacio.md),
              const MarcacionesDeHoy(),
              const SizedBox(height: Espacio.md),
              const TarjetaDesvincular(),
            ],
          ),
        ),
      ),
    );
  }
}
