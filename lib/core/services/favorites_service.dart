import '../../config/constants.dart';
import '../models/cart_model.dart';
import '../models/favorite_model.dart';
import 'api_service.dart';

/// Servicio de favoritos (CU25).
/// Sigue el patrón de [CartService]: HTTP delgado con `dio` vía [ApiService].
class FavoritesService {
  final ApiService _apiService;

  FavoritesService({required ApiService apiService}) : _apiService = apiService;

  /// `GET /favoritos/` — lista completa con producto y disponibilidad.
  Future<List<FavoriteModel>> getFavoritos({
    int skip = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _apiService.dio.get(
        AppConstants.epFavoritos,
        queryParameters: {'skip': skip, 'limit': limit},
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) => FavoriteModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `GET /favoritos/ids` — solo IDs (una llamada para marcar corazones).
  Future<Set<int>> getFavoritoIds() async {
    try {
      final response =
          await _apiService.dio.get(AppConstants.epFavoritosIds);
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final ids = data['producto_ids'];
        if (ids is List) {
          return ids
              .map((e) => e is int ? e : int.tryParse(e.toString()) ?? -1)
              .where((e) => e >= 0)
              .toSet();
        }
      } else if (data is List) {
        return data
            .map((e) => e is int ? e : int.tryParse(e.toString()) ?? -1)
            .where((e) => e >= 0)
            .toSet();
      }
      return {};
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `POST /favoritos/{producto_id}` — idempotente en el backend.
  Future<FavoriteModel> agregar(int productoId) async {
    try {
      final response = await _apiService.dio.post(
        '${AppConstants.epFavoritos}$productoId',
      );
      if (response.data is Map<String, dynamic>) {
        return FavoriteModel.fromJson(
            response.data as Map<String, dynamic>);
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `DELETE /favoritos/{producto_id}` — idempotente en el backend.
  Future<void> quitar(int productoId) async {
    try {
      await _apiService.dio.delete(
        '${AppConstants.epFavoritos}$productoId',
      );
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `POST /favoritos/{producto_id}/mover-al-carrito`.
  Future<CartModel> moverAlCarrito({
    required int productoId,
    required int varianteProductoId,
    int cantidad = 1,
    bool quitarDeFavoritos = false,
  }) async {
    try {
      final response = await _apiService.dio.post(
        '${AppConstants.epFavoritos}$productoId/mover-al-carrito',
        data: {
          'variante_producto_id': varianteProductoId,
          'cantidad': cantidad,
          'quitar_de_favoritos': quitarDeFavoritos,
        },
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
