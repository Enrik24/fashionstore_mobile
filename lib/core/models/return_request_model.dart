/// Solicitud de devolución o cambio (CU28).
/// Backend: SolicitudDevolucionResponse
/// {id, numero_solicitud, cliente_id, orden_id, sucursal_id, tipo, motivo,
///  motivo_detalle, estado, monto_reembolso, observaciones_staff,
///  revisado_por_id, fecha_solicitud, fecha_resolucion, detalles[]}
class ReturnItemModel {
  final int id;
  final int solicitudId;
  final int detalleOrdenId;
  final int? varianteProductoId;
  final int cantidad;
  final int? varianteCambioId;
  final double precioUnitario;

  // [EXAMEN-2] Campos de reposición offline (CU18) — solo lectura local.
  // [EXAMEN-2] Precio de la variante nueva y diferencia por línea (§5.9).
  final double? precioVarianteNueva;
  final double? diferencia;
  // [EXAMEN-2] Subtotal de la diferencia de la línea (CU18).
  final double? subtotalDiferencia;
  // [EXAMEN-2] Estado de la línea (DEVUELTA / NUEVA / SIN_ALTERNATIVA).
  final String? estadoItem;
  // [EXAMEN-2] Identificador offline de la línea local (CU13/CU18).
  final String? uuidOffline;

  ReturnItemModel({
    required this.id,
    required this.solicitudId,
    required this.detalleOrdenId,
    this.varianteProductoId,
    required this.cantidad,
    this.varianteCambioId,
    required this.precioUnitario,
    // [EXAMEN-2] CU18: precio/diferencia por línea (§5.9).
    this.precioVarianteNueva,
    this.diferencia,
    this.subtotalDiferencia,
    this.estadoItem,
    this.uuidOffline,
  });

  static int? _parseIntOpt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    return int.tryParse(raw.toString());
  }

  static int _parseInt(dynamic raw, [int fallback = 0]) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static double _parseDouble(dynamic raw, [double fallback = 0.0]) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  // [EXAMEN-2] CU18: precio/diferencia opcionales por línea (§5.9).
  static double? _parseDoubleOpt(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }

  factory ReturnItemModel.fromJson(Map<String, dynamic> json) {
    return ReturnItemModel(
      id: _parseInt(json['id']),
      solicitudId: _parseInt(json['solicitud_id']),
      detalleOrdenId: _parseInt(json['detalle_orden_id']),
      varianteProductoId: _parseIntOpt(json['variante_producto_id']),
      cantidad: _parseInt(json['cantidad'], 1),
      varianteCambioId: _parseIntOpt(json['variante_cambio_id']),
      precioUnitario: _parseDouble(json['precio_unitario']),
      // [EXAMEN-2] CU18: diferencia por línea (§5.9).
      precioVarianteNueva: _parseDoubleOpt(json['precio_variante_nueva']),
      diferencia: _parseDoubleOpt(json['diferencia']),
      subtotalDiferencia: _parseDoubleOpt(json['subtotal_diferencia']),
      estadoItem: json['estado_item']?.toString(),
      uuidOffline: json['uuid_offline']?.toString(),
    );
  }

  // [EXAMEN-2] CU13/CU18: serializa una fila de items_devolucion_local.
  Map<String, Object?> toLocalMap() => <String, Object?>{
    'id': id == 0 ? null : id,
    'solicitud_id': solicitudId,
    'detalle_orden_id': detalleOrdenId,
    'variante_producto_id': varianteProductoId,
    'cantidad': cantidad,
    'variante_cambio_id': varianteCambioId,
    'precio_unitario': precioUnitario,
    'precio_variante_nueva': precioVarianteNueva,
    'diferencia': diferencia,
    'subtotal_diferencia': subtotalDiferencia,
    'estado_item': estadoItem,
    'uuid_offline': uuidOffline,
  };
}

class ReturnRequestModel {
  final int id;
  final String numeroSolicitud;
  final int? clienteId;
  final int ordenId;
  final int? sucursalId;
  final String tipo;
  final String motivo;
  final String? motivoDetalle;
  final String estado;
  final double? montoReembolso;
  final String? observacionesStaff;
  final DateTime? fechaSolicitud;
  final DateTime? fechaResolucion;
  final List<ReturnItemModel> items;

  // [EXAMEN-2] Campos de Fase 3 (CU13/CU18, §3.6 y §5.9) — solo lectura local.
  // [EXAMEN-2] Tipo canónico DEVOLUCION/REPOSICION (CAMBIO es alias legacy).
  final String? numeroReposicion;
  final String? notaReposicionUrl;
  final DateTime? fechaCambioLimite;
  final double? diferenciaPrecio;
  final String? tipoDiferencia;
  final double? montoPagadoDiferencia;
  final double? saldoFavor;
  final String? notaDevolucionUrl;
  final bool esOffline;
  final String? uuidOffline;
  final String? estadoSincronizacion;
  final int? varianteCambioId;
  final double? precioVarianteNueva;

