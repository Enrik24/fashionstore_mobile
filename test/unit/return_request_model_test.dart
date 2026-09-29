import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/models/return_request_model.dart';

void main() {
  group('ReturnRequestModel parsing (CU28)', () {
    test('fromJson con SolicitudDevolucionResponse del backend', () {
      final json = {
        'id': 1,
        'numero_solicitud': 'DEV-20260921-0001',
        'cliente_id': 10,
        'orden_id': 55,
        'sucursal_id': 2,
        'tipo': 'DEVOLUCION',
        'motivo': 'TALLA_INCORRECTA',
        'motivo_detalle': 'La talla M quedó pequeña',
        'estado': 'PENDIENTE',
        'monto_reembolso': '199.99',
        'observaciones_staff': null,
        'revisado_por_id': null,
        'fecha_solicitud': '2026-09-21T10:00:00Z',
        'fecha_resolucion': null,
        'detalles': [
          {
            'id': 1,
            'solicitud_id': 1,
            'detalle_orden_id': 101,
            'variante_producto_id': 7,
            'cantidad': 1,
            'variante_cambio_id': null,
            'precio_unitario': '199.99',
          },
        ],
      };

      final request = ReturnRequestModel.fromJson(json);
      expect(request.numeroSolicitud, 'DEV-20260921-0001');
      expect(request.ordenId, 55);
      expect(request.isCambio, isFalse);
      expect(request.motivo, 'TALLA_INCORRECTA');
      expect(request.estado, 'PENDIENTE');
      expect(request.montoReembolso, 199.99);
      expect(request.items, hasLength(1));
      expect(request.items.first.detalleOrdenId, 101);
      expect(request.items.first.varianteCambioId, isNull);
      expect(request.fechaSolicitud, isNotNull);
      expect(request.fechaResolucion, isNull);
    });

    test('solicitud de CAMBIO con variante de cambio', () {
      final json = {
        'id': 2,
        'numero_solicitud': 'DEV-20260921-0002',
        'orden_id': 56,
        'tipo': 'CAMBIO',
        'motivo': 'COLOR_INCORRECTO',
        'estado': 'APROBADA',
        'fecha_solicitud': '2026-09-21T11:00:00Z',
        'detalles': [
          {
            'id': 2,
            'solicitud_id': 2,
            'detalle_orden_id': 102,
            'cantidad': '2',
            'variante_cambio_id': 9,
            'precio_unitario': 150,
          },
        ],
      };

      final request = ReturnRequestModel.fromJson(json);
      expect(request.isCambio, isTrue);
      expect(request.items.first.cantidad, 2);
      expect(request.items.first.varianteCambioId, 9);
    });

    test('labels de motivos y estados', () {
      expect(MotivosDevolucion.label('TALLA_INCORRECTA'),
          'Talla incorrecta');
      expect(MotivosDevolucion.label('DEFECTO_FABRICA'),
          'Defecto de fábrica');
      expect(EstadosDevolucion.label('PENDIENTE_REEMBOLSO'),
          'Pendiente de reembolso');
      expect(EstadosDevolucion.label('COMPLETADA'), 'Completada');
      expect(MotivosDevolucion.todos, hasLength(4));
    });
  });
}
