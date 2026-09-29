import '../../config/constants.dart';
import '../models/cart_model.dart';
import '../models/coupon_model.dart';
import 'api_service.dart';

/// Servicio de cupones del cliente (CU27).
/// Sigue el patrón de [CartService]: HTTP delgado con `dio` vía [ApiService].
class CouponService {
  final ApiService _apiService;

  CouponService({required ApiService apiService}) : _apiService = apiService;

  /// `GET /cupones/disponibles` — cupones vigentes para el cliente.
  Future<List<CouponModel>> getDisponibles() async {
    try {
      final response = await _apiService.dio.get(
        AppConstants.epCuponesDisponibles,
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) => CouponModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `POST /cupones/validar` — validación fina con items del carrito.
  Future<CouponValidationResult> validarCupon(
    String codigo, {
    double? subtotal,
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epCuponesValidar,
        data: {
          'codigo': codigo.trim().toUpperCase(),
          if (subtotal != null) 'subtotal': subtotal,
          if (items != null && items.isNotEmpty) 'items': items,
        },
      );
      if (response.data is Map<String, dynamic>) {
        return CouponValidationResult.fromJson(
            response.data as Map<String, dynamic>);
      }
      return CouponValidationResult(
          valido: false, mensaje: 'Respuesta inesperada del servidor');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `POST /carrito/aplicar-cupon` — aplica y devuelve el carrito recalculado.
  Future<CartModel> aplicarCupon(String codigo) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epCarritoAplicarCupon,
        data: {'codigo': codigo.trim().toUpperCase()},
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `DELETE /carrito/remover-cupon` — quita el cupón y recalcula.
  Future<CartModel> removerCupon() async {
    try {
      final response = await _apiService.dio.delete(
        AppConstants.epCarritoRemoverCupon,
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
