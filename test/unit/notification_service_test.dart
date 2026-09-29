import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/services/notification_service.dart';

void main() {
  group('NotificationService.resolveRoute (tap en push, CU13)', () {
    test('respeta urls válidas del móvil', () {
      expect(
        NotificationService.resolveRoute({'url': '/profile/returns'}),
        '/profile/returns',
      );
      expect(
        NotificationService.resolveRoute({'url': '/reservations'}),
        '/reservations',
      );
      expect(
        NotificationService.resolveRoute({'url': '/profile/orders/5'}),
        '/profile/orders/5',
      );
    });

    test('mapea tipos de devolución a Mis Devoluciones', () {
      expect(
        NotificationService.resolveRoute({
          'tipo': 'DEVOLUCION_APROBADA',
          'url': '/branch/returns',
        }),
        '/profile/returns',
      );
    });

    test('mapea tipos de reserva a Mis Reservas', () {
      expect(
        NotificationService.resolveRoute({
          'tipo': 'RESERVA_PREPARADA',
          'url': '/branch/reservations',
        }),
        '/reservations',
      );
    });

    test('mapea tipos de orden/pago al historial', () {
      expect(
        NotificationService.resolveRoute({'tipo': 'PAGO_CONFIRMADO'}),
        '/profile/orders',
      );
    });

    test('sin datos va al home', () {
      expect(NotificationService.resolveRoute({}), '/home');
    });
  });
}
