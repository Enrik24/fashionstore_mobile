import 'dart:async';

import 'package:flutter/material.dart';

import '../models/phase2_models.dart';
import '../services/pending_payment_service.dart';

/// [EXAMEN-2] Pagos diferidos y cuenta regresiva (CU16).
class PendingPaymentProvider extends ChangeNotifier {
  PendingPaymentProvider({required PendingPaymentService service})
    : _service = service {
    _subscription = _service.eventos.listen((_) => load());
  }

  final PendingPaymentService _service;
  StreamSubscription<PendingPaymentModel>? _subscription;
  List<PendingPaymentModel> _payments = const [];
  bool _loading = false;
  String? _error;

  List<PendingPaymentModel> get payments => _payments;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  int get pendingCount => _payments.where((p) => p.estaPendiente).length;
  double get pendingAmount => _payments
      .where((p) => p.estaPendiente)
      .fold<double>(0, (sum, p) => sum + p.monto);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _payments = await _service.pendientes();
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> confirm(String uuid) async {
    await _service.confirmarPago(uuid);
    await load();
  }

  Future<void> retry(String uuid) async {
    await _service.reintentarPago(uuid);
    await load();
  }

  Future<String?> prepararPaymentSheet(String uuid) async {
    final secret = await _service.prepararPaymentSheet(uuid);
    notifyListeners();
    return secret;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
