// [EXAMEN-2] Modelos de dominio para operación, sincronización y pagos offline.
import 'dart:convert';

class OfflineOperationModel {
  const OfflineOperationModel({
    required this.uuidOperacion,
    required this.tipoOperacion,
    required this.estadoSincronizacion,
    required this.secuenciaLocal,
    required this.payload,
    this.dispositivoId = '',
    this.usuarioId,
    this.sucursalId,
    this.intentos = 0,
    this.fechaRegistroLocal,
    this.fechaUltimoIntento,
    this.fechaRecepcionServidor,
    this.errorDetalle,
  });

  final String uuidOperacion;
  final String tipoOperacion;
  final String estadoSincronizacion;
  final int secuenciaLocal;
  final Map<String, Object?> payload;
  final String dispositivoId;
  final int? usuarioId;
  final int? sucursalId;
  final int intentos;
  final DateTime? fechaRegistroLocal;
  final DateTime? fechaUltimoIntento;
  final DateTime? fechaRecepcionServidor;
  final String? errorDetalle;

  bool get isPendiente => const {
    'PENDIENTE',
    'ERROR',
    'RECHAZADA',
  }.contains(estadoSincronizacion.toUpperCase());
  bool get isTerminal => const {
    'CONFIRMADA',
    'DUPLICADA',
  }.contains(estadoSincronizacion.toUpperCase());
  bool get requiereRevision =>
      estadoSincronizacion.toUpperCase() == 'CONFLICTO';

  factory OfflineOperationModel.fromMap(Map<String, Object?> map) {
    Map<String, Object?> payload = const {};
    final raw = map['payload_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) payload = Map<String, Object?>.from(decoded);
      } catch (_) {}
    }
    return OfflineOperationModel(
      uuidOperacion: map['uuid_operacion']?.toString() ?? '',
      tipoOperacion: map['tipo_operacion']?.toString() ?? '',
      estadoSincronizacion:
          map['estado_sincronizacion']?.toString() ?? 'PENDIENTE',
      secuenciaLocal: (map['secuencia_local'] as num?)?.toInt() ?? 0,
      payload: payload,
      dispositivoId: map['dispositivo_id']?.toString() ?? '',
      usuarioId: (map['usuario_id'] as num?)?.toInt(),
      sucursalId: (map['sucursal_id'] as num?)?.toInt(),
      intentos: (map['intentos'] as num?)?.toInt() ?? 0,
      fechaRegistroLocal: DateTime.tryParse(
        map['fecha_registro_local']?.toString() ?? '',
      ),
      fechaUltimoIntento: DateTime.tryParse(
        map['fecha_ultimo_intento']?.toString() ?? '',
      ),
      fechaRecepcionServidor: DateTime.tryParse(
        map['fecha_recepcion_servidor']?.toString() ?? '',
      ),
      errorDetalle: map['ultimo_error']?.toString(),
    );
  }

  /// Contrato local; el cliente HTTP lo transforma al campo `payload` del API.
  Map<String, Object?> toMap() => <String, Object?>{
    'uuid_operacion': uuidOperacion,
    'tipo_operacion': tipoOperacion,
    'estado_sincronizacion': estadoSincronizacion,
    'secuencia_local': secuenciaLocal,
    'payload_json': jsonEncode(payload),
    'dispositivo_id': dispositivoId,
    'usuario_id': usuarioId,
    'sucursal_id': sucursalId,
    'intentos': intentos,
    'fecha_registro_local': fechaRegistroLocal?.toUtc().toIso8601String(),
    'fecha_ultimo_intento': fechaUltimoIntento?.toUtc().toIso8601String(),
    'fecha_recepcion_servidor': fechaRecepcionServidor
        ?.toUtc()
        .toIso8601String(),
    'ultimo_error': errorDetalle,
  };
}

class ConflictModel {
  const ConflictModel({
    required this.id,
    required this.tipo,
    required this.motivo,
    required this.estado,
    required this.resuelto,
    this.uuidOperacion,
    this.datosLocal,
    this.datosCentral,
    this.accion,
    this.fecha,
  });

  final int id;
  final String tipo;
  final String motivo;
  final String estado;
  final bool resuelto;
  final String? uuidOperacion;
  final Map<String, Object?>? datosLocal;
  final Map<String, Object?>? datosCentral;
  final String? accion;
  final DateTime? fecha;

  factory ConflictModel.fromMap(Map<String, Object?> map) {
    Map<String, Object?>? decode(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        final value = jsonDecode(raw);
        return value is Map ? Map<String, Object?>.from(value) : null;
      } catch (_) {
        return null;
      }
    }

