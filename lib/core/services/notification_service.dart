import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import 'api_service.dart';
import 'storage_service.dart';
import '../database/local_database_service.dart';

/// Handler de mensajes en segundo plano (debe ser top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // El sistema muestra la notificación automáticamente; al tocarla,
  // `onMessageOpenedApp` / `getInitialMessage` resuelven la navegación.
}

/// Notificaciones push con Firebase Cloud Messaging (CU13, solo Android).
///
/// - Registra el token del dispositivo en el backend
///   (`POST /notificaciones/dispositivos`) tras el login.
/// - Lo desregistra al cerrar sesión.
/// - Al tocar una notificación navega a la sección correspondiente
///   (devoluciones, reservas u órdenes).
class NotificationService {
  final ApiService _apiService;
  final GlobalKey<ScaffoldMessengerState>? _messengerKey;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StorageService? _storageService;
  LocalDatabaseService? _localDatabase;

  // [EXAMEN-2] C2.6 CU09: tipos push soportados (FCM).
  static const String tipoPagoConfirmado = 'PAGO_CONFIRMADO';
  static const String tipoPagoRechazado = 'PAGO_RECHAZADO';
  static const String tipoConflictoNuevo = 'CONFLICTO_NUEVO';
  static const String tipoCuentaPorRegularizar = 'CUENTA_POR_REGULARIZAR';
  static const String tipoDispositivoRevocado = 'DISPOSITIVO_REVOCADO';
  // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): avisos de devolución, reposición,
  // compensación y falta de talla alternativa (RF-037, RN-024).
  static const String tipoDevolucion = 'DEVOLUCION';
  static const String tipoReposicion = 'REPOSICION';
  static const String tipoCompensacion = 'COMPENSACION';
  static const String tipoSinAlternativa = 'SIN_ALTERNATIVA';

  /// [EXAMEN-2] Inyecta dependencias para limpiar datos al revocarse el dispositivo.
  void configureOfflineRevocation({
    required StorageService storageService,
    required LocalDatabaseService localDatabase,
  }) {
    _storageService = storageService;
    _localDatabase = localDatabase;
  }

  String? _token;
  bool _initialized = false;

  NotificationService({
    required ApiService apiService,
    GlobalKey<ScaffoldMessengerState>? messengerKey,
  }) : _apiService = apiService,
       _messengerKey = messengerKey;

  String? get token => _token;
  bool get isInitialized => _initialized;

  /// Inicializa FCM: permiso, handler de fondo y listeners.
  Future<void> init() async {
    if (_initialized) return;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _messaging.requestPermission(alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onTapMessage);

      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        _onTapMessage(initial);
      }

      _messaging.onTokenRefresh.listen((newToken) {
        _token = newToken;
        // Se re-registra en el próximo login; si hay sesión, registrar ya.
        registerDevice();
      });

