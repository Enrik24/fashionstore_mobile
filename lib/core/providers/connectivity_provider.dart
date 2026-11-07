import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/connectivity_service.dart';

/// [EXAMEN-2] Estado de conectividad para la interfaz de CU17.
class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider(this._service);

  final ConnectivityService _service;
  StreamSubscription<bool>? _subscription;

  bool get estaEnLinea => _service.estaEnLinea;
  DateTime? get ultimaVerificacion => _service.ultimaVerificacion;

  Future<void> initialize() async {
    await _service.verificarServidor();
    await _service.observarCambios();
    _subscription = _service.cambios.listen((_) => notifyListeners());
    notifyListeners();
  }

  Future<void> refrescar() async {
    await _service.verificarServidor();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    super.dispose();
  }
}
