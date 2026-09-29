import 'package:flutter/material.dart';
import '../models/promotion_model.dart';
import '../services/promotion_service.dart';

/// Promociones activas en memoria (espejo de `ActivePromotionsService` web).
///
/// Se carga una sola vez y los cards consultan el descuento aplicable por
/// producto/categoría. Solo informativo: el backend no descuenta promos en
/// el carrito automáticamente.
class PromotionsProvider extends ChangeNotifier {
  final PromotionService _service;

  PromotionsProvider({required PromotionService promotionService})
      : _service = promotionService;

  List<PromotionModel> _promociones = [];
  bool _loaded = false;
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  bool get isLoaded => _loaded;
  bool get hasPromotions => _promociones.isNotEmpty;

  /// Carga las promociones una sola vez (llamadas extra se ignoran).
  Future<void> load() async {
    if (_loaded || _isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      _promociones = await _service.getPromocionesActivas();
    } catch (_) {
      _promociones = [];
    } finally {
      _loaded = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Mayor % de descuento aplicable (producto directo o por categoría).
  double? getDiscountForProduct(int productoId, int? categoriaId) {
    double? maxDescuento;
    for (final promo in _promociones) {
      if (!promo.isPorcentaje) continue;
      final valor = promo.valor ?? 0;
      final aplicaProducto = promo.productoIds.contains(productoId);
      final aplicaCategoria = categoriaId != null &&
          promo.categoriaIds.contains(categoriaId);
      if (aplicaProducto || aplicaCategoria) {
        if (maxDescuento == null || valor > maxDescuento) {
          maxDescuento = valor;
        }
      }
    }
    return maxDescuento;
  }

  bool has2x1(int productoId, int? categoriaId) {
    return _promociones.any((p) {
      if (!p.is2x1) return false;
      return p.productoIds.contains(productoId) ||
          (categoriaId != null &&
              p.categoriaIds.contains(categoriaId));
    });
  }

  /// Precio con el mejor descuento aplicado (si hay).
  double precioConDescuento(
      int productoId, int? categoriaId, double precioBase) {
    final d = getDiscountForProduct(productoId, categoriaId);
    if (d == null) return precioBase;
    return precioBase * (1 - d / 100);
  }
}
