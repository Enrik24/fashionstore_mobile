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

  // ====================================================================
  // [EXAMEN-2] Fase 3 (CU13/CU18): operaciones offline del cliente/cajero.
  // No tocan la lista online; el detalle local se lee por uuid.
  // ====================================================================

  List<ReturnRequestModel> _localRequests = const [];

  List<ReturnRequestModel> get localRequests => _localRequests;

  /// CU13: crea una devolución pura offline y la antepone en local.
  Future<ReturnRequestModel?> crearDevolucionOffline({
    required String numeroComprobanteOrigen,
    int? ordenOrigenId,
    int? sucursalId,
    int? clienteId,
    String motivo = MotivosDevolucion.tallaIncorrecta,
    String? motivoDetalle,
    required List<LineaDevolucion> items,
    bool saldoFavor = false,
    DateTime? fechaCambioLimite,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final creada = await _service.crearDevolucionOffline(
        numeroComprobanteOrigen: numeroComprobanteOrigen,
        ordenOrigenId: ordenOrigenId,
        sucursalId: sucursalId,
        clienteId: clienteId,
        motivo: motivo,
        motivoDetalle: motivoDetalle,
        items: items,
        saldoFavor: saldoFavor,
        fechaCambioLimite: fechaCambioLimite,
      );
      _localRequests = [creada, ..._localRequests];
      return creada;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// CU18: crea una reposición offline.
  Future<ReturnRequestModel?> crearReposicionOffline({
    required String numeroComprobanteOrigen,
    int? ordenOrigenId,
    int? sucursalId,
    int? clienteId,
    String motivo = MotivosDevolucion.tallaIncorrecta,
    String? motivoDetalle,
    required List<LineaDevolucion> items,
    DateTime? fechaCambioLimite,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final creada = await _service.crearReposicionOffline(
        numeroComprobanteOrigen: numeroComprobanteOrigen,
        ordenOrigenId: ordenOrigenId,
        sucursalId: sucursalId,
        clienteId: clienteId,
        motivo: motivo,
        motivoDetalle: motivoDetalle,
        items: items,
        fechaCambioLimite: fechaCambioLimite,
      );
      _localRequests = [creada, ..._localRequests];
      return creada;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Alias legacy CAMBIO == reposición.
  Future<ReturnRequestModel?> crearCambioOffline({
    required String numeroComprobanteOrigen,
    int? ordenOrigenId,
    int? sucursalId,
    int? clienteId,
    String motivo = MotivosDevolucion.tallaIncorrecta,
    String? motivoDetalle,
    required List<LineaDevolucion> items,
    DateTime? fechaCambioLimite,
  }) => crearReposicionOffline(
    numeroComprobanteOrigen: numeroComprobanteOrigen,
    ordenOrigenId: ordenOrigenId,
    sucursalId: sucursalId,
    clienteId: clienteId,
    motivo: motivo,
    motivoDetalle: motivoDetalle,
    items: items,
    fechaCambioLimite: fechaCambioLimite,
  );

  Future<ReturnRequestModel?> getSolicitudDesdeLocal(String uuidOffline) =>
      _service.getSolicitudDesdeLocal(uuidOffline);
}
