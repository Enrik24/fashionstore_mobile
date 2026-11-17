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

  /// [EXAMEN-2] B1.7.c: confirma el pago diferido. Devuelve `true` si se
  /// confirmó (antes devolvía `void` y la UI no podía informar).
  Future<bool> confirm(String uuid) async {
    try {
      await _service.confirmarPago(uuid);
      await load();
      _error = null;
      return true;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  /// [EXAMEN-2] B1.7.c: reintenta el pago diferido.
  Future<bool> retry(String uuid) async {
    try {
      await _service.reintentarPago(uuid);
      await load();
      _error = null;
      return true;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  /// Prepara el cobro: PaymentSheet nativo o redirección al checkout de Stripe.
  Future<PreparacionPago> prepararPago(String uuid) async {
    final preparacion = await _service.prepararPago(uuid);
    notifyListeners();
    return preparacion;
  }

  Future<String?> prepararPaymentSheet(String uuid) async {
    final secret = await _service.prepararPaymentSheet(uuid);
    notifyListeners();
    return secret;
  }

  void olvidarClientSecret(String uuid) => _service.olvidarClientSecret(uuid);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
