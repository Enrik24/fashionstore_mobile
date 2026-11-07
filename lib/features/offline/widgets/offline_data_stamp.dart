import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/services/storage_service.dart';

/// [EXAMEN-2] Sello de última descarga para datos locales (CU17/CU05).
class OfflineDataStamp extends StatelessWidget {
  const OfflineDataStamp({super.key});

  @override
  Widget build(BuildContext context) {
    final stamp = context.read<StorageService>().readDownloadStamp();
    if (stamp == null) return const SizedBox.shrink();
    final fecha = DateFormat('dd/MM/yyyy HH:mm').format(stamp.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'Datos actualizados al $fecha. Los precios y el stock son referenciales.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
