import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
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

/// Messenger global para avisos de notificaciones en primer plano.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'rootScaffoldMessenger');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Datos de localización para formatos de fecha en español
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

  // Initialize Core Services
  final apiService = ApiService(storageService: storageService);
  final authService = AuthService(apiService: apiService);
  final catalogService = CatalogService(apiService: apiService);
  final cartService = CartService(apiService: apiService);
  final reservationService = ReservationService(apiService: apiService);
  final orderService = OrderService(apiService: apiService);
  final aiService = AiService(apiService: apiService);
  final favoritesService = FavoritesService(apiService: apiService);
  final reviewService = ReviewService(apiService: apiService);
  final couponService = CouponService(apiService: apiService);
  final returnService = ReturnService(apiService: apiService);
  final promotionService = PromotionService(apiService: apiService);
  final notificationService = NotificationService(
    apiService: apiService,
    messengerKey: rootScaffoldMessengerKey,
  );
  try {
    await notificationService.init();
  } catch (_) {}

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
          ),
        ),
        ChangeNotifierProvider<CatalogProvider>(
          create: (_) => CatalogProvider(catalogService: catalogService),
        ),
        ChangeNotifierProvider<ReservationProvider>(
          create: (_) => ReservationProvider(reservationService: reservationService),
        ),
        ChangeNotifierProvider<CheckoutProvider>(
          create: (_) => CheckoutProvider(orderService: orderService),
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
          create: (_) =>
              PromotionsProvider(promotionService: promotionService),
        ),
        ChangeNotifierProvider<ReturnProvider>(
          create: (_) => ReturnProvider(returnService: returnService),
        ),
      ],
      child: const FashionStoreApp(),
    ),
  );
}

class FashionStoreApp extends StatelessWidget {
  const FashionStoreApp({super.key});

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
