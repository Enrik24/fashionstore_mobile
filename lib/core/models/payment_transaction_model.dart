/// Transacción de pago de una orden (CU18).
/// Backend: `GET /pagos/transacciones/orden/{orden_id}`
/// -> TransaccionPagoResponse
/// {id, orden_id, monto, metodo_pago, estado, referencia_externa, fecha}
class PaymentTransactionModel {
  final int id;
  final int ordenId;
  final double monto;
  final String metodoPago;
  final String estado;
  final String? referenciaExterna;
  final DateTime? fecha;

  PaymentTransactionModel({
    required this.id,
    required this.ordenId,
    required this.monto,
    required this.metodoPago,
    required this.estado,
    this.referenciaExterna,
    this.fecha,
  });

  bool get isConfirmed =>
      estado.toUpperCase() == 'CONFIRMADO' ||
      estado.toUpperCase() == 'CONFIRMADA';
  bool get isPending => estado.toUpperCase() == 'PENDIENTE';
  bool get isRejected =>
      estado.toUpperCase() == 'RECHAZADO' ||
      estado.toUpperCase() == 'RECHAZADA';
  bool get isRefunded =>
      estado.toUpperCase() == 'REEMBOLSADO' ||
      estado.toUpperCase() == 'REEMBOLSADA';

  static int _parseInt(dynamic raw, [int fallback = 0]) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
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

  factory PaymentTransactionModel.fromJson(Map<String, dynamic> json) {
    return PaymentTransactionModel(
      id: _parseInt(json['id']),
      ordenId: _parseInt(json['orden_id']),
      monto: _parseDouble(json['monto']),
      metodoPago: json['metodo_pago']?.toString() ?? '',
      estado: json['estado']?.toString() ?? 'PENDIENTE',
      referenciaExterna: json['referencia_externa']?.toString(),
      fecha: _parseDate(json['fecha']),
    );
  }
}
