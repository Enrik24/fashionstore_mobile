import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/conflict_provider.dart';
import '../../core/utils/conflict_classifier.dart';
import 'conflict_detail_sheet.dart';

/// [EXAMEN-2] Comparación y resolución de conflictos (CU09).
class ConflictsPage extends StatelessWidget {
  const ConflictsPage({super.key});

  /// [EXAMEN-2] B1.5.h: abre el detalle del conflicto (Local vs Central).
  ///
  /// La hoja exist��a pero **nunca se instanciaba**: la pantalla usaba un
  /// `ExpansionTile` inline. Ahora el detalle completo (con la comparación
  /// local↔central y las tres acciones) se muestra en la hoja.
  void _abrirDetalle(BuildContext context, dynamic conflicto) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ConflictDetailSheet(
        conflict: conflicto,
        onResolver: (accion) {
          context.read<ConflictProvider>().resolver(conflicto.id, accion);
          Navigator.pop(sheetContext);
        },
        onDescartar: () {
          context.read<ConflictProvider>().descartar(conflicto.id);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }

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
                // [EXAMEN-2] B1.5.b/c: el estado distingue el conflicto
                // ordinary del que requiere decisión humana y del error de
                // datos maestros.
                final requiereDecision =
                    conflicto.estado.toUpperCase() ==
                    EstadosConflicto.conflictoManual;
                final errorDatos =
                    conflicto.estado.toUpperCase() ==
                    EstadosConflicto.errorDatos;
                return Card(
                  margin: const EdgeInsets.all(12),
                  child: ListTile(
                    title: Text(conflicto.tipo),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(provider.traducirMotivo(conflicto.motivo)),
                        if (requiereDecision)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Requiere decisión del administrador',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (errorDatos)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Datos maestros inválidos en el servidor',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (ConflictClassifier.requiereIntervencionServidor(
                          conflicto.tipo,
                        ))
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'El sistema debe ejecutar el reembolso o '
                              'deshacer el cobro duplicado',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _abrirDetalle(context, conflicto),
                  ),
                );
              },
            ),
    );
  }
}
