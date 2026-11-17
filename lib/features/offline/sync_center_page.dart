import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/compensation_provider.dart';
import '../../core/providers/sync_provider.dart';
import '../../core/widgets/sync_queue_card.dart';
import '../../core/widgets/sync_status_chip.dart';

/// [EXAMEN-2] Centro de sincronización y contador de operaciones (CU08).
class SyncCenterPage extends StatelessWidget {
  const SyncCenterPage({super.key});

  /// [EXAMEN-2] Feedback inmediato del botón: antes una sincronización sin
  /// conexión o con la cola vacía no producía ningún aviso en pantalla.
  Future<void> _sincronizar(BuildContext context, SyncProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    await provider.sincronizar();
    final error = provider.ultimoError;
    final mensaje = provider.mensajeSincronizacion;
    final texto = error ?? mensaje;
    if (texto == null || texto.isEmpty) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error != null ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SyncProvider>();
    final resumen = provider.summary;
    // [EXAMEN-2] CU19: badge de compensaciones en el centro de sincronización.
    var pendientesCompensacion = 0;
    try {
      pendientesCompensacion =
          context.watch<CompensationProvider>().pendientesCount;
    } catch (_) {}
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pendientesCompensacion > 0)
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(
                  '$pendientesCompensacion compensación(es) pendiente(s)',
                ),
                subtitle: const Text('Confirmación de efectivo en caja (CU19)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/pos/compensations'),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircularProgressIndicator(value: provider.progreso),
                  const SizedBox(height: 8),
                  Text(provider.etiquetaProgreso),
                  const SizedBox(height: 16),
                  Text(
                    '${resumen.pendientes} operaciones pendientes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Confirmadas: ${resumen.confirmadas}'),
                  Text('Duplicadas: ${resumen.duplicadas}'),
                  Text('Conflictos: ${resumen.conflictos}'),
                  Text('Rechazadas: ${resumen.rechazadas}'),
                  Text('Errores críticos: ${resumen.erroresCriticos}'),
                  // [EXAMEN-2] B2.1: chip de estado de la última operación.
                  if (provider.pendientes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SyncStatusChip(
                        estado: provider.pendientes.first.estadoSincronizacion,
                      ),
                    ),
                  // [EXAMEN-2] B1.4.a: mensaje de resumen del spec.
                  if (provider.mensajeSincronizacion != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        provider.mensajeSincronizacion!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (provider.ultimoError != null)
                    Text(
                      'Último error: ${provider.ultimoError}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: provider.isLoading
                ? null
                : () => _sincronizar(context, provider),
            icon: const Icon(Icons.sync),
            label: Text(
              provider.isLoading ? 'Sincronizando…' : 'Sincronizar ahora',
            ),
          ),
          // [EXAMEN-2] B2.1: cola de operaciones pendientes con reintento
          // por ítem. El widget existía pero **nunca se instanciaba**.
          if (provider.pendientes.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Operaciones en cola (${provider.pendientes.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final operacion in provider.pendientes)
              SyncQueueCard(
                operacion: operacion,
                onReintentar: () =>
                    provider.reintentarOperacion(operacion.uuidOperacion),
              ),
          ],
        ],
      ),
    );
  }
}
