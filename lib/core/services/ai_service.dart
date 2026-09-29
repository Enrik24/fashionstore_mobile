import '../../config/constants.dart';
import '../models/ai_model.dart';
import 'api_service.dart';

class AiService {
  final ApiService _apiService;

  AiService({required ApiService apiService}) : _apiService = apiService;

  Future<RecomendacionResponse> getRecomendaciones({
    int? clienteId,
    String? preferencias,
    int limite = 5,
  }) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epInteligenciaRecomendaciones,
        data: {
          if (clienteId != null) 'cliente_id': clienteId,
          if (preferencias != null && preferencias.isNotEmpty) 'preferencias': preferencias,
          'limite': limite,
        },
      );
      return RecomendacionResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<AsistenteChatResponse> chatAsistente({
    required String mensaje,
    List<ChatMessage> historial = const [],
    String? categoriaInteres,
  }) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epInteligenciaAsistente,
        data: {
          'mensaje': mensaje,
          'historial': historial.map((m) => m.toJson()).toList(),
          if (categoriaInteres != null && categoriaInteres.isNotEmpty)
            'categoria_interes': categoriaInteres,
        },
      );
      return AsistenteChatResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<VestidorVirtualResponse> vestidorVirtual({
    required int productoId,
    int? varianteId,
    String? imagenUsuarioBase64,
    String? imagenUsuarioUrl,
  }) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epVestidorVirtual,
        data: {
          'producto_id': productoId,
          if (varianteId != null) 'variante_id': varianteId,
          if (imagenUsuarioBase64 != null) 'imagen_usuario_base64': imagenUsuarioBase64,
          if (imagenUsuarioUrl != null) 'imagen_usuario_url': imagenUsuarioUrl,
        },
      );
      return VestidorVirtualResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<TendenciasResponse> getTendencias() async {
    try {
      final response = await _apiService.dio.get(
        AppConstants.epInteligenciaTendencias,
      );
      return TendenciasResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
