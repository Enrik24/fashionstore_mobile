import 'local_operation_repository.dart';

/// [EXAMEN-2] Repositorio de reservas creadas sin conexiÃ³n.
class LocalReservationRepository extends LocalOperationRepository {
  LocalReservationRepository(super.db, {required super.tenantId})
    : super(
        tablaCabecera: 'reservas_locales',
        columnaUuid: 'uuid_reserva',
        tablaItems: 'items_reserva_local',
      );

  Future<List<Map<String, Object?>>> listarPorCliente(int clienteId) {
    return consultar(
      'reservas_locales',
      where: 'cliente_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[clienteId, tenantId],
      orderBy: 'fecha_registro_local DESC',
    );
  }

  Future<List<Map<String, Object?>>> listarPendientes() =>
      listarPorEstado('PENDIENTE_SINCRONIZACION');
}
