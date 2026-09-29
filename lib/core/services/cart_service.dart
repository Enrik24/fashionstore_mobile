import '../../config/constants.dart';
import '../models/cart_model.dart';
import 'api_service.dart';

class CartService {
  final ApiService _apiService;

  CartService({required ApiService apiService}) : _apiService = apiService;

  Future<CartModel> getCarrito() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epCarrito);
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return CartModel.empty();
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<CartModel> addItem({
    required int varianteProductoId,
    required int cantidad,
  }) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epCarritoItems,
        data: {
          'variante_producto_id': varianteProductoId,
          'cantidad': cantidad,
        },
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return await getCarrito();
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<CartModel> updateItem({
    required int itemId,
    required int cantidad,
  }) async {
    try {
      final response = await _apiService.dio.put(
        '${AppConstants.epCarritoItems}/$itemId',
        data: {'cantidad': cantidad},
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return await getCarrito();
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<void> removeItem(int itemId) async {
    try {
      await _apiService.dio.delete('${AppConstants.epCarritoItems}/$itemId');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<void> clearCart() async {
    try {
      await _apiService.dio.delete(AppConstants.epCarrito);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `POST /carrito/aplicar-cupon` (CU27).
  Future<CartModel> applyCoupon(String codigo) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epCarritoAplicarCupon,
        data: {'codigo': codigo.trim().toUpperCase()},
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return await getCarrito();
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `DELETE /carrito/remover-cupon` (CU27).
  Future<CartModel> removeCoupon() async {
    try {
      final response = await _apiService.dio.delete(
        AppConstants.epCarritoRemoverCupon,
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return await getCarrito();
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
