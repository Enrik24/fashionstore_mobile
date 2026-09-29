import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/models/favorite_model.dart';

void main() {
  group('FavoriteModel parsing (CU25)', () {
    test('fromJson con producto anidado del backend', () {
      final json = {
        'id': 1,
        'cliente_id': 10,
        'producto_id': 25,
        'producto': {
          'id': 25,
          'sku': 'CAM-001',
          'nombre': 'Camisa Oxford',
          'precio': '199.99',
          'precio_oferta': 149.99,
          'imagenes': ['https://cdn.test/img1.jpg'],
          'estado': 'ACTIVO',
          'promedio_valoracion': '4.50',
          'total_valoraciones': 12,
        },
        'disponible': true,
        'fecha_agregado': '2026-09-20T10:00:00Z',
      };

      final fav = FavoriteModel.fromJson(json);
      expect(fav.id, 1);
      expect(fav.clienteId, 10);
      expect(fav.productoId, 25);
      expect(fav.producto.nombre, 'Camisa Oxford');
      expect(fav.producto.displayPrice, 149.99);
      expect(fav.producto.rating, 4.5);
      expect(fav.producto.totalReviews, 12);
      expect(fav.disponible, isTrue);
      expect(fav.fechaAgregado, isNotNull);
    });

    test('producto agotado se marca no disponible pero se conserva', () {
      final json = {
        'id': 2,
        'cliente_id': 10,
        'producto_id': 30,
        'producto': {
          'id': 30,
          'sku': 'PAN-002',
          'nombre': 'Pantalón',
          'precio': 250,
          'imagenes': [],
          'estado': 'AGOTADO',
        },
        'disponible': false,
        'fecha_agregado': '2026-09-19T08:00:00Z',
      };

      final fav = FavoriteModel.fromJson(json);
      expect(fav.disponible, isFalse);
      expect(fav.producto.nombre, 'Pantalón');
      expect(fav.producto.imagenes, isEmpty);
    });

    test('fromJson tolerante sin producto anidado', () {
      final json = {
        'id': 3,
        'cliente_id': '10',
        'producto_id': '40',
        'producto_nombre': 'Chaqueta',
        'disponible': true,
      };

      final fav = FavoriteModel.fromJson(json);
      expect(fav.productoId, 40);
      expect(fav.producto.nombre, 'Chaqueta');
    });
  });
}
