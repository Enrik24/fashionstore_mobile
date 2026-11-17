import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import 'config/config.dart';
import 'config/routes.dart';
import 'config/theme.dart';
import 'core/services/storage_service.dart';
import 'core/services/api_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/catalog_service.dart';
import 'core/services/cart_service.dart';
import 'core/services/reservation_service.dart';
import 'core/services/order_service.dart';
import 'core/services/ai_service.dart';
import 'core/services/favorites_service.dart';
import 'core/services/review_service.dart';
import 'core/services/coupon_service.dart';
import 'core/services/return_service.dart';
import 'core/services/promotion_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/device_service.dart';
import 'core/services/tenant_resolver.dart';
import 'core/services/local_crypto_service.dart';
import 'core/services/offline_session_service.dart';
import 'core/services/offline_config_service.dart';
import 'core/services/local_audit_service.dart';
// [EXAMEN-2] Fase 3 (CU13/CU18/CU19): servicios de devolución/reposición
// offline y compensación en modo cajero.
import 'core/services/compensation_service.dart';
import 'core/database/local_database_service.dart';
import 'core/database/repositories/local_config_repository.dart';
import 'core/database/repositories/local_permissions_repository.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/providers/offline_session_provider.dart';
import 'core/services/notification_service.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/catalog_provider.dart';
import 'core/providers/cart_provider.dart';
import 'core/providers/reservation_provider.dart';
import 'core/providers/checkout_provider.dart';
import 'core/providers/ai_provider.dart';
import 'core/providers/favorites_provider.dart';
import 'core/providers/review_provider.dart';
import 'core/providers/return_provider.dart';
import 'core/providers/recommendations_provider.dart';
import 'core/providers/promotions_provider.dart';
import 'core/services/offline_catalog_service.dart';
import 'core/services/offline_cart_service.dart';
import 'core/services/offline_document_service.dart';
import 'core/services/offline_queue_service.dart';
import 'core/services/sync_engine_service.dart';
import 'core/services/conflict_service.dart';
import 'core/services/pending_payment_service.dart';
import 'core/services/pos_service.dart';
// [EXAMEN-2] CU07/CU13/CU18: sucursal y cajero de la sesión para POS.
import 'core/services/pos_sesion_service.dart';
import 'core/services/realtime_service.dart';
import 'core/services/storage_quota_service.dart';
import 'core/providers/offline_catalog_provider.dart';
import 'core/providers/sync_provider.dart';
import 'core/providers/conflict_provider.dart';
import 'core/providers/pending_payment_provider.dart';
import 'core/providers/pos_provider.dart';
import 'core/providers/realtime_provider.dart';
// [EXAMEN-2] Fase 3 (CU13/CU18/CU19): providers de devolución/reposición
// offline y compensación en modo cajero.
import 'core/providers/offline_return_provider.dart';
import 'core/providers/compensation_provider.dart';

