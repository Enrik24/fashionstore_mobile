import 'dart:async';

import 'package:flutter/material.dart';

import '../services/realtime_service.dart';

/// Coordina el ciclo de vida de los canales y notifica eventos a la app.
class RealtimeProvider extends ChangeNotifier {
  RealtimeProvider({required RealtimeService service}) : _service = service {
    _subscription = _service.eventos.listen(_onEvent);
  }

  final RealtimeService _service;
  StreamSubscription<RealtimeEvent>? _subscription;
  final List<void Function(RealtimeEvent)> _listeners = [];

  bool get conectado => _service.estaConectado;

  void agregarEventoListener(void Function(RealtimeEvent) listener) =>
      _listeners.add(listener);

  void _onEvent(RealtimeEvent event) {
    for (final listener in List<void Function(RealtimeEvent)>.from(
      _listeners,
    )) {
      listener(event);
    }
    notifyListeners();
  }

  Future<void> iniciar() => _service.iniciar();
  Future<void> detener() => _service.detener();

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