      _initialized = true;
    } catch (_) {
      // Sin Google Play Services o sin red: la app sigue funcionando.
    }
  }

  /// Obtiene el token FCM y lo registra en el backend (requiere sesión).
  Future<void> registerDevice() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      _token = token;
      await _apiService.dio.post(
        AppConstants.epNotificacionesDispositivos,
        data: {'token': token, 'tipo_dispositivo': 'android'},
      );
    } catch (_) {
      // Sin sesión o sin red: se reintenta en el próximo login.
    }
  }

  /// [EXAMEN-2] Elimina los datos del dispositivo revocado y vuelve al login.
  Future<void> handleDeviceRevoked() async {
    await _localDatabase?.eliminarArchivoLocal();
    await _storageService?.clearOfflineMode();
    final messenger = _messengerKey?.currentState;
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'Este dispositivo fue revocado. Se eliminaron los datos locales.',
        ),
      ),
    );
    try {
      appRouter.go('/login');
    } catch (_) {}
  }

  /// [EXAMEN-2] Desregistra el token en el backend y lo borra localmente (logout).
  Future<void> unregisterDevice() async {
    try {
      final token = _token;
      if (token != null && token.isNotEmpty) {
        await _apiService.dio.delete(
          AppConstants.epNotificacionesDispositivos,
          queryParameters: {'token': token},
        );
      }
    } catch (_) {
    } finally {
      _token = null;
      try {
        await _messaging.deleteToken();
      } catch (_) {}
    }
  }

  // [EXAMEN-2] Fase 3 (CU18/CU19): bandeja de avisos del cliente (RF-037).
  /// `GET /notificaciones/mis-notificaciones`; vacío ante 404/501 N3.
  Future<List<Map<String, Object?>>> getMisNotificaciones({
    String? estado,
    int skip = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _apiService.dio.get(
        AppConstants.epNotificacionesMis,
        queryParameters: {
          if (estado != null) 'estado': estado,
          'skip': skip,
          'limit': limit,
        },
      );
      if (response.data is Map<String, dynamic>) {
        final lista = (response.data as Map<String, dynamic>)['notificaciones'];
        if (lista is List) {
          return lista.map((e) => Map<String, Object?>.from(e)).toList();
        }
      }
      if (response.data is List) {
        return (response.data as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// [EXAMEN-2] Fase 3: `PATCH /notificaciones/{id}/leida` ( false ante 404).
  Future<bool> marcarLeida(int id) async {
    try {
      await _apiService.dio.patch(
        '${AppConstants.epNotificacionesLeida}/$id/leida',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mensaje con la app abierta: aviso en pantalla con acción "Ver".
  void _onForegroundMessage(RemoteMessage message) {
    final messenger = _messengerKey?.currentState;
    if (messenger == null) return;
    final title = message.notification?.title ?? 'FashionStore';
    final body = message.notification?.body ?? '';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          body.isNotEmpty ? '$title: $body' : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Ver',
          textColor: Colors.white,
          onPressed: () => _onTapMessage(message),
        ),
      ),
    );
  }

  /// Navega según el `tipo`/`url` que envía el backend.
  void _onTapMessage(RemoteMessage message) {
    try {
      appRouter.go(_resolveRoute(message.data));
    } catch (_) {}
  }

  /// Resuelve la ruta móvil desde el payload del backend.
  /// El backend envía `data: {tipo, url}` (p.ej. url `/profile/reservations`).
  static String resolveRoute(Map<String, dynamic> data) => _resolveRoute(data);

  static String _resolveRoute(Map<String, dynamic> data) {
    final url = data['url']?.toString() ?? '';
    // URLs válidas del móvil: perfil, reservas, órdenes y catálogo.
    if (url.startsWith('/profile/') ||
        url == '/profile' ||
        url.startsWith('/reservations') ||
        url.startsWith('/catalog') ||
        url == '/cart' ||
        url == '/home') {
      return url;
    }
    // URLs de panel staff/web (p.ej. /branch/...) se mapean por tipo.
    final tipo = (data['tipo']?.toString() ?? '').toUpperCase();
    // [EXAMEN-2] C2.6 CU09: tipos de sincronización.
    if (tipo == tipoConflictoNuevo) {
      return '/offline/conflicts';
    }
    if (tipo == tipoCuentaPorRegularizar) return '/profile';
    if (tipo == tipoDispositivoRevocado) return '/login';
    if (tipo.contains('DEVOLUC')) return '/profile/returns';
    if (tipo.contains('RESERV')) return '/reservations';
    // [CU13 restaurado] PAGO genérico (y PAGO_CONFIRMADO, esperado por el
    // test CU13 como orden/pago), ORDEN y VENTA van al historial.
    // El atajo previo PAGO_CONFIRMADO/PAGO_RECHAZADO -> /offline/payments
    // rompía ese mapeo; no se mantiene para no regresar la regresión.
    if (tipo.contains('PAGO') ||
        tipo.contains('ORDEN') ||
        tipo.contains('PEDIDO') ||
        tipo.contains('COMPRA') ||
        tipo.contains('VENTA')) {
      return '/profile/orders';
    }
    return '/home';
  }
}
