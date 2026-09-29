import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/models/coupon_model.dart';

void main() {
  group('CouponModel parsing (CU27)', () {
    test('fromJson con CuponResponse del backend', () {
      final json = {
        'id': 1,
        'codigo': 'BIENVENIDA10',
        'tipo': 'PORCENTAJE',
        'valor': '10.00',
        'descripcion': '10% en tu primera compra',
        'fecha_inicio': '2026-01-01T00:00:00Z',
        'fecha_fin': '2026-12-31T23:59:59Z',
        'usos_maximos': 100,
        'usos_actuales': 5,
        'monto_minimo': '150.00',
        'estado': 'ACTIVO',
        'producto_ids': [],
        'categoria_ids': [],
      };

      final coupon = CouponModel.fromJson(json);
      expect(coupon.codigo, 'BIENVENIDA10');
      expect(coupon.isPorcentaje, isTrue);
      expect(coupon.valor, 10.0);
      expect(coupon.aplicaATodo, isTrue);
      expect(coupon.valorLabel, '10% OFF');
      expect(coupon.montoMinimo, 150.0);
      expect(coupon.fechaFin, isNotNull);
    });

    test('cupón con aplicabilidad restringida', () {
      final json = {
        'id': 2,
        'codigo': 'MUJER20',
        'tipo': 'MONTO_FIJO',
        'valor': 20,
        'estado': 'ACTIVO',
        'producto_ids': [1, 2, 3],
        'categoria_ids': [5],
        'usos_actuales': 0,
      };

      final coupon = CouponModel.fromJson(json);
      expect(coupon.isPorcentaje, isFalse);
      expect(coupon.aplicaATodo, isFalse);
      expect(coupon.productoIds, [1, 2, 3]);
      expect(coupon.valorLabel, 'Bs. 20.00 OFF');
    });

    test('CouponValidationResult con descuento calculado', () {
      final json = {
        'valido': true,
        'mensaje': 'Cupón aplicado correctamente',
        'cupon': {
          'id': 1,
          'codigo': 'BIENVENIDA10',
          'tipo': 'PORCENTAJE',
          'valor': 10,
          'estado': 'ACTIVO',
          'usos_actuales': 5,
        },
        'descuento_calculado': '25.50',
      };

      final result = CouponValidationResult.fromJson(json);
      expect(result.valido, isTrue);
      expect(result.mensaje, isNotEmpty);
      expect(result.cupon, isNotNull);
      expect(result.cupon!.codigo, 'BIENVENIDA10');
      expect(result.descuentoCalculado, 25.5);
    });

    test('CouponValidationResult inválido sin cupón', () {
      final json = {
        'valido': false,
        'mensaje': 'El cupón no es aplicable a los productos del carrito',
        'cupon': null,
        'descuento_calculado': '0.00',
      };

      final result = CouponValidationResult.fromJson(json);
      expect(result.valido, isFalse);
      expect(result.cupon, isNull);
      expect(result.descuentoCalculado, 0.0);
    });
  });
}
