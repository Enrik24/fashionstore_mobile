import '../../config/constants.dart';
import '../models/review_model.dart';
import 'api_service.dart';

/// Servicio de valoraciones de productos (CU26).
/// Sigue el patrón de [CartService]: HTTP delgado con `dio` vía [ApiService].
class ReviewService {
  final ApiService _apiService;

  ReviewService({required ApiService apiService}) : _apiService = apiService;

  /// `GET /productos/{id}/valoraciones` — público, paginado.
  Future<List<ReviewModel>> getProductReviews(
    int productoId, {
    int skip = 0,
    int limit = 20,
  }) async {
    try {
      final response = await _apiService.dio.get(
        '/productos/$productoId/valoraciones',
        queryParameters: {'skip': skip, 'limit': limit},
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) => ReviewModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `GET /productos/{id}/puede-valorar` — requiere sesión de Cliente.
  Future<CanReviewModel> canReview(int productoId) async {
    try {
      final response = await _apiService.dio.get(
        '/productos/$productoId/puede-valorar',
      );
      if (response.data is Map<String, dynamic>) {
        return CanReviewModel.fromJson(
            response.data as Map<String, dynamic>);
      }
      return CanReviewModel(puedeValorar: false, motivo: 'Sin información');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `GET /productos/{id}/mi-valoracion` — null si aún no valoró.
  Future<ReviewModel?> getMyReview(int productoId) async {
    try {
      final response = await _apiService.dio.get(
        '/productos/$productoId/mi-valoracion',
      );
      if (response.data is Map<String, dynamic>) {
        return ReviewModel.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      // 404 = sin valoración propia; no es un error para la UI.
      final err = _apiService.handleError(e);
      if (err.statusCode == 404) return null;
      throw err;
    }
  }

  /// `POST /productos/{id}/valoraciones` — 201.
  Future<ReviewModel> createReview(
    int productoId, {
    required int puntuacion,
    String? comentario,
  }) async {
    try {
      final response = await _apiService.dio.post(
        '/productos/$productoId/valoraciones',
        data: {
          'puntuacion': puntuacion,
          if (comentario != null && comentario.trim().isNotEmpty)
            'comentario': comentario.trim(),
        },
      );
      if (response.data is Map<String, dynamic>) {
        return ReviewModel.fromJson(response.data as Map<String, dynamic>);
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `PUT /valoraciones/{id}` — solo el autor.
  Future<ReviewModel> updateReview(
    int valoracionId, {
    int? puntuacion,
    String? comentario,
  }) async {
    try {
      final response = await _apiService.dio.put(
        '${AppConstants.epValoraciones}$valoracionId',
        data: {
          if (puntuacion != null) 'puntuacion': puntuacion,
          if (comentario != null) 'comentario': comentario.trim(),
        },
      );
      if (response.data is Map<String, dynamic>) {
        return ReviewModel.fromJson(response.data as Map<String, dynamic>);
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
