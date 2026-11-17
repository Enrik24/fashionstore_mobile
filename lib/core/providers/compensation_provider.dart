// [EXAMEN-2] CU19: estado de las compensaciones (solo modo cajero).
// `pendientesCount` y la confirmación de efectivo solo se exponen cuando el
// usuario tiene rol cajero/encargado (D-MOV-20).
import 'package:flutter/material.dart';

import '../models/compensation_model.dart';
import '../services/compensation_service.dart';

class CompensationProvider extends ChangeNotifier {
  CompensationProvider({
    required CompensationService service,
    required bool esCajero,
    int cajeroId = 0,
  }) : _service = service,
       _esCajero = esCajero,
       _cajeroId = cajeroId;

  final CompensationService _service;
  bool _esCajero;
  int _cajeroId;

  List<CompensacionModel> _compensaciones = const [];
  CompensacionModel? _detalleSeleccionado;
  Map<String, Object?> _resumen = const {};
  int _pendientes = 0;
  bool _loading = false;
  String? _error;
  // [EXAMEN-2] B1.9.f: la última carga fue **local** (sin conexión) ⇒ la app
  // queda en modo lectura: no se puede confirmar ni reintentar.
  bool _soloLectura = false;

  List<CompensacionModel> get compensaciones => _compensaciones;
  CompensacionModel? get detalleSeleccionado => _detalleSeleccionado;
  Map<String, Object?> get resumen => _resumen;
  int get pendientesCount => _esCajero ? _pendientes : 0;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  bool get esCajero => _esCajero;

  /// [EXAMEN-2] B1.9.g: sin conexión sólo se consulta la caché local.
  bool get soloLectura => _soloLectura;

  void setCajero(bool value, int cajeroId) {
    _esCajero = value;
    _cajeroId = cajeroId;
    notifyListeners();
  }

  /// Recarga el listado (cache local + refresco remoto si hay red).
  ///
  /// [EXAMEN-2] B1.9.f: con `remoto: false` se lee **sólo** la caché local
  /// (modo lectura sin conexión, per CU19).
  Future<void> load({bool remoto = true}) async {
    if (!_esCajero) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (remoto) {
        _compensaciones = await _service.listar();
        _resumen = await _service.resumen();
        _soloLectura = false;
      } else {
        _compensaciones = await _service.listarLocal();
        _resumen = await _service.resumenLocal();
        _soloLectura = true;
      }
      _pendientes = await _service.pendientesCount();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> seleccionar(int id) async {
    _detalleSeleccionado = await _service.detalle(id);
    notifyListeners();
  }

  /// Confirma el efectivo; solo modo cajero, nunca por pasarela.
  Future<bool> confirmarEfectivo(int id) async {
    if (!_esCajero) {
      _error = 'Solo el modo cajero puede confirmar el efectivo';
      notifyListeners();
      return false;
    }
    // [EXAMEN-2] B1.9.g: sin conexión no se puede confirmar (la entrega en
    // caja requiere registrar el estado en el servidor).
    if (_soloLectura) {
      _error = 'Sin conexión: la confirmación se habilitará al reconectar.';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final confirmada = await _service.confirmarEfectivo(
        id,
        esCajero: true,
        cajeroId: _cajeroId,
      );
      _detalleSeleccionado = confirmada;
      _compensaciones = await _service.listar();
      _pendientes = await _service.pendientesCount();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// [EXAMEN-2] B1.9.a: reintenta el reembolso por pasarela (lo ejecuta el
  /// backend). Sólo con conexión.
  Future<bool> reintentar(int id) async {
    if (!_esCajero) {
      _error = 'Solo el modo cajero puede reintentar el reembolso';
      notifyListeners();
      return false;
    }
    if (_soloLectura) {
      _error = 'Sin conexión: el reintento se habilitará al reconectar.';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final modelo = await _service.reintentar(id);
      _detalleSeleccionado = modelo;
      _compensaciones = await _service.listar();
      _pendientes = await _service.pendientesCount();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Refresca el resumen y los pendientes sin cambiar el listado.
  Future<void> refrescarResumen() async {
    if (!_esCajero) return;
    _resumen = await _service.resumen();
    _pendientes = await _service.pendientesCount();
    notifyListeners();
  }
}
