import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/models/comprobante_model.dart';
import 'package:fashionstore_mobile/core/models/order_model.dart';

void main() {
  group('ComprobanteModel (factura por orden)', () {
    test('fromJson con ComprobanteResponse del backend', () {
      final json = {
        'numero': 'FAC-000123',
        'tipo': 'FACTURA',
        'fecha_emision': '2026-09-21T10:00:00Z',
        'monto_total': '349.99',
        'archivo_pdf': '/api/v1/ordenes/55/comprobante/pdf',
      };

      final comp = ComprobanteModel.fromJson(json);
      expect(comp.numero, 'FAC-000123');
      expect(comp.tipoLabel, 'Factura');
      expect(comp.montoTotal, 349.99);
      expect(comp.fechaEmision, isNotNull);
      expect(comp.archivoPdf, contains('comprobante/pdf'));
    });

    test('tipoLabel para cada tipo de comprobante', () {
      expect(
        ComprobanteModel(numero: 'T', tipo: 'TICKET', montoTotal: 0)
            .tipoLabel,
        'Ticket',
      );
      expect(
        ComprobanteModel(numero: 'R', tipo: 'RECIBO', montoTotal: 0)
            .tipoLabel,
        'Recibo',
      );
      expect(
        ComprobanteModel(
                numero: 'N', tipo: 'NOTA_VENTA', montoTotal: 0)
            .tipoLabel,
        'Nota de venta',
      );
    });

    test('OrderModel parsea comprobante anidado', () {
      final json = {
        'id': 55,
        'numero_orden': 'ORD-000055',
        'cliente_id': 10,
        'total': 349.99,
        'estado': 'PAGADO',
        'detalles': [],
        'comprobante': {
          'numero': 'FAC-000123',
          'tipo': 'FACTURA',
          'fecha_emision': '2026-09-21T10:00:00Z',
          'monto_total': 349.99,
          'archivo_pdf': '/api/v1/ordenes/55/comprobante/pdf',
        },
      };

      final order = OrderModel.fromJson(json);
      expect(order.comprobante, isNotNull);
      expect(order.comprobante!.numero, 'FAC-000123');
    });

    test('OrderModel sin comprobante anidado queda en null', () {
      final json = {
        'id': 56,
        'numero_orden': 'ORD-000056',
        'cliente_id': 10,
        'total': 100,
        'estado': 'PENDIENTE',
        'detalles': [],
      };

      final order = OrderModel.fromJson(json);
      expect(order.comprobante, isNull);
    });
  });
}
