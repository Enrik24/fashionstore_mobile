import 'package:flutter/material.dart';
import '../models/return_request_model.dart';
import '../services/return_service.dart';

/// Estado de devoluciones del cliente (CU28).
class ReturnProvider extends ChangeNotifier {
  final ReturnService _service;

  ReturnProvider({required ReturnService returnService})
      : _service = returnService;

  List<ReturnRequestModel> _requests = [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<ReturnRequestModel> get requests => _requests;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  /// `GET /devoluciones/mis-solicitudes`.
  Future<void> loadMyRequests({bool refresh = false}) async {
    if (!refresh && _requests.isNotEmpty) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _requests = await _service.getMisSolicitudes();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// `POST /devoluciones/` — retorna la solicitud creada o null.
  Future<ReturnRequestModel?> createRequest({
    required int ordenId,
    int? sucursalId,
    required String tipo,
    required String motivo,
    String? motivoDetalle,
    required List<ReturnItemCreate> items,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final created = await _service.crearSolicitud(
        ordenId: ordenId,
        sucursalId: sucursalId,
        tipo: tipo,
        motivo: motivo,
        motivoDetalle: motivoDetalle,
        items: items,
      );
      _requests = [created, ..._requests];
      _isSubmitting = false;
      notifyListeners();
      return created;
    } catch (e) {
      _errorMessage = e.toString();
      _isSubmitting = false;
      notifyListeners();
      return null;
    }
  }

  /// Recarga una solicitud puntual (para ver cambios de estado del staff).
  Future<ReturnRequestModel?> refreshRequest(int solicitudId) async {
    try {
      final updated = await _service.getSolicitud(solicitudId);
      final idx = _requests.indexWhere((r) => r.id == solicitudId);
      if (idx >= 0) {
        _requests[idx] = updated;
      } else {
        _requests = [updated, ..._requests];
      }
      notifyListeners();
      return updated;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  void clearState() {
    _requests = [];
    _errorMessage = null;
    notifyListeners();
  }
}
