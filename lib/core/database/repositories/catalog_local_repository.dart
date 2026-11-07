import 'dart:convert';

import 'tenant_local_repository.dart';

/// [EXAMEN-2] Repositorio del catÃ¡logo descargable para consulta offline.
class CatalogLocalRepository extends TenantLocalRepository {
  CatalogLocalRepository(super.db, {required super.tenantId});

  Future<void> guardarProducto(Map<String, Object?> producto) {
    final datos = <String, Object?>{...producto};
    final imagenes = datos['imagenes'];
    if (imagenes is List) datos['imagenes'] = jsonEncode(imagenes);
    if (datos['precio_referencia'] != null && datos['precio'] == null) {
      datos['precio'] = datos['precio_referencia'];
    }
    return guardarPorClave('productos', 'id', producto['id'], datos);
  }

  Future<void> guardarVariante(Map<String, Object?> variante) =>
      guardarPorClave('variantes', 'id', variante['id'], variante);
  Future<void> guardarSucursal(Map<String, Object?> sucursal) =>
      guardarPorClave('sucursales', 'id', sucursal['id'], sucursal);
  Future<void> guardarCategoria(Map<String, Object?> categoria) =>
      guardarPorClave('categorias', 'id', categoria['id'], categoria);
  Future<void> guardarTalla(Map<String, Object?> talla) =>
      guardarPorClave('tallas', 'id', talla['id'], talla);
  Future<void> guardarColor(Map<String, Object?> color) =>
      guardarPorClave('colores', 'id', color['id'], color);

  Future<void> guardarProductos(
    Iterable<Map<String, Object?>> productos,
  ) async {
    for (final producto in productos) {
      await guardarProducto(producto);
    }
  }

  Future<void> guardarVariantes(
    Iterable<Map<String, Object?>> variantes,
  ) async {
    for (final variante in variantes) {
      await guardarVariante(variante);
    }
  }

  Future<void> guardarStock(Map<String, Object?> stock) async {
    final variante = stock['variante_id'];
    final sucursal = stock['sucursal_id'];
    final existentes = await db.query(
      'stock',
      where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[variante, sucursal, tenantId],
      limit: 1,
    );
    final datos = <String, Object?>{
      ...stock,
      'tenant_id': tenantId,
      'dispositivo_id': stock['dispositivo_id'],
      'usuario_id': stock['usuario_id'],
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    };
    if (existentes.isEmpty) {
      await db.insert('stock', datos);
    } else {
      await db.update(
        'stock',
        datos,
        where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
        whereArgs: <Object?>[variante, sucursal, tenantId],
      );
    }
  }

  Future<int> marcarProductoEliminado(int id) {
    return db.update(
      'productos',
      <String, Object?>{
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[id, tenantId],
    );
  }

  Future<int> marcarVarianteEliminada(int id) {
    return db.update(
      'variantes',
      <String, Object?>{
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[id, tenantId],
    );
  }

  Future<List<Map<String, Object?>>> listarProductos({
    int? categoriaId,
    String? busqueda,
    bool incluirEliminados = false,
  }) async {
    final condiciones = <String>['tenant_id = ?'];
    final argumentos = <Object?>[tenantId];
    if (categoriaId != null) {
      condiciones.add('categoria_id = ?');
      argumentos.add(categoriaId);
    }
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      condiciones.add('(nombre LIKE ? OR descripcion LIKE ?)');
      final patron = '%${busqueda.trim()}%';
      argumentos.addAll(<Object?>[patron, patron]);
    }
    if (!incluirEliminados) condiciones.add('deleted_at IS NULL');
    return consultar(
      'productos',
      where: condiciones.join(' AND '),
      whereArgs: argumentos,
      orderBy: 'nombre COLLATE NOCASE',
    );
  }

  Future<Map<String, Object?>?> obtenerProducto(int id) async {
    final filas = await consultar(
      'productos',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[id, tenantId],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  Future<List<Map<String, Object?>>> listarVariantesProducto(int productoId) {
    return consultar(
      'variantes',
      where: 'producto_id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[productoId, tenantId],
      orderBy: 'sku_variante',
    );
  }

  Future<List<Map<String, Object?>>> buscarVariantesSku(String texto) {
    final patron = '%${texto.trim()}%';
    return consultar(
      'variantes',
      where: 'sku_variante LIKE ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[patron, tenantId],
      orderBy: 'sku_variante',
    );
  }

  Future<List<Map<String, Object?>>> listarStock({int? sucursalId}) {
    if (sucursalId != null) {
      return consultar(
        'stock',
        where: 'sucursal_id = ? AND tenant_id = ?',
        whereArgs: <Object?>[sucursalId, tenantId],
      );
    }
    return consultar(
      'stock',
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantId],
    );
  }

  Future<List<Map<String, Object?>>> listarSucursales({
    bool soloActivas = false,
  }) {
    return consultar(
      'sucursales',
      where: soloActivas ? 'tenant_id = ? AND estado = ?' : 'tenant_id = ?',
      whereArgs: soloActivas
          ? <Object?>[tenantId, 'ACTIVA']
          : <Object?>[tenantId],
      orderBy: 'nombre COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> listarCategorias() => consultar(
    'categorias',
    where: 'tenant_id = ?',
    whereArgs: <Object?>[tenantId],
    orderBy: 'nombre COLLATE NOCASE',
  );
  Future<List<Map<String, Object?>>> listarTallas() => consultar(
    'tallas',
    where: 'tenant_id = ?',
    whereArgs: <Object?>[tenantId],
    orderBy: 'nombre COLLATE NOCASE',
  );
  Future<List<Map<String, Object?>>> listarColores() => consultar(
    'colores',
    where: 'tenant_id = ?',
    whereArgs: <Object?>[tenantId],
    orderBy: 'nombre COLLATE NOCASE',
  );
}
