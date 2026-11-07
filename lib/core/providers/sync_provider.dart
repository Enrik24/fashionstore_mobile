import 'package:flutter/material.dart';

import '../models/phase2_models.dart';
import '../services/sync_engine_service.dart';

/// [EXAMEN-2] Estado del centro de sincronización (CU08/RF-030).
class SyncProvider extends ChangeNotifier {
  SyncProvider({required SyncEngineService service}) : _service = service;

  final SyncEngineService _service;
  SyncSummaryModel _summary = const SyncSummaryModel();
  bool _loading = false;
  int _enviando = 0;
  int _total = 0;
  String? _ultimoError;

  SyncSummaryModel get summary => _summary;
  bool get isLoading => _loading;
  bool get isSyncing => _service.estaSincronizando;
  int get pendingCount => _summary.pendientes;

  // [EXAMEN-2] C2.6 (§5.10, RF-030): progreso "Enviando N de M".
  double get progreso {
    if (_total <= 0) return _summary.pendientes == 0 ? 1.0 : 0.0;
    return (_enviando / _total).clamp(0.0, 1.0);
  }

  String get etiquetaProgreso => 'Enviando $_enviando de $_total';
  String? get ultimoError => _ultimoError ?? _summary.ultimoError;

  Future<void> cargarResumen() async {
    try {
      _summary = await _service.resumen();
      notifyListeners();
    } catch (_) {
      // El resumen es informativo; un fallo no debe impedir iniciar la app.
    }
  }

  Future<void> sincronizar() async {
    _loading = true;
    _ultimoError = null;
    _enviando = 0;
    _total = _summary.pendientes;
    notifyListeners();
    try {
      _summary = await _service.sincronizarAhora();
      _enviando = _total;
      _ultimoError = _summary.ultimoError;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // [EXAMEN-2] C2.6 CU09: reintento por ítem (POST /offline/operaciones/{uuid}/reintentar).
  Future<void> reintentarOperacion(String uuid) async {
    try {
      await _service.reintentar(uuid);
    } catch (e) {
      _ultimoError = e.toString();
    }
    await cargarResumen();
  }

  Future<void> refresh() async {
    _summary = await _service.sincronizarAhora();
    _ultimoError = _summary.ultimoError;
    notifyListeners();
  }
}
