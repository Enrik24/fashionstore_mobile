import 'package:flutter/material.dart';
import '../models/reservation_model.dart';
import '../services/reservation_service.dart';

class ReservationProvider extends ChangeNotifier {
  final ReservationService _reservationService;

  ReservationProvider({required ReservationService reservationService})
      : _reservationService = reservationService;

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
      _branches = await _reservationService.getSucursales();
      if (_branches.isNotEmpty && _selectedBranch == null) {
        _selectedBranch = _branches.first;
      }
    } catch (e) {
      // Fallback default branches in Santa Cruz if API returns empty/fails
      if (_branches.isEmpty) {
        _branches = [
          BranchModel(
            id: 1,
            nombre: 'Sucursal Ventura Mall',
            direccion: '4to Anillo, Ventura Mall, Piso 2, Santa Cruz',
            telefono: '+591 3 3888000',
            latitud: -17.7547,
            longitud: -63.1979,
            horarioApertura: '10:00',
            horarioCierre: '22:00',
          ),
          BranchModel(
            id: 2,
            nombre: 'Sucursal Las Brisas',
            direccion: 'Av. Banzer 4to Anillo, CC Las Brisas, Santa Cruz',
            telefono: '+591 3 3444000',
            latitud: -17.7582,
            longitud: -63.1764,
            horarioApertura: '10:00',
            horarioCierre: '22:00',
          ),
          BranchModel(
            id: 3,
            nombre: 'Sucursal Centro',
            direccion: 'Calle 21 de Mayo #120, Centro Histórico, Santa Cruz',
            telefono: '+591 3 3332211',
            latitud: -17.7833,
            longitud: -63.1821,
            horarioApertura: '09:00',
            horarioCierre: '20:00',
          ),
        ];
        _selectedBranch = _branches.first;
      }
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
