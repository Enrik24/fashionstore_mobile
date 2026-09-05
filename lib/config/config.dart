import 'package:flutter/foundation.dart';

class AppConfig {
  static const String appName = 'FashionStore';
  static const String appVersion = '1.0.0';
  
  /// Base API URL.
  /// Uses 10.0.2.2 for Android Emulator, localhost for iOS/Web/Desktop, or custom host.
  static String get apiBaseUrl {
    if (kIsWeb) {
      return 'http://192.168.100.30:8000/api/v1';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://192.168.100.30:8000/api/v1';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      default:
        return 'http://192.168.100.30:8000/api/v1';
    }
  }

  static const String currency = 'BOB';
  static const String currencySymbol = 'Bs.';
  static const String locale = 'es-BO';
  
  static const int connectTimeoutSeconds = 15;
  static const int receiveTimeoutSeconds = 15;
}
