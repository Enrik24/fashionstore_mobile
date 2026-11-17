import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';

/// [EXAMEN-2] C2.4 (§5.3, RN-014): sello de descarga y etiqueta
/// "precio referencial" para precios locales sin verificar en servidor.
///
/// [EXAMEN-2] B2.1: había **dos** widgets con el mismo nombre y distinto
/// comportamiento (este y `features/offline/widgets/offline_data_stamp.dart`).
/// Se han unificado en este: si no se pasa el sello explícito, se lee el
/// último sello persistido (`StorageService.readDownloadStamp`, que desde la
/// Ola 2 se escribe al completar la descarga).
class OfflineDataStamp extends StatelessWidget {
  const OfflineDataStamp({
    super.key,
    this.sello,
    this.esReferencial = false,
  });

  /// Sello explícito (p. ej. el del proveedor de catálogo).
  final DateTime? sello;

  /// Muestra la etiqueta de "precio referencial".
  final bool esReferencial;

  @override
  Widget build(BuildContext context) {
    DateTime? fecha = sello;
    if (fecha == null) {
      try {
        fecha = context.read<StorageService>().readDownloadStamp();
      } catch (_) {
        // Sin `StorageService` en el árbol (p. ej. en un test): se omite.
      }
    }
    final partes = <String>[];
    if (fecha != null) {
      final d = fecha.toLocal();
      partes.add(
        'Datos del ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
      );
    }
    if (esReferencial) partes.add('Precio referencial — verificar al sincronizar');
    if (partes.isEmpty) return const SizedBox.shrink();
    return Text(
      partes.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: 11,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}
