import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/models/review_model.dart';

void main() {
  group('ReviewModel parsing (CU26)', () {
    test('fromJson con ValoracionResponse del backend', () {
      final json = {
        'id': 5,
        'producto_id': 25,
        'cliente_id': 10,
        'cliente_nombre': 'Ana V.',
        'puntuacion': 5,
        'comentario': 'Excelente calidad',
        'estado': 'PUBLICADA',
        'fecha_creacion': '2026-09-20T10:00:00Z',
        'fecha_actualizacion': null,
      };

      final review = ReviewModel.fromJson(json);
      expect(review.id, 5);
      expect(review.productoId, 25);
      expect(review.clienteNombre, 'Ana V.');
      expect(review.puntuacion, 5);
      expect(review.comentario, 'Excelente calidad');
      expect(review.isPublicada, isTrue);
      expect(review.fechaCreacion, isNotNull);
      expect(review.fechaActualizacion, isNull);
    });

    test('valoración en moderación no cuenta como publicada', () {
      final json = {
        'id': 6,
        'producto_id': 25,
        'cliente_id': 11,
        'cliente_nombre': 'Luis P.',
        'puntuacion': '2',
        'comentario': 'Mala experiencia',
        'estado': 'PENDIENTE_MODERACION',
        'fecha_creacion': '2026-09-21T10:00:00Z',
      };

      final review = ReviewModel.fromJson(json);
      expect(review.puntuacion, 2);
      expect(review.isPublicada, isFalse);
    });

    test('CanReviewModel con valoración existente', () {
      final json = {
        'puede_valorar': true,
        'motivo': null,
        'valoracion_existente': {
          'id': 5,
          'producto_id': 25,
          'cliente_id': 10,
          'cliente_nombre': 'Ana V.',
          'puntuacion': 4,
          'comentario': null,
          'estado': 'PUBLICADA',
          'fecha_creacion': '2026-09-20T10:00:00Z',
        },
      };

      final can = CanReviewModel.fromJson(json);
      expect(can.puedeValorar, isTrue);
      expect(can.motivo, isNull);
      expect(can.valoracionExistente, isNotNull);
      expect(can.valoracionExistente!.puntuacion, 4);
    });

    test('CanReviewModel sin compra previa', () {
      final json = {
        'puede_valorar': false,
        'motivo': 'Debes comprar el producto para valorarlo',
        'valoracion_existente': null,
      };

      final can = CanReviewModel.fromJson(json);
      expect(can.puedeValorar, isFalse);
      expect(can.motivo, isNotNull);
      expect(can.valoracionExistente, isNull);
    });
  });
}
