import 'package:flutter/material.dart';

import '../models/phase2_models.dart';
import '../utils/sync_messages.dart';

/// [EXAMEN-2] C2.6 (§3.3) CU08: tarjeta de cola con reintento por ítem.
class SyncQueueCard extends StatelessWidget {
  const SyncQueueCard({
    super.key,
    required this.operacion,
    this.onReintentar,
  });

  final OfflineOperationModel operacion;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.sync),
        title: Text(operacion.tipoOperacion),
        subtitle: Text(
          '${SyncMessages.traducirEstado(operacion.estadoSincronizacion)}'
          '${operacion.errorDetalle != null ? ' — ${operacion.errorDetalle}' : ''}',
        ),
        trailing: onReintentar == null
            ? null
            : IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: onReintentar,
              ),
      ),
    );
  }
}
