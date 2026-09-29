import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/models/ai_model.dart';
import 'package:fashionstore_mobile/core/models/product_model.dart';

Map<String, dynamic> _productJson(int id, String genero) => {
      'id': id,
      'sku': 'SKU-$id',
      'nombre': 'Prenda $id',
      'precio': 100.0 + id,
      'imagenes': [],
      'estado': 'ACTIVO',
      'genero': genero,
      'promedio_valoracion': '4.00',
      'total_valoraciones': 5,
    };

void main() {
  group('Paginación del catálogo (formato real del backend)', () {
    test('parsea pagina/total_paginas sin page_size', () {
      final json = {
        'items': [_productJson(1, 'HOMBRE'), _productJson(2, 'MUJER')],
        'total': 30,
        'pagina': 1,
        'total_paginas': 3,
      };

      final resp = CatalogoResponse.fromJson(json);
      expect(resp.items, hasLength(2));
      expect(resp.total, 30);
      expect(resp.page, 1);
      // Clave del bug: antes se calculaba ceil(30/20)=2 y faltaba la
      // última página; ahora se usa total_paginas=3 del backend.
      expect(resp.totalPages, 3);
    });

    test('tolera formato alternativo page/page_size/total_pages', () {
      final json = {
        'items': [_productJson(1, 'UNISEX')],
        'total': 25,
        'page': 2,
        'page_size': 12,
        'total_pages': 3,
      };

      final resp = CatalogoResponse.fromJson(json);
      expect(resp.page, 2);
      expect(resp.pageSize, 12);
      expect(resp.totalPages, 3);
    });

    test('ProductModel parsea genero', () {
      final p = ProductModel.fromJson(_productJson(7, 'MUJER'));
      expect(p.genero, 'MUJER');
      expect(p.rating, 4.0);
      expect(p.totalReviews, 5);
    });
  });

  group('RecomendacionItem (endpoint /inteligencia/recomendaciones)', () {
    test('fromJson con todos los campos del backend', () {
      final json = {
        'producto_id': 10,
        'nombre': 'Camisa Oxford',
        'razon': 'Coincide con tu estilo casual',
        'imagen_url': null,
        'imagenes': ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
        'precio': 199.99,
        'categoria': 'Camisas',
        'genero': 'HOMBRE',
        'sku': 'CAM-001',
      };

      final rec = RecomendacionItem.fromJson(json);
      expect(rec.productoId, 10);
      expect(rec.imagenes, hasLength(2));
      expect(rec.genero, 'HOMBRE');
      expect(rec.sku, 'CAM-001');
      expect(rec.precio, 199.99);
    });

    test('usa imagen_url cuando no hay lista de imagenes', () {
      final json = {
        'producto_id': 11,
        'nombre': 'Vestido',
        'razon': 'Tendencia',
        'imagen_url': 'https://cdn.test/v.jpg',
        'imagenes': [],
        'precio': 250,
      };

      final rec = RecomendacionItem.fromJson(json);
      expect(rec.imagenes, ['https://cdn.test/v.jpg']);
      expect(rec.imagenUrl, 'https://cdn.test/v.jpg');
    });

    test('RecomendacionResponse con estilo y mensaje', () {
      final json = {
        'cliente_id': 1,
        'estilo_detectado': 'Casual elegante',
        'mensaje_personalizado': 'Elegimos esto para ti',
        'recomendaciones': [
          {
            'producto_id': 1,
            'nombre': 'P1',
            'razon': 'R1',
            'precio': 100,
          },
        ],
      };

      final resp = RecomendacionResponse.fromJson(json);
      expect(resp.estiloDetectado, 'Casual elegante');
      expect(resp.mensajePersonalizado, 'Elegimos esto para ti');
      expect(resp.recomendaciones, hasLength(1));
    });
  });
}
