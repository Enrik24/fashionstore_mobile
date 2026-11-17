import 'package:fashionstore_mobile/features/offline/deferred_checkout_web_view_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checkout WebView dentro de la app (CU16)', () {
    const uuid = '6c24c7bd-1234-4abc-8def-0123456789ab';

    test('detecta la URL de éxito del backend con retorno=exito', () {
      const url =
          'https://fashionstore-frontend-smoky.vercel.app/checkout/pago-pendiente/$uuid?retorno=exito';
      expect(esRetornoCheckoutDiferido(url), isTrue);
      expect(esRetornoCancelado(url), isFalse);
    });

    test('detecta la URL de cancelación con retorno=cancelado', () {
      const url =
          'https://fashionstore-frontend-smoky.vercel.app/checkout/pago-pendiente/$uuid?retorno=cancelado';
      expect(esRetornoCheckoutDiferido(url), isTrue);
      expect(esRetornoCancelado(url), isTrue);
    });

    test('detecta las URLs del entorno local del backend', () {
      expect(
        esRetornoCheckoutDiferido(
          'http://localhost:4200/checkout/pago-pendiente/$uuid?retorno=exito',
        ),
        isTrue,
      );
      expect(
        esRetornoCheckoutDiferido('https://fashionstore.app/pago-exito'),
        isTrue,
      );
      expect(
        esRetornoCancelado('https://fashionstore.app/pago-cancelado'),
        isTrue,
      );
    });

    test('NO intercepta la URL del checkout de Stripe', () {
      expect(
        esRetornoCheckoutDiferido(
          'https://checkout.stripe.com/c/pay/cs_test_a1b2c3',
        ),
        isFalse,
      );
      expect(
        esRetornoCheckoutDiferido('not a url'),
        isFalse,
      );
    });
  });
}
