// [EXAMEN-2] CU19: compensación por venta offline rechazada (modo cajero).
// Espejo del serializer del backend
// (`operaciones_offline/router.py::_serializar_compensacion`) más caché local.
class CompensacionModel {
  const CompensacionModel({
    required this.id,
    this.operacionOfflineId,
    this.uuidOperacion,
    this.ordenId,
    this.clienteId,
    required this.monto,
    this.moneda,
    required this.tipo,
    required this.estado,
    this.referenciaExterna,
    this.motivo,
    this.notificadoCliente = false,
    this.errorDetalle,
    this.fechaCreacion,
    this.fechaCompletado,
    this.resueltoPor,
  });

  final int id;
  final int? operacionOfflineId;
  final String? uuidOperacion;
  final int? ordenId;
  final int? clienteId;
  final double monto;
  final String? moneda;
  final String tipo;
  final String estado;
  final String? referenciaExterna;
  final String? motivo;
  final bool notificadoCliente;
  final String? errorDetalle;
  final DateTime? fechaCreacion;
  final DateTime? fechaCompletado;
  final String? resueltoPor;

  static int? _parseIntOpt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    return int.tryParse(raw.toString());
  }

  static double _parseDouble(dynamic raw, [double fallback = 0.0]) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static DateTime? _parseDate(dynamic raw) {
    final s = raw?.toString();
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// Lee la respuesta del backend (`/offline/compensaciones*`).
  factory CompensacionModel.fromJson(Map<String, dynamic> json) {
    final tipo = json['tipo']?.toString() ?? 'REEMBOLSO_EFECTIVO';
    final estado = json['estado']?.toString() ?? 'PENDIENTE';
    return CompensacionModel(
      id: _parseIntOpt(json['id']) ?? 0,
      operacionOfflineId: _parseIntOpt(json['operacion_offline_id']),
      uuidOperacion: json['uuid_operacion']?.toString(),
      ordenId: _parseIntOpt(json['orden_id']),
      clienteId: _parseIntOpt(json['cliente_id']),
      monto: _parseDouble(json['monto']),
      moneda: json['moneda']?.toString(),
      tipo: tipo.toUpperCase(),
      estado: estado.toUpperCase(),
      referenciaExterna: json['referencia_externa']?.toString(),
      motivo: json['motivo']?.toString(),
      notificadoCliente: json['notificado_cliente'] == true,
      errorDetalle: json['error_detalle']?.toString(),
      fechaCreacion: _parseDate(json['fecha_creacion']),
      fechaCompletado: _parseDate(
        json['fecha_completado'] ?? json['fecha_resolucion'],
      ),
      resueltoPor: json['resuelto_por']?.toString(),
    );
  }

  /// Reconstruye desde una fila de `compensaciones` (caché local CU19).
  factory CompensacionModel.fromMap(Map<String, Object?> map) {
    return CompensacionModel(
      id: (map['id'] as num?)?.toInt() ?? 0,
      operacionOfflineId: (map['operacion_offline_id'] as num?)?.toInt(),
      uuidOperacion: map['uuid_operacion']?.toString(),
      ordenId: (map['orden_id'] as num?)?.toInt(),
      clienteId: (map['cliente_id'] as num?)?.toInt(),
      monto: (map['monto'] as num?)?.toDouble() ?? 0,
      moneda: map['moneda']?.toString(),
      tipo: map['tipo']?.toString() ?? 'REEMBOLSO_EFECTIVO',
      estado: map['estado']?.toString() ?? 'PENDIENTE',
      referenciaExterna: map['referencia_externa']?.toString(),
      motivo: map['motivo']?.toString(),
      notificadoCliente: map['notificado_cliente'] == 1,
      errorDetalle: map['error_detalle']?.toString(),
      fechaCreacion: DateTime.tryParse(map['fecha_creacion']?.toString() ?? ''),
      fechaCompletado: DateTime.tryParse(
        (map['fecha_completado'] ?? map['fecha_resolucion'])?.toString() ?? '',
      ),
      resueltoPor: map['resuelto_por']?.toString(),
    );
  }

  /// Fila insertable en `compensaciones` (dedup por `id` en el repositorio).
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id == 0 ? null : id,
    'operacion_offline_id': operacionOfflineId,
    'uuid_operacion': uuidOperacion,
    'orden_id': ordenId,
    'cliente_id': clienteId,
    'monto': monto,
    'moneda': moneda,
    'tipo': tipo.toUpperCase(),
    'estado': estado.toUpperCase(),
    'referencia_externa': referenciaExterna,
    'motivo': motivo,
    'notificado_cliente': notificadoCliente ? 1 : 0,
    'error_detalle': errorDetalle,
    'fecha_creacion': fechaCreacion?.toUtc().toIso8601String(),
    'fecha_completado': fechaCompletado?.toUtc().toIso8601String(),
    'fecha_resolucion': fechaCompletado?.toUtc().toIso8601String(),
    'resuelto_por': resueltoPor,
  };

  bool get esEfectivo => tipo.toUpperCase() == 'REEMBOLSO_EFECTIVO';
  bool get estaCompletada => estado.toUpperCase() == 'COMPLETADA';
  bool get estaPendiente => const {
    'PENDIENTE',
    'EN_PROCESO',
  }.contains(estado.toUpperCase());

  /// Copia con otro estado (p. ej. al confirmar el efectivo en caja).
  CompensacionModel copyWith({
    String? estado,
    DateTime? fechaCompletado,
    String? resueltoPor,
  }) => CompensacionModel(
    id: id,
    operacionOfflineId: operacionOfflineId,
    uuidOperacion: uuidOperacion,
    ordenId: ordenId,
    clienteId: clienteId,
    monto: monto,
    moneda: moneda,
    tipo: tipo,
    estado: estado ?? this.estado,
    referenciaExterna: referenciaExterna,
    motivo: motivo,
    notificadoCliente: notificadoCliente,
    errorDetalle: errorDetalle,
    fechaCreacion: fechaCreacion,
    fechaCompletado: fechaCompletado ?? this.fechaCompletado,
    resueltoPor: resueltoPor ?? this.resueltoPor,
  );
}

/// [EXAMEN-2] Tipos y estados de compensación (CU19, espejo backend).
class CompensacionTipos {
  static const String reembolsoEfectivo = 'REEMBOLSO_EFECTIVO';
  static const String reembolsoTarjeta = 'REEMBOLSO_TARJETA';
  static const String notaCredito = 'NOTA_CREDITO';
  static const String saldoFavor = 'SALDO_FAVOR';
  static const String pendiente = 'PENDIENTE';
  static const String enProceso = 'EN_PROCESO';
  static const String completada = 'COMPLETADA';
  static const String fallida = 'FALLIDA';

  static String labelTipo(String tipo) {
    return switch (tipo.toUpperCase()) {
      reembolsoEfectivo => 'Reembolso en efectivo',
      reembolsoTarjeta => 'Reembolso por tarjeta',
      notaCredito => 'Nota de crédito',
      saldoFavor => 'Saldo a favor',
      _ => tipo,
    };
  }

  static String labelEstado(String estado) {
    return switch (estado.toUpperCase()) {
      pendiente => 'Pendiente',
      enProceso => 'En proceso',
      completada => 'Completada',
      fallida => 'Fallida',
      _ => estado,
    };
  }
}
