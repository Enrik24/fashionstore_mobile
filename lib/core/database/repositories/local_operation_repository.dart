import 'tenant_local_repository.dart';

/// [EXAMEN-2] Base de operaciones locales con cabecera y detalle.
abstract class LocalOperationRepository extends TenantLocalRepository {
  LocalOperationRepository(
    super.db, {
    required super.tenantId,
    required this.tablaCabecera,
    required this.columnaUuid,
    required this.tablaItems,
  });

  final String tablaCabecera;
  final String columnaUuid;
  final String tablaItems;

  Future<void> crear(String uuid, Map<String, Object?> datos) {
    return guardarPorClave(tablaCabecera, columnaUuid, uuid, <String, Object?>{
      ...datos,
      columnaUuid: uuid,
    });
  }

  Future<void> guardar(String uuid, Map<String, Object?> datos) {
    return guardarPorClave(tablaCabecera, columnaUuid, uuid, <String, Object?>{
      ...datos,
      columnaUuid: uuid,
    });
  }

  Future<Map<String, Object?>?> obtenerPorUuid(String uuid) async {
    final filas = await consultar(
      tablaCabecera,
      where: '$columnaUuid = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, tenantId],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  Future<List<Map<String, Object?>>> listarPorEstado(String estado) {
    return consultar(
      tablaCabecera,
      where: 'estado = ? AND tenant_id = ?',
      whereArgs: <Object?>[estado, tenantId],
      orderBy: 'fecha_actualizacion DESC',
    );
  }

  Future<List<Map<String, Object?>>> listarTodos() {
    return consultar(
      tablaCabecera,
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantId],
      orderBy: 'fecha_actualizacion DESC',
    );
  }

  Future<void> guardarItems(
    String uuid,
    Iterable<Map<String, Object?>> items,
  ) async {
    for (final item in items) {
      final id = item['id'];
      if (id == null) {
        await db.insert(tablaItems, <String, Object?>{
          ...item,
          columnaUuid: uuid,
          'tenant_id': tenantId,
          'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await guardarPorClave(tablaItems, 'id', id, <String, Object?>{
          ...item,
          columnaUuid: uuid,
          'tenant_id': tenantId,
        });
      }
    }
  }

  Future<List<Map<String, Object?>>> listarItems(String uuid) {
    return consultar(
      tablaItems,
      where: '$columnaUuid = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, tenantId],
      orderBy: 'id',
    );
  }

  Future<int> eliminarOperacion(String uuid) =>
      eliminarRegistro(tablaCabecera, columnaUuid, uuid);

  Future<int> actualizarEstado(String uuid, String estado) {
    return db.update(
      tablaCabecera,
      <String, Object?>{
        'estado': estado,
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: '$columnaUuid = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, tenantId],
    );
  }
}
