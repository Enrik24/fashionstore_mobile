/// Comprobante de una orden (factura, ticket, recibo).
/// Backend: `GET /ordenes/{id}/comprobante` -> ComprobanteResponse
/// {numero, tipo, fecha_emision, monto_total, archivo_pdf}
class ComprobanteModel {
  final String numero;
  final String tipo;
  final DateTime? fechaEmision;
  final double montoTotal;
  final String? archivoPdf;

  ComprobanteModel({
    required this.numero,
    required this.tipo,
    this.fechaEmision,
    required this.montoTotal,
    this.archivoPdf,
  });

  /// Etiqueta legible del tipo de comprobante.
  String get tipoLabel {
    switch (tipo.toUpperCase()) {
      case 'FACTURA':
        return 'Factura';
      case 'TICKET':
        return 'Ticket';
      case 'RECIBO':
        return 'Recibo';
      case 'NOTA_VENTA':
        return 'Nota de venta';
      default:
        return tipo;
    }
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

  factory ComprobanteModel.fromJson(Map<String, dynamic> json) {
    return ComprobanteModel(
      numero: json['numero']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? 'FACTURA',
      fechaEmision: _parseDate(json['fecha_emision']),
      montoTotal: _parseDouble(json['monto_total']),
      archivoPdf: json['archivo_pdf']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'numero': numero,
      'tipo': tipo,
      'fecha_emision': fechaEmision?.toIso8601String(),
      'monto_total': montoTotal,
      'archivo_pdf': archivoPdf,
    };
  }
}
