import 'package:flutter/material.dart';

import '../../core/models/phase2_models.dart';
import '../../core/utils/sync_messages.dart';

/// [EXAMEN-2] C2.6 (§3.3) CU09: detalle del conflicto (Local vs Central).
class ConflictDetailSheet extends StatelessWidget {
  const ConflictDetailSheet({
    super.key,
    required this.conflict,
    required this.onResolver,
    required this.onDescartar,
  });

  final ConflictModel conflict;
  final void Function(String accion) onResolver;
  final VoidCallback onDescartar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conflicto ${conflict.tipo}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Chip(label: Text(SyncMessages.traducirEstado(conflict.estado))),
            const SizedBox(height: 12),
            Text(
              SyncMessages.traducirMotivo(conflict.motivo),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _Columna(titulo: 'Local', datos: conflict.datosLocal),
            const SizedBox(height: 8),
            _Columna(titulo: 'Central', datos: conflict.datosCentral),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDescartar,
                    child: const Text('Descartar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => onResolver('ACEPTAR_LOCAL'),
                    child: const Text('Conservar local'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => onResolver('ACEPTAR_CENTRAL'),
                child: const Text('Aceptar servidor'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna({required this.titulo, required this.datos});
  final String titulo;
  final Map<String, Object?>? datos;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            datos == null || datos!.isEmpty
                ? '—'
                : datos!.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