    return ConflictModel(
      id: (map['id'] as num?)?.toInt() ?? 0,
      tipo: map['tipo']?.toString() ?? 'DESCONOCIDO',
      motivo: map['motivo']?.toString() ?? '',
      estado: map['estado']?.toString() ?? 'PENDIENTE',
      resuelto: (map['resuelto'] as num?)?.toInt() == 1,
      uuidOperacion: map['uuid_operacion']?.toString(),
      datosLocal: decode(map['datos_local']?.toString()),
      datosCentral: decode(map['datos_central']?.toString()),
      accion: map['accion']?.toString(),
      fecha: DateTime.tryParse(map['fecha_registro_local']?.toString() ?? ''),
    );
  }
}

class PendingPaymentModel {
  const PendingPaymentModel({
    required this.uuidPago,
    required this.monto,
    required this.estado,
    this.uuidOrden,
    this.moneda = 'BOB',
    this.fechaExpiracion,
    this.intentos = 0,
    this.ultimoError,
    this.idempotencyKey,
  });

  final String uuidPago;
  final String? uuidOrden;
  final double monto;
  final String moneda;
  final String estado;
  final DateTime? fechaExpiracion;
  final int intentos;
  final String? ultimoError;
  final String? idempotencyKey;

  bool get requiereAccion => estado.toUpperCase() == 'REQUIERE_ACCION_CLIENTE';
  bool get estaPendiente => !const {
    'CONFIRMADO',
    'CANCELADO',
    'EXPIRADO',
    'RECHAZADO',
  }.contains(estado.toUpperCase());
  Duration? get cuentaRegresiva {
    final expira = fechaExpiracion;
    if (expira == null) return null;
    final diferencia = expira.difference(DateTime.now());
    return diferencia.isNegative ? Duration.zero : diferencia;
  }

  factory PendingPaymentModel.fromMap(Map<String, Object?> map) =>
      PendingPaymentModel(
        uuidPago: map['uuid_pago']?.toString() ?? '',
        uuidOrden: map['uuid_orden']?.toString(),
        monto: (map['monto'] as num?)?.toDouble() ?? 0,
        moneda: map['moneda']?.toString() ?? 'BOB',
        estado: map['estado']?.toString() ?? 'PENDIENTE',
        fechaExpiracion: DateTime.tryParse(
          map['fecha_expiracion']?.toString() ?? '',
        ),
        intentos: (map['intentos'] as num?)?.toInt() ?? 0,
        ultimoError: map['ultimo_error']?.toString(),
        idempotencyKey: map['idempotency_key']?.toString(),
      );
}

class SyncSummaryModel {
  const SyncSummaryModel({
    this.pendientes = 0,
    this.enviadas = 0,
    this.confirmadas = 0,
    this.rechazadas = 0,
    this.conflictos = 0,
    this.duplicadas = 0,
    this.erroresCriticos = 0,
    this.ultimoError,
  });

  final int pendientes;
  final int enviadas;
  final int confirmadas;
  final int rechazadas;
  final int conflictos;
  final int duplicadas;
  final int erroresCriticos;
  final String? ultimoError;

  factory SyncSummaryModel.fromCounts(
    Map<String, int> counts, {
    String? ultimoError,
  }) {
    int get(String key) => counts[key.toUpperCase()] ?? 0;
    return SyncSummaryModel(
      pendientes: get('PENDIENTE') + get('ERROR'),
      enviadas: get('ENVIADA'),
      confirmadas: get('CONFIRMADA'),
      rechazadas: get('RECHAZADA'),
      conflictos: get('CONFLICTO'),
      duplicadas: get('DUPLICADA'),
      erroresCriticos: get('ERROR_CRITICO'),
      ultimoError: ultimoError,
    );
  }
}

class LocalSaleModel {
  const LocalSaleModel({
    required this.uuidOffline,
    required this.sucursalId,
    required this.total,
    required this.montoRecibido,
    required this.cambio,
    required this.estado,
    this.items = const [],
    this.fecha,
  });

  final String uuidOffline;
  final int sucursalId;
  final double total;
  final double montoRecibido;
  final double cambio;
  final String estado;
  final List<Map<String, Object?>> items;
  final DateTime? fecha;
}

class OfflineDownloadStatus {
  const OfflineDownloadStatus({
    this.enProgreso = false,
    this.incompleto = false,
    this.ultimaDescargaCompleta,
    this.cursorCatalogo,
    this.sello,
    this.error,
  });

  final bool enProgreso;
  final bool incompleto;
  final DateTime? ultimaDescargaCompleta;
  final String? cursorCatalogo;
  final DateTime? sello;
  final String? error;

  OfflineDownloadStatus copyWith({
    bool? enProgreso,
    bool? incompleto,
    DateTime? ultimaDescargaCompleta,
    String? cursorCatalogo,
    DateTime? sello,
    String? error,
  }) => OfflineDownloadStatus(
    enProgreso: enProgreso ?? this.enProgreso,
    incompleto: incompleto ?? this.incompleto,
    ultimaDescargaCompleta:
        ultimaDescargaCompleta ?? this.ultimaDescargaCompleta,
    cursorCatalogo: cursorCatalogo ?? this.cursorCatalogo,
    sello: sello ?? this.sello,
    error: error,
  );
}
