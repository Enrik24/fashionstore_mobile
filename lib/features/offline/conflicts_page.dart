import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/conflict_provider.dart';

/// [EXAMEN-2] Comparación y resolución de conflictos (CU09).
class ConflictsPage extends StatelessWidget {
  const ConflictsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConflictProvider>();
    return Scaffold(
      appBar: AppBar(title: Text('Conflictos (${provider.pendingCount})')),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.conflicts.isEmpty
          ? const Center(child: Text('No hay conflictos pendientes'))
          : ListView.builder(
              itemCount: provider.conflicts.length,
              itemBuilder: (context, index) {
                final conflicto = provider.conflicts[index];
                return Card(
                  margin: const EdgeInsets.all(12),
                  child: ExpansionTile(
                    title: Text(conflicto.tipo),
                    subtitle: Text(provider.traducirMotivo(conflicto.motivo)),
                    children: [
                      if (conflicto.datosLocal != null)
                        _Datos(
                          titulo: 'Datos locales',
                          datos: conflicto.datosLocal!,
                        ),
                      if (conflicto.datosCentral != null)
                        _Datos(
                          titulo: 'Datos del servidor',
                          datos: conflicto.datosCentral!,
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => provider.descartar(conflicto.id),
                              child: const Text('Descartar'),
                            ),
                            FilledButton(
                              onPressed: () => provider.resolver(
                                conflicto.id,
                                'ACEPTAR_CENTRAL',
                              ),
                              child: const Text('Aceptar servidor'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Datos extends StatelessWidget {
  const _Datos({required this.titulo, required this.datos});
  final String titulo;
  final Map<String, Object?> datos;

  @override
  Widget build(BuildContext context) {
    Object? decoded = datos;
    return ExpansionTile(
      title: Text(titulo),
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('$decoded')),
      ],
    );
  }
}
