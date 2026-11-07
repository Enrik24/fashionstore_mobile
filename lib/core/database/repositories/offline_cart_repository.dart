import 'tenant_local_repository.dart';

/// [EXAMEN-2] Repositorio del carrito persistente y tenant-aware.
class OfflineCartRepository extends TenantLocalRepository {
  OfflineCartRepository(super.db, {required super.tenantId});

  Future<Map<String, Object?>?> obtenerActivo() async {
    final filas = await consultar(
      'carrito',
      where: "tenant_id = ? AND estado = 'ACTIVO'",
      whereArgs: <Object?>[tenantId],
      orderBy: 'fecha_actualizacion DESC',
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  Future<Map<String, Object?>?> obtenerPorUuid(String uuid) async {
    final filas = await consultar(
      'carrito',
      where: 'uuid_carrito = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, tenantId],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  Future<void> crear(
    String uuid, {
    Map<String, Object?> datos = const {},
  }) async {
    await guardarPorClave('carrito', 'uuid_carrito', uuid, <String, Object?>{
      ...datos,
      'uuid_carrito': uuid,
      'estado': datos['estado'] ?? 'ACTIVO',
      'subtotal': datos['subtotal'] ?? 0,
      'impuestos': datos['impuestos'] ?? 0,
      'total': datos['total'] ?? 0,
    });
  }

  Future<void> guardar(Map<String, Object?> carrito) {
    return guardarPorClave(
      'carrito',
      'uuid_carrito',
      carrito['uuid_carrito'],
      carrito,
    );
  }

  Future<int> agregarItem({
    required String uuidCarrito,
    required int varianteProductoId,
    required int cantidad,
    required double precioUnitario,
    int? stockConocido,
  }) {
    final ahora = DateTime.now().toUtc().toIso8601String();
    return db.insert('items_carrito', <String, Object?>{
      'uuid_carrito': uuidCarrito,
      'tenant_id': tenantId,
      'variante_producto_id': varianteProductoId,
      'cantidad': cantidad,
      'precio_unitario': precioUnitario,
      'subtotal': precioUnitario * cantidad,
      'stock_conocido': stockConocido,
      'fecha_actualizacion': ahora,
    });
  }

  Future<void> guardarItems(
    String uuidCarrito,
    Iterable<Map<String, Object?>> items,
  ) async {
    for (final item in items) {
      await guardarPorClave(
        'items_carrito',
        'id',
        item['id'],
        <String, Object?>{
          ...item,
          'uuid_carrito': uuidCarrito,
          'tenant_id': tenantId,
        },
      );
    }
  }

  Future<List<Map<String, Object?>>> listarItems(String uuidCarrito) {
    return consultar(
      'items_carrito',
      where: 'uuid_carrito = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuidCarrito, tenantId],
      orderBy: 'id',
    );
  }

  Future<int> actualizarItem(
    int id, {
    required int cantidad,
    required double precioUnitario,
    int? stockConocido,
  }) {
    return db.update(
      'items_carrito',
      <String, Object?>{
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
        'subtotal': cantidad * precioUnitario,
        'stock_conocido': stockConocido,
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[id, tenantId],
    );
  }

  Future<int> quitarItem(int id) => eliminarRegistro('items_carrito', 'id', id);

  Future<int> vaciar(String uuidCarrito) {
    return db.delete(
      'items_carrito',
      where: 'uuid_carrito = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuidCarrito, tenantId],
    );
  }

  Future<int> eliminarCarrito(String uuidCarrito) =>
      eliminarRegistro('carrito', 'uuid_carrito', uuidCarrito);
}