  ReturnRequestModel({
    required this.id,
    required this.numeroSolicitud,
    this.clienteId,
    required this.ordenId,
    this.sucursalId,
    required this.tipo,
    required this.motivo,
    this.motivoDetalle,
    required this.estado,
    this.montoReembolso,
    this.observacionesStaff,
    this.fechaSolicitud,
    this.fechaResolucion,
    this.items = const [],
    // [EXAMEN-2] CU13/CU18 (§3.6).
    this.numeroReposicion,
    this.notaReposicionUrl,
    this.fechaCambioLimite,
    this.diferenciaPrecio,
    this.tipoDiferencia,
    this.montoPagadoDiferencia,
    this.saldoFavor,
    this.notaDevolucionUrl,
    this.esOffline = false,
    this.uuidOffline,
    this.estadoSincronizacion,
    this.varianteCambioId,
    this.precioVarianteNueva,
  });

  bool get isCambio => tipo.toUpperCase() == 'CAMBIO';

  // [EXAMEN-2] CU18: canónico REPOSICION (CAMBIO es alias legacy).
  bool get isReposicion => const ['REPOSICION', 'CAMBIO'].contains(tipo.toUpperCase());

  // [EXAMEN-2] CU13/CU18: diferencia clasificada (COBRO/SALDO_FAVOR/SIN_DIFERENCIA).
  String get clasificacionDiferencia {
    final v = tipoDiferencia?.toUpperCase();
    if (v != null && v.isNotEmpty) return v;
    final d = diferenciaPrecio ?? 0;
    if (d > 0.005) return 'COBRO';
    if (d < -0.005) return 'SALDO_FAVOR';
    return 'SIN_DIFERENCIA';
  }

  // [EXAMEN-2] CU13/CU18: fila local desde devoluciones_locales.
  Map<String, Object?> toLocalMap() => <String, Object?>{
    'uuid_offline': uuidOffline,
    'orden_origen_id': ordenId == 0 ? null : ordenId,
    'numero_solicitud': numeroSolicitud,
    'numero_reposicion': numeroReposicion,
    'tipo': tipo.toUpperCase(),
    'motivo': motivo,
    'motivo_detalle': motivoDetalle,
    'estado': estado,
    'estado_sincronizacion': estadoSincronizacion,
    'es_offline': esOffline ? 1 : 0,
    'diferencia_precio': diferenciaPrecio,
    'tipo_diferencia': tipoDiferencia,
    'monto_pagado_diferencia': montoPagadoDiferencia,
    'saldo_favor': saldoFavor,
    'monto_reembolso': montoReembolso,
    'fecha_limite_cambio': fechaCambioLimite?.toUtc().toIso8601String(),
    'cliente_id': clienteId,
    'sucursal_id': sucursalId,
    'nota_devolucion_url': notaDevolucionUrl,
    'nota_reposicion_url': notaReposicionUrl,
  };

