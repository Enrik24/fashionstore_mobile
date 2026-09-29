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

  ReturnItemModel({
    required this.id,
    required this.solicitudId,
    required this.detalleOrdenId,
    this.varianteProductoId,
    required this.cantidad,
    this.varianteCambioId,
    required this.precioUnitario,
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

  factory ReturnItemModel.fromJson(Map<String, dynamic> json) {
    return ReturnItemModel(
      id: _parseInt(json['id']),
      solicitudId: _parseInt(json['solicitud_id']),
      detalleOrdenId: _parseInt(json['detalle_orden_id']),
      varianteProductoId: _parseIntOpt(json['variante_producto_id']),
      cantidad: _parseInt(json['cantidad'], 1),
      varianteCambioId: _parseIntOpt(json['variante_cambio_id']),
      precioUnitario: _parseDouble(json['precio_unitario']),
    );
  }
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
  });

  bool get isCambio => tipo.toUpperCase() == 'CAMBIO';

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
    );
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
