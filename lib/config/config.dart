class AppConfig {
  static const String appName = 'FashionStore';
  static const String appVersion = '1.0.0';

  /// URL del backend configurable al compilar:
  /// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000`.
  ///
  /// Se acepta tanto la raíz del servidor como una URL que ya termine en
  /// `/api/v1`. Render continúa siendo el destino predeterminado.
  static const String _apiBaseUrlConfigurada = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://fashionstore-backend-production-c05430ab.up.railway.app/api/v1',
  );

  static String get apiBaseUrl {
    var url = _apiBaseUrlConfigurada.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api/v1')) return url;
    return '$url/api/v1';
  }

  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );

  static const String currency = 'BOB';
  static const String currencySymbol = 'Bs.';
  static const String locale = 'es-BO';

  static const int connectTimeoutSeconds = 15;
  static const int receiveTimeoutSeconds = 15;

  /// URLs de la tienda web para redirigir al cliente después de pagar en la
  /// pasarela hospedada (Stripe Checkout / PayPal).
  /// Se inyectan al compilar con:
  ///   --dart-define=PAYMENT_SUCCESS_URL=https://TU-FRONTEND.com/checkout/success
  ///   --dart-define=PAYMENT_CANCEL_URL=https://TU-FRONTEND.com/checkout/cancel
  /// Si quedan vacías, el backend usa sus propias STRIPE_SUCCESS_URL / STRIPE_CANCEL_URL.
  static const String paymentSuccessUrl = String.fromEnvironment(
    'PAYMENT_SUCCESS_URL',
  );
  static const String paymentCancelUrl = String.fromEnvironment(
    'PAYMENT_CANCEL_URL',
  );

  // [EXAMEN-2] C1.4/C2.2/C2.8: contrato offline y reglas de sincronización (§15.1).
  static const String versionContratoSync = '1.0';
  static const int offlineLoteMaximo = 50;
  static const int offlineBackoffBaseSegundos = 2;
  static const int offlineBackoffMaximoSegundos = 300;
  static const int offlineEspacioMaximoMb = 200;
  static const int offlineDiasConservarConfirmadas = 30;
  static const String stripePublishableKeyFallback = '';
  static const int pinLongitudMinima = 6;
  static const int pinIntentosMaximos = 5;
  static const bool habilitarSincronizacionWebSocket = true;
}
