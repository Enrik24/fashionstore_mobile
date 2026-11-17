import 'package:flutter/material.dart';

import '../models/phase2_models.dart';
import '../services/sync_engine_service.dart';
import '../utils/sync_messages.dart';

/// [EXAMEN-2] Estado del centro de sincronización (CU08/RF-030).
class SyncProvider extends ChangeNotifier {
  SyncProvider({required SyncEngineService service}) : _service = service;

  final SyncEngineService _service;
  SyncSummaryModel _summary = const SyncSummaryModel();
  bool _loading = false;
  int _enviando = 0;
  int _total = 0;
  String? _ultimoError;
  // [EXAMEN-2] B2.1: operaciones pendientes (para la cola con reintento).
  List<OfflineOperationModel> _pendientes = const [];

  /// [EXAMEN-2] B2.1: operaciones en cola pendientes de enviar.
  List<OfflineOperationModel> get pendientes => _pendientes;

  SyncSummaryModel get summary => _summary;
  bool get isLoading => _loading;
  bool get isSyncing => _service.estaSincronizando;
  int get pendingCount => _summary.pendientes;

  /// [EXAMEN-2] B1.8.c: fecha de la última sincronización efectiva.
  DateTime? _ultimaSincronizacion;
  DateTime? get ultimaSincronizacion => _ultimaSincronizacion;

  /// [EXAMEN-2] B1.4.a: resumen de la última sincronización.
  String? _mensajeSincronizacion;
  String? get mensajeSincronizacion => _mensajeSincronizacion;

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
      // [EXAMEN-2] B1.8.c: se carga también la fecha de la última
      // sincronización para el banner offline.
      _ultimaSincronizacion = await _service.ultimaSincronizacion();
      // [EXAMEN-2] B2.1: la cola de pendientes alimenta la tarjeta de
      // reintento por ítem del centro de sincronización.
      _pendientes = await _service.pendientes();
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
    _mensajeSincronizacion = null;
    notifyListeners();
    try {
      // [EXAMEN-2] Con la cola vacía no hay nada que enviar: se informa al
      // usuario en lugar de parecer un botón sin efecto.
      final enCola = await _service.pendientes();
      if (enCola.isEmpty) {
        _summary = await _service.resumen();
        _mensajeSincronizacion = 'No hay operaciones pendientes de sincronizar.';
        return;
      }
      _total = enCola.length;
      _summary = await _service.sincronizarAhora();
      _enviando = _total;
      _ultimoError = _summary.ultimoError;
      // [EXAMEN-2] B1.4.a: mensaje de resumen del spec ("Sincronización
      // completa: X confirmadas, Y rechazadas"). El helper existía en
      // `SyncMessages` pero **nunca se invocaba**.
      _mensajeSincronizacion = SyncMessages.mensajeSincronizacion(
        confirmadas: _summary.confirmadas,
        rechazadas: _summary.rechazadas,
        // [BUG-SYNC] si tras sincronizar quedan operaciones pendientes el
        // mensaje debe reflejarlo (antes decía "completa" con pendientes).
        pendientes: _summary.pendientes,
      );
      _ultimaSincronizacion = await _service.ultimaSincronizacion();
    } finally {
      // Refresca contadores y la cola mostrada (SyncQueueCard) tras enviar.
      await cargarResumen();
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
