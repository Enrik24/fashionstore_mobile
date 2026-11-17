import 'package:flutter/material.dart';
import '../models/reservation_model.dart';
import '../services/reservation_service.dart';

class ReservationProvider extends ChangeNotifier {
  final ReservationService _reservationService;

  ReservationProvider({required ReservationService reservationService})
    : _reservationService = reservationService {
    loadReservations();
  }

  List<ReservationModel> _reservations = [];
  List<BranchModel> _branches = [];
  BranchModel? _selectedBranch;
  bool _isLoading = false;
  bool _isLoadingBranches = false;
  bool _isCreating = false;
  String? _errorMessage;

  List<ReservationModel> get reservations => _reservations;
  List<BranchModel> get branches => _branches;
  BranchModel? get selectedBranch => _selectedBranch;
  bool get isLoading => _isLoading;
  bool get isLoadingBranches => _isLoadingBranches;
  bool get isCreating => _isCreating;
  String? get errorMessage => _errorMessage;

  Future<void> loadReservations() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _reservations = await _reservationService.getReservas();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBranches() async {
    _isLoadingBranches = true;
    notifyListeners();

    try {
      // [FIX] Antes, al fallar el API se inyectaban 3 sucursales
      // hardcodeadas (Ventura Mall/Las Brisas/Centro) y el usuario veía esa
      // lista ficticia en "Retiro en Tienda" aunque hubiera conexión. Ahora
      // `getSucursales` degrada solo a las sucursales REALES descargadas
      // (tabla local `sucursales`); si no hay datos, la UI muestra su aviso.
      _branches = await _reservationService.getSucursales();
      if (_branches.isNotEmpty && _selectedBranch == null) {
        _selectedBranch = _branches.first;
      }
    } catch (_) {
      _branches = const <BranchModel>[];
    } finally {
      _isLoadingBranches = false;
      notifyListeners();
    }
  }

  void selectBranch(BranchModel branch) {
    _selectedBranch = branch;
    notifyListeners();
  }

  Future<ReservationModel?> createReservation({
    required int sucursalId,
    required DateTime fechaReserva,
    String? horarioAproximado,
    String? notas,
    required List<Map<String, dynamic>> items,
    // [EXAMEN-2] B1.2.c/d: el cajero forzó la reserva porque el stock local
    // no alcanzaba; queda marcada para revisión del servidor (RN-006).
    bool forzar = false,
  }) async {
    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newReservation = await _reservationService.crearReserva(
        sucursalId: sucursalId,
        fechaReserva: fechaReserva,
        horarioAproximado: horarioAproximado,
        notas: notas,
        items: items,
        forzar: forzar,
      );
      _reservations.insert(0, newReservation);
      _isCreating = false;
      notifyListeners();
      return newReservation;
    } catch (e) {
      _errorMessage = e.toString();
      _isCreating = false;
      notifyListeners();
      return null;
    }
  }

  Future<ReservationModel?> getReservationDetail(int id) async {
    try {
      return await _reservationService.getReservaDetalle(id);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> cancelReservation(int id) async {
    try {
      await _reservationService.cancelarReserva(id);
      await loadReservations();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
}
