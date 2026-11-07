import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/compensation_provider.dart';
import '../../core/providers/sync_provider.dart';

/// [EXAMEN-2] Centro de sincronización y contador de operaciones (CU08).
class SyncCenterPage extends StatelessWidget {
  const SyncCenterPage({super.key});

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
            onPressed: provider.isLoading ? null : provider.sincronizar,
            icon: const Icon(Icons.sync),
            label: Text(
              provider.isLoading ? 'Sincronizando…' : 'Sincronizar ahora',
            ),
          ),
        ],
      ),
    );
  }
}
