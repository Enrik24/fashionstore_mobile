import 'local_operation_repository.dart';

/// [EXAMEN-2] Repositorio de Ã³rdenes locales, incluidas las de pago diferido.
class LocalOrderRepository extends LocalOperationRepository {
  LocalOrderRepository(super.db, {required super.tenantId})
    : super(
        tablaCabecera: 'ordenes_locales',
        columnaUuid: 'uuid_orden',
        tablaItems: 'items_orden_local',
      );

  Future<List<Map<String, Object?>>> listarVigentes() {
    return consultar(
      'ordenes_locales',
      where: 'tenant_id = ? AND (expira_en IS NULL OR expira_en >= ?)',
      whereArgs: <Object?>[tenantId, DateTime.now().toUtc().toIso8601String()],
      orderBy: 'fecha_registro_local DESC',
    );
  }

  Future<int> marcarExpirada(String uuid) => actualizarEstado(uuid, 'EXPIRADA');
}