/// Messenger global para avisos de notificaciones en primer plano.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'rootScaffoldMessenger');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Datos de localizaciÃ³n para formatos de fecha en espaÃ±ol
  // (pantalla de reservas usa DateFormat con locale 'es_ES').
  try {
    await initializeDateFormatting('es_ES', null);
  } catch (_) {}

  // Initialize Local & Secure Storage
  final storageService = await StorageService.init();

  // Initialize Firebase (Push Notifications, solo Android con
  // google-services.json). Sin Google Play Services la app sigue funcionando.
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  if (AppConfig.stripePublishableKey.isNotEmpty) {
    Stripe.publishableKey = AppConfig.stripePublishableKey;
  }

  // Initialize Core Services
  final apiService = ApiService(storageService: storageService);
  final offlineClient = ApiServiceOfflineClient(apiService);
  final localCryptoService = LocalCryptoService();
  final localDatabaseService = LocalDatabaseService(
    storageService: storageService,
    cryptoService: localCryptoService,
  );
  try {
    await localDatabaseService.abrir();
  } catch (error) {
    // La app online continúa, pero el error queda disponible para que la UI
    // offline pueda explicar por qué no puede leer o guardar el paquete.
    await localDatabaseService.cerrar();
    localDatabaseService.registrarErrorApertura(error);
  }
  final deviceService = DeviceService(
    storageService: storageService,
    apiService: apiService,
    client: offlineClient,
    cryptoService: localCryptoService,
  );
  final connectivityService = ConnectivityService(client: offlineClient);
  final localConfigRepository = LocalConfigRepository(localDatabaseService);
  final localPermissionsRepository = LocalPermissionsRepository(
    localDatabaseService,
  );
  final offlineSessionService = OfflineSessionService(
    storageService: storageService,
    cryptoService: localCryptoService,
    deviceService: deviceService,
    client: offlineClient,
    configRepository: localConfigRepository,
    permissionsRepository: localPermissionsRepository,
    localDatabase: localDatabaseService,
  );
  await offlineSessionService.initialize();
  final offlineConfigService = OfflineConfigService(
    repository: localConfigRepository,
    client: offlineClient,
  );
  final localAuditService = LocalAuditService(localDatabaseService);
  final authService = AuthService(
    apiService: apiService,
    offlineSessionService: offlineSessionService,
    localDatabaseService: localDatabaseService,
  );
  late final CatalogService catalogService;
  late final CartService cartService;
  late final ReservationService reservationService;
  final orderService = OrderService(apiService: apiService);
  final aiService = AiService(apiService: apiService);
  final favoritesService = FavoritesService(apiService: apiService);
  final reviewService = ReviewService(apiService: apiService);
  final couponService = CouponService(apiService: apiService);
  // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): se instancian tras resolver el
  // tenant y la cola (ver más abajo).
  late final ReturnService returnService;
  late final CompensationService compensationService;
  final promotionService = PromotionService(apiService: apiService);
  final notificationService = NotificationService(
    apiService: apiService,
    messengerKey: rootScaffoldMessengerKey,
  );
  notificationService.configureOfflineRevocation(
    storageService: storageService,
    localDatabase: localDatabaseService,
  );
  apiService.onDeviceRevoked = notificationService.handleDeviceRevoked;
  // [EXAMEN-2] RN-019: si /offline/* responde "Dispositivo no registrado",
  // el interceptor intenta dar de alta el UUID local y reintentar una vez,
  // en lugar de borrar la sesión. Cubre instalaciones que iniciaron sesión
  // antes de que el alta automática existiera.
  apiService.onRegistrarDispositivo = () async {
    try {
      await deviceService.registrar();
      return true;
    } catch (_) {
      return false;
    }
  };
  try {
    await notificationService.init();
  } catch (_) {}

  // [EXAMEN-2] Servicios de Fase 2. El tenant se toma de la sesiÃ³n cacheada o
  // del Ãºltimo tenant offline; el backend sigue siendo la autoridad final.
  final tenantId = TenantResolver(storageService).resolver();
  final dispositivoId = await deviceService.dispositivoId;
  final realtimeService = RealtimeService(
    storageService: storageService,
    tenantId:
        storageService.getUser()?.tenantId ??
        storageService.readLastTenant() ??
        1,
  );
  // [EXAMEN-2] B0.4: el id del usuario debe quedar en TODA operación offline
  // (CU17 exige tenant_id + usuario_id + dispositivo_id + uuid_operacion).
  final usuarioId = storageService.getUser()?.id ?? 0;
  final offlineQueueService = OfflineQueueService(
    database: localDatabaseService,
    tenantId: tenantId,
    dispositivoId: dispositivoId,
    usuarioId: usuarioId > 0 ? usuarioId : null,
  );
  final offlineCatalogService = OfflineCatalogService(
    database: localDatabaseService,
    tenantId: tenantId,
    client: offlineClient,
  );
  late final OfflineCartService offlineCartService;
  // [EXAMEN-2] B1.2.a: el servicio de documentos se crea antes para poder
  // inyectarlo en el servicio de reservas (comprobante temporal de CU06).
  final offlineDocumentService = OfflineDocumentService(
    database: localDatabaseService,
    tenantId: tenantId,
  );
  catalogService = CatalogService(
    apiService: apiService,
    offline: offlineCatalogService,
  );
  reservationService = ReservationService(
    apiService: apiService,
    database: localDatabaseService,
    tenantId: tenantId,
    queue: offlineQueueService,
    // [EXAMEN-2] B0.4: el usuario queda estampado en cada fila local.
    usuarioId: usuarioId > 0 ? usuarioId : null,
    // [EXAMEN-2] B1.2.a: genera el comprobante temporal de la reserva offline.
    documents: offlineDocumentService,
  );
  final storageQuotaService = StorageQuotaService(
    database: localDatabaseService,
    tenantId: tenantId,
  );
  final syncEngineService = SyncEngineService(
    queue: offlineQueueService,
    client: offlineClient,
    connectivity: connectivityService,
    audit: localAuditService,
    tenantId: tenantId,
    dispositivoId: dispositivoId,
    // [EXAMEN-2] B1.5.i: limpieza de datos sincronizados y obsoletos.
    quotaService: storageQuotaService,
  );
  final conflictService = ConflictService(
    database: localDatabaseService,
    tenantId: tenantId,
    audit: localAuditService,
  );
  final pendingPaymentService = PendingPaymentService(
    database: localDatabaseService,
    tenantId: tenantId,
    client: offlineClient,
    audit: localAuditService,
    // [EXAMEN-2] B0.4.
    usuarioId: usuarioId > 0 ? usuarioId : null,
  );
  offlineCartService = OfflineCartService(
    database: localDatabaseService,
    tenantId: tenantId,
    dispositivoId: dispositivoId,
    client: offlineClient,
    queue: offlineQueueService,
    pendingPayments: pendingPaymentService,
    // [EXAMEN-2] B0.4.
    usuarioId: usuarioId > 0 ? usuarioId : null,
  );
  // [EXAMEN-2] B1.1.d: configuración del tenant para la vigencia de la orden
  // pendiente y la tasa de impuestos.
  offlineCartService.configurarRepositorioConfig(localConfigRepository);
  cartService = CartService(
    apiService: apiService,
    offline: offlineCartService,
    catalog: offlineCatalogService,
  );
  // [EXAMEN-2] C2.5 (§7.6) CU15: la bandera remota alimenta la guarda del
  // carrito offline; si la consulta falla se usa la copia local respaldada
  // en la tabla `configuracion` (OfflineConfigService).
  unawaited(
    offlineConfigService
        .obtenerConfiguracion(tenantId)
        .then((config) {
          cartService.habilitarCarritoOffline = config.habilitarCarritoOffline;
          // [EXAMEN-2] B2.1: si el tenant publicó su propia clave **pública**
          // de Stripe en el paquete offline, se usa esa (la de compilación es
          // sólo el valor por defecto de desarrollo). Nunca se persiste la
          // clave secreta (RNF-15).
          final clave = config.clavePublicaStripe;
          if (clave != null && clave.isNotEmpty) {
            Stripe.publishableKey = clave;
          }
          // [EXAMEN-2] B1.1.e: descarga automática del catálogo a la hora que
          // fija el tenant (`descarga_automatica` + `hora_descarga`).
          offlineCatalogService.programarDescargaAutomatica(config);
        })
        .catchError((Object _) {
          // Sin red: se respeta la copia local (valor por defecto true).
        }),
  );

  // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): crear offline con base local y cola.
  returnService = ReturnService(
    apiService: apiService,
    database: localDatabaseService,
    tenantId: tenantId,
    queue: offlineQueueService,
    audit: localAuditService,
    // [EXAMEN-2] B0.4.
    usuarioId: usuarioId > 0 ? usuarioId : null,
  );
  compensationService = CompensationService(
    database: localDatabaseService,
    tenantId: tenantId,
    apiService: apiService,
    audit: localAuditService,
    // [EXAMEN-2] B0.4.
    usuarioId: usuarioId > 0 ? usuarioId : null,
  );
  final posService = PosService(
    database: localDatabaseService,
    tenantId: tenantId,
    queue: offlineQueueService,
    apiService: apiService,
    // [EXAMEN-2] B0.4.
    usuarioId: usuarioId > 0 ? usuarioId : null,
  );
  // [EXAMEN-2] CU07/CU13/CU18: sucursal y cajero resueltos de la sesión
  // (persistencia + fallback al paquete offline descargado).
  final posSesionService = PosSesionService(
    database: localDatabaseService,
    storage: storageService,
    tenantId: tenantId,
  );
  // [EXAMEN-2] Fase 3 (CU19): aviso cuando el guarda de rol devuelve a /home.
  RolCajeroRedirect.onAviso = (mensaje) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  };
  // [EXAMEN-2] CU05/RNF-14: la descarga del paquete respeta la cuota local.
  offlineCatalogService.configurarQuota(storageQuotaService);
  // [EXAMEN-2] B1.1: el paquete offline trae `impuestos`, `stripe`,
  // `permisos` y `configuracion_offline`; el servicio los persiste.
  offlineCatalogService.configurarRepositorios(
    config: localConfigRepository,
    permissions: localPermissionsRepository,
  );
  // [FIX-SYNC] Normaliza las órdenes diferidas heredadas (payload con
  // `acepta_nuevo_total: false`) y deduplica los conflictos que dejaron los
  // reintentos en bucle, antes de habilitar los disparadores de sync.
  try {
    await offlineQueueService.normalizarOrdenesDiferidas();
  } catch (_) {
    // Best-effort: no bloquea el arranque.
  }
  // [FIX-SYNC] Al terminar cada sincronización (incluida la que dispara la
  // reconexión) se reenvían los pagos diferidos locales aún no creados en el
  // servidor y se refresca su estado.
  syncEngineService.reenviarPagosLocales =
      pendingPaymentService.reenviarPendientesLocales;
  await syncEngineService.registrarDisparadores();
  // [EXAMEN-2] B1.7.a: job de expiración de los pagos diferidos (RN-016).
  pendingPaymentService.programarExpiracion();
  // [EXAMEN-2] B1.4.d: el resultado de la sincronización se aplica también a
  // la fila local del dominio (devoluciones/reposiciones).
  offlineQueueService.aplicarResultadoDominio =
      (uuidOperacion, estado, detalle) async {
        // [EXAMEN-2] B2.4: si el servidor rechazó la reposición por falta de
        // talla alternativa, se le pide que notifique al cliente (RN-022/RN-024).
        final solicitudId =
            (detalle?['solicitud_id'] as num?)?.toInt() ??
            (detalle?['id_solicitud'] as num?)?.toInt();
        if (solicitudId != null && solicitudId > 0) {
          final motivo = detalle?['motivo']?.toString() ?? '';
          if (estado.toUpperCase().contains('SIN_ALTERNATIVA') ||
              motivo.toUpperCase().contains('SIN_ALTERNATIVA')) {
            await returnService.notificarSinAlternativa(solicitudId);
          }
        }
        await returnService.aplicarResultadoSync(
          uuidOffline: uuidOperacion,
          estado: estado,
          estadoSincronizacion: estado,
          numeroReposicion: detalle?['numero_reposicion']?.toString(),
        );
      };

  runApp(
    MultiProvider(
      providers: [
        // Services
        Provider<StorageService>.value(value: storageService),
        Provider<ApiService>.value(value: apiService),
        Provider<AuthService>.value(value: authService),
        Provider<CatalogService>.value(value: catalogService),
        Provider<CartService>.value(value: cartService),
        Provider<ReservationService>.value(value: reservationService),
        Provider<OrderService>.value(value: orderService),
        Provider<AiService>.value(value: aiService),
        Provider<FavoritesService>.value(value: favoritesService),
        Provider<ReviewService>.value(value: reviewService),
        Provider<CouponService>.value(value: couponService),
        Provider<ReturnService>.value(value: returnService),
        Provider<PromotionService>.value(value: promotionService),
        Provider<NotificationService>.value(value: notificationService),
        Provider<DeviceService>.value(value: deviceService),
        Provider<ConnectivityService>.value(value: connectivityService),
        Provider<LocalDatabaseService>.value(value: localDatabaseService),
        Provider<LocalCryptoService>.value(value: localCryptoService),
        Provider<OfflineSessionService>.value(value: offlineSessionService),
        Provider<OfflineConfigService>.value(value: offlineConfigService),
        Provider<LocalAuditService>.value(value: localAuditService),
        Provider<LocalConfigRepository>.value(value: localConfigRepository),
        Provider<LocalPermissionsRepository>.value(
          value: localPermissionsRepository,
        ),
        Provider<OfflineQueueService>.value(value: offlineQueueService),
        Provider<OfflineCatalogService>.value(value: offlineCatalogService),
        Provider<OfflineCartService>.value(value: offlineCartService),
        Provider<SyncEngineService>.value(value: syncEngineService),
        Provider<ConflictService>.value(value: conflictService),
        Provider<PendingPaymentService>.value(value: pendingPaymentService),
        Provider<PosService>.value(value: posService),
        Provider<PosSesionService>.value(value: posSesionService),
        Provider<StorageQuotaService>.value(value: storageQuotaService),
        Provider<OfflineDocumentService>.value(value: offlineDocumentService),
        Provider<RealtimeService>.value(value: realtimeService),
        ChangeNotifierProvider<RealtimeProvider>(
          create: (_) => RealtimeProvider(service: realtimeService),
        ),

        // Providers (State Management)
        ChangeNotifierProvider<CartProvider>(
          create: (_) => CartProvider(cartService: cartService),
        ),
        ChangeNotifierProvider<FavoritesProvider>(
          create: (_) => FavoritesProvider(favoritesService: favoritesService),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (context) => AuthProvider(
            authService: authService,
            storageService: storageService,
            cartProvider: context.read<CartProvider>(),
            favoritesProvider: context.read<FavoritesProvider>(),
            notificationService: notificationService,
            deviceService: deviceService,
          ),
        ),
        ChangeNotifierProvider<CatalogProvider>(
          create: (_) => CatalogProvider(catalogService: catalogService),
        ),
        ChangeNotifierProvider<ReservationProvider>(
          create: (_) =>
              ReservationProvider(reservationService: reservationService),
        ),
        ChangeNotifierProvider<CheckoutProvider>(
          create: (_) => CheckoutProvider(
            orderService: orderService,
            cartService: cartService,
          ),
        ),
        ChangeNotifierProvider<AiProvider>(
          create: (_) => AiProvider(aiService: aiService),
        ),
        ChangeNotifierProvider<ReviewProvider>(
          create: (_) => ReviewProvider(reviewService: reviewService),
        ),
        ChangeNotifierProvider<RecommendationsProvider>(
          create: (_) => RecommendationsProvider(
            aiService: aiService,
            catalogService: catalogService,
          ),
        ),
        ChangeNotifierProvider<PromotionsProvider>(
          create: (_) => PromotionsProvider(promotionService: promotionService),
        ),
        ChangeNotifierProvider<ReturnProvider>(
          create: (_) => ReturnProvider(returnService: returnService),
        ),
        ChangeNotifierProvider<ConnectivityProvider>(
          create: (_) =>
              ConnectivityProvider(connectivityService)..initialize(),
        ),
        ChangeNotifierProvider<OfflineSessionProvider>(
          create: (_) => OfflineSessionProvider(offlineSessionService),
        ),
        ChangeNotifierProvider<OfflineCatalogProvider>(
          create: (_) =>
              OfflineCatalogProvider(
                service: offlineCatalogService,
                // [EXAMEN-2] B1.1.j: el sello de descarga se persiste.
                storageService: storageService,
              )..cargarLocal(),
        ),
        ChangeNotifierProvider<SyncProvider>(
          create: (_) =>
              SyncProvider(service: syncEngineService)..cargarResumen(),
        ),
        ChangeNotifierProvider<ConflictProvider>(
          create: (_) => ConflictProvider(service: conflictService)..load(),
        ),
        ChangeNotifierProvider<PendingPaymentProvider>(
          create: (_) =>
              PendingPaymentProvider(service: pendingPaymentService)..load(),
        ),
        ChangeNotifierProvider<PosProvider>(
          create: (_) => PosProvider(
            service: posService,
            documentService: offlineDocumentService,
            sesion: posSesionService,
          ),
        ),
        // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): devoluciones, reposiciones y
        // compensaciones. El rol cajero lo resuelve AuthProvider al montar.
        Provider<CompensationService>.value(value: compensationService),
        ChangeNotifierProvider<OfflineReturnProvider>(
          create: (_) => OfflineReturnProvider(
            returnService: returnService,
            posService: posService,
            sesion: posSesionService,
          ),
        ),
        ChangeNotifierProvider<CompensationProvider>(
          create: (_) => CompensationProvider(
            service: compensationService,
            esCajero: false,
          ),
        ),
      ],
      child: const FashionStoreApp(),
    ),
  );
}

