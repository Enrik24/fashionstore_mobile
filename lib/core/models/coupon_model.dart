/// Cupón de descuento (CU27).
/// Backend: CuponResponse
/// {id, codigo, tipo, valor, descripcion, fecha_inicio, fecha_fin,
///  usos_maximos, usos_actuales, monto_minimo, estado, producto_ids,
///  categoria_ids, creado_por_id, fecha_creacion}
class CouponModel {
  final int id;
  final String codigo;
  final String tipo;
  final double valor;
  final String? descripcion;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final int? usosMaximos;
  final int usosActuales;
  final double? montoMinimo;
  final String estado;
  final List<int> productoIds;
  final List<int> categoriaIds;

  CouponModel({
    required this.id,
    required this.codigo,
    required this.tipo,
    required this.valor,
    this.descripcion,
    this.fechaInicio,
    this.fechaFin,
    this.usosMaximos,
    this.usosActuales = 0,
    this.montoMinimo,
    this.estado = 'ACTIVO',
    this.productoIds = const [],
    this.categoriaIds = const [],
  });

  /// true cuando el cupón aplica a todo el catálogo (sin restricciones).
  bool get aplicaATodo => productoIds.isEmpty && categoriaIds.isEmpty;

  bool get isPorcentaje => tipo.toUpperCase() == 'PORCENTAJE';

  String get valorLabel =>
      isPorcentaje ? '${valor.toStringAsFixed(0)}% OFF' : 'Bs. ${valor.toStringAsFixed(2)} OFF';

  static int _parseInt(dynamic raw, [int fallback = 0]) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static double _parseDouble(dynamic raw, [double fallback = 0.0]) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static List<int> _parseIds(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => _parseInt(e)).toList();
    }
    return [];
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

  factory CouponModel.fromJson(Map<String, dynamic> json) {
    return CouponModel(
      id: _parseInt(json['id']),
      codigo: json['codigo']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? 'PORCENTAJE',
      valor: _parseDouble(json['valor']),
      descripcion: json['descripcion']?.toString(),
      fechaInicio: _parseDate(json['fecha_inicio']),
      fechaFin: _parseDate(json['fecha_fin']),
      usosMaximos: json['usos_maximos'] == null
          ? null
          : _parseInt(json['usos_maximos']),
      usosActuales: _parseInt(json['usos_actuales']),
      montoMinimo: json['monto_minimo'] == null
          ? null
          : _parseDouble(json['monto_minimo']),
      estado: json['estado']?.toString() ?? 'ACTIVO',
      productoIds: _parseIds(json['producto_ids']),
      categoriaIds: _parseIds(json['categoria_ids']),
    );
  }
}

/// Resultado de `POST /cupones/validar` (CU27).
/// {valido, mensaje, cupon?, descuento_calculado}
class CouponValidationResult {
  final bool valido;
  final String mensaje;
  final CouponModel? cupon;
  final double descuentoCalculado;

  CouponValidationResult({
    required this.valido,
    required this.mensaje,
    this.cupon,
    this.descuentoCalculado = 0.0,
  });

  factory CouponValidationResult.fromJson(Map<String, dynamic> json) {
    final rawCupon = json['cupon'];
    final desc = json['descuento_calculado'];
    final descValue = desc is num
        ? desc.toDouble()
        : double.tryParse(desc?.toString() ?? '0') ?? 0.0;
    return CouponValidationResult(
      valido: json['valido'] == true,
      mensaje: json['mensaje']?.toString() ?? '',
      cupon: rawCupon is Map<String, dynamic>
          ? CouponModel.fromJson(rawCupon)
          : null,
      descuentoCalculado: descValue,
    );
  }
}
