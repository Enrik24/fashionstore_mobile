import 'package:flutter/foundation.dart';

import '../models/api_response.dart';
import '../services/offline_session_service.dart';

/// [EXAMEN-2] Estado de sesión offline de CU17.
class OfflineSessionProvider extends ChangeNotifier {
  OfflineSessionProvider(this._service);

  final OfflineSessionService _service;
  bool _cargando = false;
  String? _error;
  bool _sesionLocalActiva = false;

  bool get cargando => _cargando;
  String? get error => _error;
  bool get pinConfigurado => _service.pinConfigurado;
  bool get haySesionValida => _service.haySesionValida;
  // [EXAMEN-2] C1.2: sesión guardada pero vencida => solo consulta.
  bool get sesionVencida => _service.sesionVencida;
  int get intentosRestantes => _service.intentosRestantes;
  Duration get tiempoRestante => _service.tiempoRestante;
  DateTime? get expiraEn => _service.expiraEn;
  bool get sesionLocalActiva => _sesionLocalActiva;

  Future<void> initialize() async {
    await _service.initialize();
    notifyListeners();
  }

  // [EXAMEN-2] C1.2: página->provider->servicio (no servicio directo).
  Future<bool> configurarPin({
    required String pin,
    required String contrasenaActual,
  }) async {
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _service.configurarPin(
        pin: pin,
        contrasenaActual: contrasenaActual,
      );
      _cargando = false;
      notifyListeners();
      return ok;
    } on ApiException catch (error) {
      _error = error.message;
      _cargando = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> renovarToken() async {
    final ok = await _service.renovarToken();
    notifyListeners();
    return ok;
  }

  Future<void> cerrarSesionOffline() async {
    await _service.cerrarSesionOffline();
    _sesionLocalActiva = false;
    notifyListeners();
  }

  Future<bool> iniciar(String pin) async {
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _service.iniciarSesionOffline(pin);
      // [EXAMEN-2] C1.2: sesión vencida no activa modo operativo.
      _sesionLocalActiva = ok && _service.haySesionValida;
      _cargando = false;
      notifyListeners();
      return _sesionLocalActiva;
    } on ApiException catch (error) {
      _error = error.message;
      _sesionLocalActiva = false;
      _cargando = false;
      notifyListeners();
      return false;
    }
  }

  void limpiarError() {
    _error = null;
    notifyListeners();
  }
}
