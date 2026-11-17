import 'dart:async';
import 'dart:convert';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/local_payment_repository.dart';
import '../models/phase2_models.dart';
import 'device_service.dart';
import 'local_audit_service.dart';

/// Datos que el backend entrega para cobrar un pago diferido.
///
/// Con `PaymentIntent` (o en modo simulado) llega `clientSecret` y la app usa
/// el PaymentSheet nativo. Con `Checkout Session` — modo real desde v16 del
/// backend — no existe `clientSecret` (RN-015): el cobro se completa en el
/// navegador con `checkoutUrl` y luego se verifica contra el servidor.
/// Es el mismo contrato que maneja el frontend web (`PreparacionPago`).
class PreparacionPago {
  const PreparacionPago({
    this.clientSecret,
    this.checkoutUrl,
    this.simulado = false,
  });

  final String? clientSecret;
  final String? checkoutUrl;
  final bool simulado;

  bool get usaPaymentSheet =>
      clientSecret != null && clientSecret!.isNotEmpty;

  bool get usaRedirect =>
      !usaPaymentSheet && checkoutUrl != null && checkoutUrl!.isNotEmpty;
}

/// [EXAMEN-2] Pago diferido con idempotencia y expiración (CU16).
class PendingPaymentService {
  PendingPaymentService({
    required LocalDatabaseService database,
    required int tenantId,
    required OfflineApiClient client,
    LocalPaymentRepository? repository,
    LocalAuditService? audit,
    // [EXAMEN-2] B0.4: id del usuario para estampar `usuario_id`.
    int? usuarioId,
  }) : _database = database,
       _tenantId = tenantId,
       _client = client,
       _repository = repository,
       _audit = audit,
       _usuarioId = usuarioId;

  final LocalDatabaseService _database;
  final int _tenantId;
  final OfflineApiClient _client;
  LocalPaymentRepository? _repository;
  final LocalAuditService? _audit;
  // [EXAMEN-2] B0.4.
  final int? _usuarioId;
  final StreamController<PendingPaymentModel> _eventos =
      StreamController<PendingPaymentModel>.broadcast();
  final Map<String, String> _clientSecrets = <String, String>{};
  // [EXAMEN-2] B1.7.a: temporizador del job de expiracion.
  Timer? _timerExpiracion;

  LocalPaymentRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _repository ??= LocalPaymentRepository(
      db,
      tenantId: _tenantId,
      usuarioId: _usuarioId,
    );
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

  /// [EXAMEN-2] B1.7.a: programa el job de expiración.
  ///
  /// Antes `procesarExpirados()` existía pero **nadie lo invocaba**: los pagos
  /// diferidos vencidos nunca se marcaban como `EXPIRADO` ni liberaban el
  /// stock (RN-016). Se ejecuta al arrancar y cada 5 minutos.
  void programarExpiracion({Duration intervalo = const Duration(minutes: 5)}) {
    _timerExpiracion?.cancel();
    _timerExpiracion = Timer.periodic(intervalo, (_) async {
      try {
        await procesarExpirados();
      } catch (_) {
        // El job es best-effort: no debe romper la app.
      }
    });
    // also ejecuta una vez al arrancar.
    unawaited(
      procesarExpirados().catchError((Object _) => 0),
    );
  }

  /// Cancela el job de expiración (al cerrar sesión o revocar el dispositivo).
  void cancelarExpiracion() {
    _timerExpiracion?.cancel();
    _timerExpiracion = null;
  }

  /// [EXAMEN-2] B1.7.d: reenvía al backend los pagos diferidos **locales**
  /// que aún no se han creado en el servidor.
  ///
  /// El POST inicial ocurre al crear el pago; si fallaba por falta de red, el
  /// pago quedaba local `PENDIENTE` sin que nada lo reenviara.
  Future<int> reenviarPendientesLocales() async {
    final todos = await _repo.listarTodos();
    var reenviados = 0;
    for (final fila in todos) {
      final estado = fila['estado']?.toString().toUpperCase() ?? '';
      if (estado != 'PENDIENTE') continue;
      final uuid = fila['uuid_pago']?.toString() ?? '';
      if (uuid.isEmpty) continue;
      final datos = fila['datos_json']?.toString();
      Map<String, Object?>? cuerpo;
      if (datos != null && datos.isNotEmpty) {
        try {
          final decodificado = jsonDecode(datos);
          if (decodificado is Map) cuerpo = Map<String, Object?>.from(decodificado);
        } catch (_) {}
      }
      try {
        final data = await _client.post(
          AppConstants.epPagosDiferidos,
          data: <String, Object?>{
            'uuid_pago': uuid,
            'uuid_orden': fila['uuid_orden']?.toString(),
            'monto': fila['monto'],
            'moneda': fila['moneda'] ?? 'BOB',
            ...?cuerpo,
          },
          headers: <String, dynamic>{'Idempotency-Key': uuid},
        );
        // [FIX-SYNC] El backend responde con el pago existente (idempotente
        // por uuid_pago) o el recién creado: se guarda el id del
        // PaymentIntent. El client_secret NUNCA se persiste (RN-015).
        if (data is Map) {
          final stripeId = data['stripe_payment_intent_id']?.toString();
          if (stripeId != null && stripeId.isNotEmpty) {
            await _repo.guardar(<String, Object?>{
              'uuid_pago': uuid,
              'stripe_payment_intent_id': stripeId,
            });
          }
        }
        await _repo.actualizarEstado(uuid, 'REQUIERE_ACCION_CLIENTE');
        reenviados++;
      } catch (_) {
        // Sin red: se reintentará en la próxima pasada.
      }
    }
    return reenviados;
  }

  /// Descarga los datos necesarios para cobrar el pago diferido.
  ///
  /// El backend puede devolver:
  ///  * `client_secret` -> PaymentSheet nativo (PaymentIntent o modo simulado).
  ///  * `checkout_url`  -> Checkout Session de Stripe: se abre en el navegador
  ///    y se verifica con `confirmarPago` (igual que hace la web).
  /// RN-015: el `client_secret` nunca se persiste, solo vive en memoria.
  Future<PreparacionPago> prepararPago(String uuidPago) async {
    final data = await _client.get('${AppConstants.epPagosDiferidos}/$uuidPago');
    if (data is! Map) {
      throw StateError(
        'El servidor devolvió una respuesta inválida al preparar el pago.',
      );
    }
    final secret = data['client_secret']?.toString();
    final tieneSecret = secret != null && secret.isNotEmpty;
    if (tieneSecret) _clientSecrets[uuidPago] = secret;
    return PreparacionPago(
      clientSecret: tieneSecret ? secret : null,
      checkoutUrl: data['checkout_url']?.toString(),
      simulado: data['simulado'] == true,
    );
  }

  /// Mantiene el contrato anterior para quienes solo necesitan el secreto.
  Future<String?> prepararPaymentSheet(String uuidPago) async {
    final preparacion = await prepararPago(uuidPago);
    return preparacion.clientSecret;
  }

  String? clientSecretEnMemoria(String uuidPago) => _clientSecrets[uuidPago];

  void olvidarClientSecret(String uuidPago) => _clientSecrets.remove(uuidPago);

  Future<void> dispose() async => _eventos.close();
}
