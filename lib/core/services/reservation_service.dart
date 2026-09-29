import 'package:intl/intl.dart';
import '../../config/constants.dart';
import '../models/reservation_model.dart';
import 'api_service.dart';

class ReservationService {
  final ApiService _apiService;

  ReservationService({required ApiService apiService}) : _apiService = apiService;

  Future<List<ReservationModel>> getReservas() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epMisReservas);
      if (response.data is List) {
        return (response.data as List)
            .map((item) => ReservationModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map && response.data['items'] != null) {
        return (response.data['items'] as List)
            .map((item) => ReservationModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<ReservationModel> getReservaDetalle(int id) async {
    try {
      final response = await _apiService.dio.get('${AppConstants.epReservas}$id');
      return ReservationModel.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<ReservationModel> crearReserva({
    required int sucursalId,
    required DateTime fechaReserva,
    String? horarioAproximado,
    String? notas,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(fechaReserva);
      // The backend expects a valid time (HH:MM) in horario_aproximado.
      // The UI sends a human label like '15:00 - 18:00 (Tarde)', so we extract
      // the start time and also use it to build the full datetime for fecha_reserva.
      final startTime = (horarioAproximado != null && horarioAproximado.isNotEmpty)
          ? horarioAproximado.split(' ').first
          : '12:00';
      final payload = {
        'sucursal_id': sucursalId,
        'fecha_reserva': '${formattedDate}T$startTime:00',
        if (horarioAproximado != null && horarioAproximado.isNotEmpty)
          'horario_aproximado': startTime,
        if (notas != null && notas.isNotEmpty) 'notas': notas,
        'detalles': items,
      };

      final response = await _apiService.dio.post(
        AppConstants.epReservas,
        data: payload,
      );

      return ReservationModel.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<void> cancelarReserva(int id) async {
    try {
      await _apiService.dio.post(
        '${AppConstants.epReservas}$id/cancelar',
      );
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<BranchModel>> getSucursales() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epSucursales);
      if (response.data is List) {
        return (response.data as List)
            .map((item) => BranchModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map && response.data['items'] != null) {
        return (response.data['items'] as List)
            .map((item) => BranchModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
