import 'local_operation_repository.dart';

/// [EXAMEN-2] Repositorio de ventas de contado registradas offline.
class LocalSaleRepository extends LocalOperationRepository {
  LocalSaleRepository(super.db, {required super.tenantId})
    : super(
        tablaCabecera: 'ventas_locales',
        columnaUuid: 'uuid_offline',
        tablaItems: 'items_venta_local',
      );

  Future<List<Map<String, Object?>>> listarPorSucursal(int sucursalId) {
    return consultar(
      'ventas_locales',
      where: 'sucursal_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[sucursalId, tenantId],
      orderBy: 'fecha_registro_local DESC',
    );
  }

  Future<List<Map<String, Object?>>> listarPendientes() =>
      listarPorEstado('PENDIENTE_SINCRONIZACION');

  Future<void> registrarVenta(
    String uuid, {
    required int sucursalId,
    required double total,
    required double montoRecibido,
    required double cambio,
    Map<String, Object?> datos = const {},
    List<Map<String, Object?>> items = const [],
  }) async {
    await crear(uuid, <String, Object?>{
      'sucursal_id': sucursalId,
      'cliente_id': datos['cliente_id'],
      'cajero_id': datos['cajero_id'],
      'es_offline': datos['es_offline'] ?? 1,
      'estado': datos['estado'] ?? 'PENDIENTE_SINCRONIZACION',
      'estado_sincronizacion':
          datos['estado_sincronizacion'] ?? 'PENDIENTE_SINCRONIZACION',
      'subtotal': datos['subtotal'] ?? total,
      'impuestos': datos['impuestos'] ?? 0,
      'total': total,
      'monto_recibido': montoRecibido,
      'cambio': cambio,
      'metodo_pago': datos['metodo_pago'],
      'datos_json': datos['datos_json'],
      'fecha_registro_local':
          datos['fecha_registro_local'] ??
          DateTime.now().toUtc().toIso8601String(),
    });
    await guardarItems(uuid, items);
  }
}
