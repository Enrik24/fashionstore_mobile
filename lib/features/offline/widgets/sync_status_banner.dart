import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/compensation_provider.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/offline_session_provider.dart';
import '../../../core/providers/sync_provider.dart';

/// [EXAMEN-2] Banner de estado online/offline y cuenta regresiva de CU17.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityProvider>().estaEnLinea;
    final session = context.watch<OfflineSessionProvider>();
    final restante = session.tiempoRestante;
    // [EXAMEN-2] RF-030: badge de compensaciones pendientes en el banner.
    var compensaciones = 0;
    try {
      compensaciones = context.watch<CompensationProvider>().pendientesCount;
    } catch (_) {}
    // [EXAMEN-2] B1.8.c: el banner muestra **también** la última
    // sincronización (el spec pide "Modo offline — última sincronización").
    DateTime? ultimaSync;
    try {
      ultimaSync = context.watch<SyncProvider>().ultimaSincronizacion;
    } catch (_) {}
    final sufijoSync = ultimaSync == null
        ? ''
        : ' — última sincronización: ${_hora(ultimaSync)}';
    final texto = online
        ? 'En línea'
        : session.haySesionValida
        ? 'Modo offline$sufijoSync · vence en ${restante.inHours}h '
              '${restante.inMinutes.remainder(60)}m'
        : 'Sin conexión$sufijoSync. Se enviarán las operaciones al recuperar la red.';
    return Material(
      color: online ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(online ? Icons.cloud_done : Icons.cloud_off, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(texto)),
            if (compensaciones > 0)
              Chip(
                label: Text('$compensaciones compensación(es)'),
                avatar: const Icon(Icons.payments, size: 16),
              ),
            if (!online && !session.haySesionValida)
              TextButton(onPressed: () {}, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  /// [EXAMEN-2] B1.8.c: hora legible de la última sincronización.
  String _hora(DateTime valor) {
    final local = valor.toLocal();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(local.day)}/${dos(local.month)} '
        '${dos(local.hour)}:${dos(local.minute)}';
  }
}
