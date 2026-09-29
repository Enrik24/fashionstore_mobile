import '../../config/constants.dart';
import '../models/promotion_model.dart';
import 'api_service.dart';

/// Servicio de promociones públicas (solo lectura, sin auth).
/// Backend: `GET /public/promociones/activas`.
class PromotionService {
  final ApiService _apiService;

  PromotionService({required ApiService apiService})
      : _apiService = apiService;

  Future<List<PromotionModel>> getPromocionesActivas() async {
    try {
      final response = await _apiService.dio.get(
        AppConstants.epPromocionesActivas,
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) => PromotionModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