class FashionStoreApp extends StatefulWidget {
  const FashionStoreApp({super.key});

  @override
  State<FashionStoreApp> createState() => _FashionStoreAppState();
}

class _FashionStoreAppState extends State<FashionStoreApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final realtime = context.read<RealtimeProvider>();
      final auth = context.read<AuthProvider>();
      realtime.agregarEventoListener(_onRealtimeEvent);
      await realtime.iniciar();
      // [EXAMEN-2] CU19: refleja el rol cajero/encargado al provider.
      _actualizarRolCajero();
      auth.addListener(_actualizarRolCajero);
    });
  }

  void _actualizarRolCajero() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final roles =
        auth.currentUser?.roles
            .map((rol) => rol.nombre.toLowerCase())
            .toSet() ??
        const <String>{};
    final esCajero =
        roles.contains('cajero') ||
        roles.contains('encargado') ||
        roles.contains('encargado de sucursal') ||
        roles.contains('administrador');
    context.read<CompensationProvider>().setCajero(
      esCajero,
      auth.currentUser?.id ?? 0,
    );
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (!mounted) return;
    final tipo = event.type.toLowerCase();
    if (tipo.contains('pago')) {
      unawaited(context.read<PendingPaymentProvider>().load());
      unawaited(context.read<SyncProvider>().cargarResumen());
      return;
    }
    if (tipo.contains('stock') ||
        tipo.contains('catalogo') ||
        tipo.contains('sync')) {
      unawaited(context.read<CatalogProvider>().loadCatalog(refresh: true));
      unawaited(context.read<CartProvider>().loadCart());
      unawaited(context.read<ReservationProvider>().loadReservations());
      unawaited(context.read<SyncProvider>().cargarResumen());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // [EXAMEN-2] Al volver a segundo plano se intenta drenar la cola local.
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<SyncProvider>().refresh());
      unawaited(context.read<RealtimeProvider>().iniciar());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(context.read<RealtimeProvider>().detener());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FashionStore',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
    );
  }
}