  static int _parseInt(dynamic raw, [int fallback = 0]) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static int? _parseIntOpt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    return int.tryParse(raw.toString());
  }

  static double? _parseDoubleOpt(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
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

  factory ReturnRequestModel.fromJson(Map<String, dynamic> json) {
    var rawItems = json['detalles'] ?? json['items'] ?? [];
    List<ReturnItemModel> itemList = [];
    if (rawItems is List) {
      itemList = rawItems
          .map((e) => ReturnItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return ReturnRequestModel(
      id: _parseInt(json['id']),
      numeroSolicitud:
          json['numero_solicitud']?.toString() ?? 'DEV-${json['id']}',
      clienteId: _parseIntOpt(json['cliente_id']),
      ordenId: _parseInt(json['orden_id']),
      sucursalId: _parseIntOpt(json['sucursal_id']),
      tipo: json['tipo']?.toString() ?? 'DEVOLUCION',
      motivo: json['motivo']?.toString() ?? 'OTRO',
      motivoDetalle: json['motivo_detalle']?.toString(),
      estado: json['estado']?.toString() ?? 'PENDIENTE',
      montoReembolso: _parseDoubleOpt(json['monto_reembolso']),
      observacionesStaff: json['observaciones_staff']?.toString(),
      fechaSolicitud: _parseDate(json['fecha_solicitud']),
      fechaResolucion: _parseDate(json['fecha_resolucion']),
      items: itemList,
      // [EXAMEN-2] CU13/CU18 (§3.6, §5.9).
      numeroReposicion: json['numero_reposicion']?.toString(),
      notaReposicionUrl: json['nota_reposicion_url']?.toString(),
      fechaCambioLimite: _parseDate(json['fecha_limite_cambio']),
      diferenciaPrecio: _parseDoubleOpt(json['diferencia_precio']),
      tipoDiferencia: json['tipo_diferencia']?.toString(),
      montoPagadoDiferencia: _parseDoubleOpt(
        json['monto_pagado_diferencia'],
      ),
      saldoFavor: _parseDoubleOpt(json['saldo_favor']),
      notaDevolucionUrl: json['nota_devolucion_url']?.toString(),
      esOffline: json['es_offline'] == true || json['es_offline'] == 1,
      uuidOffline: json['uuid_offline']?.toString(),
      estadoSincronizacion: json['estado_sincronizacion']?.toString(),
      varianteCambioId: _parseIntOpt(json['variante_cambio_id']),
      precioVarianteNueva: _parseDoubleOpt(json['precio_variante_nueva']),
    );
  }

  // [EXAMEN-2] CU13/CU18: reconstruye la solicitud desde filas locales.
  factory ReturnRequestModel.fromLocal(
    Map<String, Object?> fila,
    List<ReturnItemModel> items,
  ) {
    return ReturnRequestModel(
      id: _parseInt(fila['id']),
      numeroSolicitud: fila['numero_solicitud']?.toString() ?? '',
      clienteId: _parseIntOpt(fila['cliente_id']),
      ordenId: _parseInt(fila['orden_origen_id']),
      sucursalId: _parseIntOpt(fila['sucursal_id']),
      tipo: fila['tipo']?.toString() ?? 'DEVOLUCION',
      motivo: fila['motivo']?.toString() ?? 'OTRO',
      motivoDetalle: fila['motivo_detalle']?.toString(),
      estado: fila['estado']?.toString() ?? 'PENDIENTE_SINCRONIZACION',
      montoReembolso: _parseDoubleOpt(fila['monto_reembolso']),
      fechaSolicitud: _parseDate(fila['fecha_registro_local']),
      items: items,
      numeroReposicion: fila['numero_reposicion']?.toString(),
      notaReposicionUrl: fila['nota_reposicion_url']?.toString(),
      fechaCambioLimite: _parseDate(fila['fecha_limite_cambio']),
      diferenciaPrecio: _parseDoubleOpt(fila['diferencia_precio']),
      tipoDiferencia: fila['tipo_diferencia']?.toString(),
      montoPagadoDiferencia: _parseDoubleOpt(
        fila['monto_pagado_diferencia'],
      ),
      saldoFavor: _parseDoubleOpt(fila['saldo_favor']),
      notaDevolucionUrl: fila['nota_devolucion_url']?.toString(),
      esOffline: fila['es_offline'] == 1,
      uuidOffline: fila['uuid_offline']?.toString(),
      estadoSincronizacion: fila['estado_sincronizacion']?.toString(),
    );
  }
}

/// [EXAMEN-2] Estados adicionales de Fase 3 (CU13/CU18).
class EstadosFase3 {
  static const String errorVentaInvalida = 'ERROR_VENTA_INVALIDA';
  static const String sinAlternativa = 'SIN_ALTERNATIVA';
  static const String pendienteSincronizacion = 'PENDIENTE_SINCRONIZACION';

  static String label(String estado) {
    return switch (estado.toUpperCase()) {
      errorVentaInvalida =>
        'Venta original inválida',
      sinAlternativa => 'Sin alternativa de talla',
      pendienteSincronizacion => 'Pendiente de sincronización',
      _ => EstadosDevolucion.label(estado),
    };
  }
}

/// [EXAMEN-2] Clasificación de la diferencia (CU13/CU18, RN-025).
class TipoDiferencia {
  static const String cobro = 'COBRO';
  static const String saldoFavor = 'SALDO_FAVOR';
  static const String sinDiferencia = 'SIN_DIFERENCIA';

  static String clasificar(double diferencia) {
    if (diferencia > 0.005) return cobro;
    if (diferencia < -0.005) return saldoFavor;
    return sinDiferencia;
  }

  static String label(String tipo) {
    return switch (tipo.toUpperCase()) {
      cobro => 'Cobro',
      saldoFavor => 'Saldo a favor',
      _ => 'Sin diferencia',
    };
  }
}

/// Motivos de devolución (espejo del enum backend `MotivoDevolucion`).
class MotivosDevolucion {
  static const String tallaIncorrecta = 'TALLA_INCORRECTA';
  static const String colorIncorrecto = 'COLOR_INCORRECTO';
  static const String defectoFabrica = 'DEFECTO_FABRICA';
  static const String otro = 'OTRO';

  static const List<String> todos = [
    tallaIncorrecta,
    colorIncorrecto,
    defectoFabrica,
    otro,
  ];

  static String label(String motivo) {
    switch (motivo.toUpperCase()) {
      case tallaIncorrecta:
        return 'Talla incorrecta';
      case colorIncorrecto:
        return 'Color incorrecto';
      case defectoFabrica:
        return 'Defecto de fábrica';
      default:
        return 'Otro';
    }
  }
}

/// Estados de solicitud (espejo del enum backend `EstadoSolicitudDevolucion`).
class EstadosDevolucion {
  static const String pendiente = 'PENDIENTE';
  static const String enRevision = 'EN_REVISION';
  static const String aprobada = 'APROBADA';
  static const String rechazada = 'RECHAZADA';
  static const String completada = 'COMPLETADA';
  static const String pendienteReembolso = 'PENDIENTE_REEMBOLSO';

  static String label(String estado) {
    switch (estado.toUpperCase()) {
      case pendiente:
        return 'Pendiente';
      case enRevision:
        return 'En revisión';
      case aprobada:
        return 'Aprobada';
      case rechazada:
        return 'Rechazada';
      case completada:
        return 'Completada';
      case pendienteReembolso:
        return 'Pendiente de reembolso';
      default:
        return estado;
    }
  }
}
