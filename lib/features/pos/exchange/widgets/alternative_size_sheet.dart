// [EXAMEN-2] CU18/RN-022: alternativas de talla mayor/menor en la sucursal u
// otras sucursales; sin alternativa se deriva a devolución (SIN_ALTERNATIVA).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/providers/offline_return_provider.dart';

Future<void> showAlternativeSizeSheet(
  BuildContext context, {
  required int varianteId,
  int? sucursalId,
}) async {
  final provider = context.read<OfflineReturnProvider>();
  await provider.buscarAlternativaTalla(
    varianteId: varianteId,
    sucursalId: sucursalId,
  );
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: provider,
      child: const _AlternativeSheetBody(),
    ),
  );
}

class _AlternativeSheetBody extends StatelessWidget {
  const _AlternativeSheetBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<OfflineReturnProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (provider.alternativas.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.help_outline, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'SIN_ALTERNATIVA: no hay talla mayor ni menor '
                  'en esta sucursal ni en otras sucursales.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Se derivó a devolución (RN-022).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        }
        return ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Alternativas de talla'),
              subtitle: Text('Mayor/menor en esta sucursal u otras'),
            ),
            ...provider.alternativas.map(
              (alt) => ListTile(
                title: Text(
                  alt['sucursal']?.toString() ??
                      alt['talla']?.toString() ??
                      'Alternativa',
                ),
                subtitle: Text(
                  'Variante ${alt['variante_id'] ?? alt['id'] ?? ''} • '
                  'Stock: ${alt['stock'] ?? 0}',
                ),
                trailing: Text('${alt['precio'] ?? ''}'),
              ),
            ),
          ],
        );
      },
    );
  }
}
