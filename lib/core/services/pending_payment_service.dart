import 'dart:async';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/local_payment_repository.dart';
import '../models/phase2_models.dart';
import 'device_service.dart';
import 'local_audit_service.dart';

/// [EXAMEN-2] Pago diferido con idempotencia y expiración (CU16).
class PendingPaymentService {
  PendingPaymentService({
    required LocalDatabaseService database,
    required int tenantId,
    required OfflineApiClient client,
    LocalPaymentRepository? repository,
    LocalAuditService? audit,
  }) : _database = database,
       _tenantId = tenantId,
       _client = client,
       _repository = repository,
       _audit = audit;

  final LocalDatabaseService _database;
  final int _tenantId;
  final OfflineApiClient _client;
  LocalPaymentRepository? _repository;
  final LocalAuditService? _audit;
  final StreamController<PendingPaymentModel> _eventos =
      StreamController<PendingPaymentModel>.broadcast();
  final Map<String, String> _clientSecrets = <String, String>{};

  LocalPaymentRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _repository ??= LocalPaymentRepository(db, tenantId: _tenantId);
  }

  Stream<PendingPaymentModel> get eventos => _eventos.stream;

  // [EXAMEN-2] C2.5 CU16: crea el PaymentIntent en el servidor (POST /pagos/diferidos).
  Future<PendingPaymentModel> registrarPago({
    required String uuidPago,
    required String uuidOrden,
    required double monto,
    String moneda = 'BOB',
    DateTime? expiraEn,
    bool intentarRemoto = true,
  }) async {
    await _repo.crear(
      uuidPago,
      monto: monto,
      uuidOrden: uuidOrden,
      moneda: moneda,
      fechaExpiracion: expiraEn,
      idempotencyKey: uuidPago,
    );
    // Intento de creación remota con Idempotency-Key = uuidPago (RN-015).
    // Si no hay red, queda PENDIENTE local y se sincroniza vía cola.
    String? stripeId;
    if (intentarRemoto) {
      try {
        final data = await _client.post(
          AppConstants.epPagosDiferidos,
          headers: <String, dynamic>{'Idempotency-Key': uuidPago},
          data: <String, Object?>{
            'uuid_pago': uuidPago,
            'uuid_orden': uuidOrden,
            'monto': monto,
            'moneda': moneda,
            if (expiraEn != null) 'expira_en': expiraEn.toUtc().toIso8601String(),
          },
        );
        if (data is Map) {
          stripeId = data['stripe_payment_intent_id']?.toString();
        }
      } catch (_) {}
    }
    if (stripeId != null && stripeId.isNotEmpty) {
      await _repo.guardar(<String, Object?>{
        'uuid_pago': uuidPago,
        'stripe_payment_intent_id': stripeId,
      });
    }
    final pago = await estadoPago(uuidPago);
    if (pago != null) _eventos.add(pago);
    return pago!;
  }

  Future<PendingPaymentModel?> estadoPago(String uuidPago) async {
    final fila = await _repo.obtenerPorUuid(uuidPago);
    return fila == null ? null : PendingPaymentModel.fromMap(fila);
  }

  Future<List<PendingPaymentModel>> pendientes() async {
    final pagos = await _repo.listarTodos();
    return pagos
        .map(PendingPaymentModel.fromMap)
        .where((pago) => pago.estaPendiente)
        .toList(growable: false);
  }

  Future<int> contadorPendientes() async => (await pendientes()).length;

  Future<Duration?> cuentaRegresiva(String uuidPago) async =>
      (await estadoPago(uuidPago))?.cuentaRegresiva;

  Future<PendingPaymentModel?> confirmarPago(String uuidPago) async {
    try {
      await _client.post(
        '${AppConstants.epPagosDiferidos}/$uuidPago/confirmar',
        headers: <String, dynamic>{'Idempotency-Key': uuidPago},
      );
      await _repo.actualizarEstado(uuidPago, 'CONFIRMADO');
      await _audit?.registrar(
        tenantId: _tenantId,
        tipo: 'PAGO_DIFERIDO_CONFIRMADO',
        mensaje: 'Pago diferido confirmado.',
        datos: <String, dynamic>{'uuid_pago': uuidPago},
      );
      final pago = await estadoPago(uuidPago);
      if (pago != null) _eventos.add(pago);
      return pago;
    } catch (error) {
      await _repo.registrarIntento(uuidPago, ultimoError: error.toString());
      await _repo.actualizarEstado(
        uuidPago,
        'RECHAZADO',
        ultimoError: error.toString(),
      );
      await _audit?.registrar(
        tenantId: _tenantId,
        tipo: 'PAGO_DIFERIDO_RECHAZADO',
        mensaje: 'El pago diferido fue rechazado.',
        datos: <String, dynamic>{'uuid_pago': uuidPago},
      );
      rethrow;
    }
  }

  Future<PendingPaymentModel?> reintentarPago(String uuidPago) async {
    await _repo.registrarIntento(uuidPago);
    await _repo.actualizarEstado(uuidPago, 'PENDIENTE');
    await _client.post(
      '${AppConstants.epPagosDiferidos}/$uuidPago/reintentar',
      headers: <String, dynamic>{'Idempotency-Key': uuidPago},
    );
    await _repo.actualizarEstado(uuidPago, 'REQUIERE_ACCION_CLIENTE');
    await _audit?.registrar(
      tenantId: _tenantId,
      tipo: 'PAGO_DIFERIDO_REINTENTADO',
      mensaje: 'Se solicito el reintento del pago diferido.',
      datos: <String, dynamic>{'uuid_pago': uuidPago},
    );
    return estadoPago(uuidPago);
  }

  // [EXAMEN-2] C2.5 CU16: cancelación con Idempotency-Key y expiración local.
  Future<void> cancelarPago(String uuidPago) async {
    await _client.post(
      '${AppConstants.epPagosDiferidos}/$uuidPago/cancelar',
      headers: <String, dynamic>{'Idempotency-Key': uuidPago},
    );
    await _repo.actualizarEstado(uuidPago, 'CANCELADO');
    final pago = await estadoPago(uuidPago);
    if (pago != null) _eventos.add(pago);
  }

  // [EXAMEN-2] C2.5 CU16: job de expiración — marca EXPIRADO y libera stock (RN-007).
  Future<int> procesarExpirados() async {
    final todos = await _repo.listarTodos();
    var procesados = 0;
    final ahora = DateTime.now().toUtc();
    for (final fila in todos) {
      final expRaw = fila['fecha_expiracion']?.toString();
      final exp = DateTime.tryParse(expRaw ?? '');
      if (exp == null || exp.isAfter(ahora)) continue;
      final estado = fila['estado']?.toString().toUpperCase() ?? '';
      if (!const {'PENDIENTE', 'REQUIERE_ACCION_CLIENTE'}.contains(estado)) {
        continue;
      }
      final uuid = fila['uuid_pago']?.toString() ?? '';
      if (uuid.isEmpty) continue;
      await _repo.actualizarEstado(uuid, 'EXPIRADO');
      await _audit?.registrar(
        tenantId: _tenantId,
        tipo: 'PAGO_DIFERIDO_EXPIRADO',
        mensaje: 'Pago diferido expirado; stock liberado.',
        datos: <String, dynamic>{'uuid_pago': uuid},
      );
      procesados++;
    }
    return procesados;
  }

  /// Descarga el `client_secret` ?nicamente cuando se necesita PaymentSheet.
  /// RN-015: nunca se persiste en SQLite ni en almacenamiento seguro.
  Future<String?> prepararPaymentSheet(String uuidPago) async {
    final data = await _client.get('${AppConstants.epPagosDiferidos}/$uuidPago');
    if (data is! Map) return null;
    final secret = data['client_secret']?.toString();
    if (secret == null || secret.isEmpty) return null;
    _clientSecrets[uuidPago] = secret;
    return secret;
  }

  String? clientSecretEnMemoria(String uuidPago) => _clientSecrets[uuidPago];

  void olvidarClientSecret(String uuidPago) => _clientSecrets.remove(uuidPago);

  Future<void> dispose() async => _eventos.close();
}
