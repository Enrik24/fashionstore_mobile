/// [EXAMEN-2] B0.2 (Plan de cierre de brechas, Ola 1).
///
/// Mapper **compartido** del stock local por variante. Antes de esta tarea el
/// stock referencial se calculaba en un único lugar (`OfflineCatalogService`),
/// por lo que el POS (`PosService.buscarVarianteLocal`) y el carrito
/// (`CartService`) recibían variantes **sin** `stock_total` y caían al
/// valor por defecto `0` de `VarianteProducto.fromJson`.
///
/// Regla de cálculo (idéntica a `ReturnService._stockDisponible`):
/// `disponible = cantidad - cantidad_reservada`.
library;

/// Utilidad sin estado para enrichir variantes con el stock local conocido.
class VariantStockMapper {
  const VariantStockMapper._();

  /// Agrupa el stock local por variante y sucursal.
  ///
  /// [stock] son filas crudas de la tabla `stock` (`variante_id`,
  /// `sucursal_id`, `cantidad`, `cantidad_reservada`).
  ///
  /// Devuelve `varianteId -> {sucursalId: disponible}`.
  static Map<int, Map<int, int>> porSucursal(
    List<Map<String, Object?>> stock,
  ) {
    final resultado = <int, Map<int, int>>{};
    for (final fila in stock) {
      final varianteId = (fila['variante_id'] as num?)?.toInt();
      final sucursalId = (fila['sucursal_id'] as num?)?.toInt();
      if (varianteId == null || sucursalId == null) continue;
      final cantidad = (fila['cantidad'] as num?)?.toInt() ?? 0;
      final reservada = (fila['cantidad_reservada'] as num?)?.toInt() ?? 0;
      final disponible = cantidad - reservada;
      (resultado[varianteId] ??= <int, int>{})[sucursalId] = disponible;
    }
    return resultado;
  }

  /// Enriquece cada variante con `stock_total` y `stock_por_sucursal`.
  ///
  /// - `stock_total` es el disponible **total** (suma de todas las sucursales).
  /// - `stock_por_sucursal` es el disponible por sucursal.
  ///
  /// Cuando la variante **no** tiene fila de stock, se marca
  /// `stock_conocido = false` para que la UI pueda distinguir
  /// "sin stock" (0) de "sin dato" (desconocido) — B0.2.c.
  static List<Map<String, Object?>> enriquecer(
    List<Map<String, Object?>> variantes,
    List<Map<String, Object?>> stock,
  ) {
    final stockPorVariante = porSucursal(stock);
    return variantes.map((variante) {
      final varianteId = (variante['id'] as num?)?.toInt();
      final porSucursalVariante =
          varianteId == null
              ? <int, int>{}
              : (stockPorVariante[varianteId] ?? <int, int>{});
      final total = porSucursalVariante.values.fold<int>(0, (a, b) => a + b);
      return <String, Object?>{
        ...variante,
        'stock_total': total,
        'stock_por_sucursal': porSucursalVariante,
        'stock_conocido':
            varianteId != null && stockPorVariante.containsKey(varianteId),
      };
    }).toList(growable: false);
  }

  /// Disponible de una variante en una sucursal concreta.
  static int disponibleEnSucursal(
    List<Map<String, Object?>> stock,
    int varianteId,
    int sucursalId,
  ) {
    for (final fila in stock) {
      if ((fila['variante_id'] as num?)?.toInt() != varianteId) continue;
      if ((fila['sucursal_id'] as num?)?.toInt() != sucursalId) continue;
      final cantidad = (fila['cantidad'] as num?)?.toInt() ?? 0;
      final reservada = (fila['cantidad_reservada'] as num?)?.toInt() ?? 0;
      return cantidad - reservada;
    }
    return 0;
  }
}
