import '../../config/constants.dart';
import '../models/return_request_model.dart';
import 'api_service.dart';

/// Item para crear una solicitud (`ItemSolicitudDevolucionCreate` del backend).
class ReturnItemCreate {
  final int detalleOrdenId;
  final int cantidad;
  final int? varianteCambioId;

  ReturnItemCreate({
    required this.detalleOrdenId,
    this.cantidad = 1,
    this.varianteCambioId,
  });

  Map<String, dynamic> toJson() {
    return {
      'detalle_orden_id': detalleOrdenId,
      'cantidad': cantidad,
      if (varianteCambioId != null) 'variante_cambio_id': varianteCambioId,
    };
  }
}

/// Servicio de devoluciones y cambios del cliente (CU28).
/// Sigue el patrón de [CartService]: HTTP delgado con `dio` vía [ApiService].
class ReturnService {
  final ApiService _apiService;

  ReturnService({required ApiService apiService}) : _apiService = apiService;

  /// `POST /devoluciones/` — 201.
  Future<ReturnRequestModel> crearSolicitud({
    required int ordenId,
    int? sucursalId,
    required String tipo,
    required String motivo,
    String? motivoDetalle,
    required List<ReturnItemCreate> items,
  }) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epDevoluciones,
        data: {
          'orden_id': ordenId,
          if (sucursalId != null) 'sucursal_id': sucursalId,
          'tipo': tipo.toUpperCase(),
          'motivo': motivo.toUpperCase(),
          if (motivoDetalle != null && motivoDetalle.trim().isNotEmpty)
            'motivo_detalle': motivoDetalle.trim(),
          'items': items.map((e) => e.toJson()).toList(),
        },
      );
      if (response.data is Map<String, dynamic>) {
        return ReturnRequestModel.fromJson(
            response.data as Map<String, dynamic>);
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `GET /devoluciones/mis-solicitudes`.
  Future<List<ReturnRequestModel>> getMisSolicitudes({
    int skip = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _apiService.dio.get(
        AppConstants.epMisDevoluciones,
        queryParameters: {'skip': skip, 'limit': limit},
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) => ReturnRequestModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `GET /devoluciones/{id}` — la propia (el backend valida el propietario).
  Future<ReturnRequestModel> getSolicitud(int solicitudId) async {
    try {
      final response = await _apiService.dio.get(
        '${AppConstants.epDevoluciones}$solicitudId',
      );
      if (response.data is Map<String, dynamic>) {
        return ReturnRequestModel.fromJson(
            response.data as Map<String, dynamic>);
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
