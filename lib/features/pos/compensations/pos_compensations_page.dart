// [EXAMEN-2] CU19: compensaciones de ventas offline rechazadas (modo cajero).
// Estado, tipo, monto, motivo y confirmación de efectivo con doble
// confirmación. La app nunca ejecuta reembolsos por pasarela (D-MOV-20).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/compensation_model.dart';
import '../../../core/providers/compensation_provider.dart';

class PosCompensationsPage extends StatefulWidget {
  const PosCompensationsPage({super.key});

  @override
  State<PosCompensationsPage> createState() => _PosCompensationsPageState();
}

class _PosCompensationsPageState extends State<PosCompensationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompensationProvider>().load();
    });
  }

  Color _estadoColor(String estado) => switch (estado.toUpperCase()) {
    'COMPLETADA' => Colors.green,
    'FALLIDA' => Colors.red,
    'EN_PROCESO' => Colors.blue,
    _ => Colors.orange,
  };

  Future<void> _confirmar(CompensacionModel compensacion) async {
    final provider = context.read<CompensationProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar efectivo'),
        content: Text(
          '¿Confirmas la entrega de Bs. ${compensacion.monto.toStringAsFixed(2)} '
          'en efectivo al cliente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final confirmado = await provider.confirmarEfectivo(compensacion.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          confirmado
              ? 'Efectivo confirmado'
              : provider.errorMessage ?? 'No se pudo confirmar',
        ),
        backgroundColor: confirmado ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CompensationProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Compensaciones (cajero)')),
      body: provider.isLoading && provider.compensaciones.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.compensaciones.isEmpty
          ? const Center(
              child: Text('Sin compensaciones pendientes de revisar'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: provider.compensaciones.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final c = provider.compensaciones[i];
                final color = _estadoColor(c.estado);
                return Card(
                  child: ListTile(
                    title: Text(
                      '#${c.id} • ${CompensacionTipos.labelTipo(c.tipo)}',
                    ),
                    subtitle: Text(
                      'Bs. ${c.monto.toStringAsFixed(2)} • '
                      '${CompensacionTipos.labelEstado(c.estado)}'
                      '${c.motivo != null && c.motivo!.isNotEmpty ? '\n${c.motivo}' : ''}',
                    ),
                    trailing: Icon(Icons.circle, color: color, size: 14),
                    onTap: () => provider.seleccionar(c.id),
                  ),
                );
              },
            ),
      bottomSheet: provider.detalleSeleccionado == null
          ? null
          : Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Detalle #${provider.detalleSeleccionado!.id}: '
                      '${provider.detalleSeleccionado!.motivo ?? ''}',
                    ),
                    if (provider.detalleSeleccionado!.esEfectivo &&
                        !provider.detalleSeleccionado!.estaCompletada)
                      FilledButton(
                        onPressed: () =>
                            _confirmar(provider.detalleSeleccionado!),
                        child: const Text('Confirmar efectivo'),
                      )
                    else if (!provider.detalleSeleccionado!.esEfectivo)
                      const Text(
                        'Este reembolso lo procesa el sistema; '
                        'la app no ejecuta pagos por pasarela.',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
