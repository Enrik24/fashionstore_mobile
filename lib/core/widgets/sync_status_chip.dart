import 'package:flutter/material.dart';

import '../utils/sync_messages.dart';

/// [EXAMEN-2] C2.6 (§3.3): chip de estado de sincronización.
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final esError = estado.toUpperCase() == 'ERROR_CRITICO';
    return Chip(
      label: Text(SyncMessages.traducirEstado(estado)),
      backgroundColor: esError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
    );
  }
}
