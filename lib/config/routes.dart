import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/models/order_model.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/offline_session_provider.dart';
import '../core/models/product_model.dart';
import '../features/splash/splash_screen.dart';
import '../features/auth/login/login_page.dart';
import '../features/auth/register/register_page.dart';
import '../features/auth/change_password/change_password_page.dart';
import '../features/main/main_shell.dart';
import '../features/home/home_page.dart';
import '../features/catalog/catalog_page.dart';
import '../features/catalog/search/search_page.dart';
import '../features/catalog/product_detail/product_detail_page.dart';
import '../features/cart/cart_page.dart';
import '../features/checkout/checkout_page.dart';
import '../features/checkout/order_success_page.dart';
import '../features/checkout/stripe_webview_page.dart';
import '../features/reservations/reservations_page.dart';
import '../features/reservations/reservation_detail_page.dart';
import '../features/reservations/create_reservation/create_reservation_page.dart';
import '../features/reservations/create_reservation/branch_selector_page.dart';
import '../features/profile/profile_page.dart';
import '../features/profile/edit_profile/edit_profile_page.dart';
import '../features/profile/favorites/favorites_page.dart';
import '../features/profile/orders/orders_history_page.dart';
import '../features/profile/orders/order_detail_page.dart';
import '../features/profile/returns/my_returns_page.dart';
import '../features/profile/returns/return_detail_page.dart';
import '../features/profile/returns/request_return_page.dart';
import '../features/ai_assistant/ai_assistant_page.dart';
import '../features/ar_fitting/ar_fitting_page.dart';
import '../features/offline/offline_access_page.dart';
import '../features/offline/offline_pin_setup_page.dart';
import '../features/offline/offline_devices_page.dart';
import '../features/offline/offline_download_page.dart';
import '../features/offline/sync_center_page.dart';
import '../features/offline/conflicts_page.dart';
import '../features/offline/pending_payments_page.dart';
import '../features/pos/pos_home_page.dart';
import '../features/pos/pos_sale_page.dart';
import '../features/pos/barcode_scanner_page.dart';
// [EXAMEN-2] Fase 3 (CU13/CU18/CU19): rutas POS con guarda de rol cajero.
import '../features/pos/return/pos_return_page.dart';
import '../features/pos/exchange/pos_exchange_page.dart';
import '../features/pos/compensations/pos_compensations_page.dart';
import '../features/pos/sale/sale_receipt_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

// [EXAMEN-2] Fase 3 (CU13/CU18/CU19): el guarda de rol notifica con un aviso
// al volver a /home. main.dart registra el callback (SnackBar global).
class RolCajeroRedirect {
  const RolCajeroRedirect._();
  static void Function(String mensaje)? onAviso;
}

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  redirect: (context, state) {
    final uri = state.uri.path;
    // [EXAMEN-2] Las pantallas operativas exigen sesión online u offline.
    final rutaProtegida =
        uri == '/home' ||
        uri.startsWith('/catalog') ||
        uri == '/cart' ||
        uri.startsWith('/checkout') ||
        uri.startsWith('/profile') ||
        uri.startsWith('/reservations') ||
        uri == '/offline/download' ||
        uri == '/offline/sync' ||
        uri == '/offline/conflicts' ||
        uri == '/offline/payments' ||
        uri.startsWith('/pos');
    if (!rutaProtegida) return null;
    try {
      final auth = context.read<AuthProvider>();
      final offline = context.read<OfflineSessionProvider>();
      // [EXAMEN-2] C1.2: sesión vencida => solo consulta de catálogo.
      final soloConsulta = offline.sesionVencida;
      final puedeOperar =
          auth.isAuthenticated ||
          (offline.sesionLocalActiva && offline.haySesionValida);
      if (!puedeOperar) {
        if (soloConsulta) {
          final esConsulta =
              uri == '/home' || uri.startsWith('/catalog');
          if (esConsulta) return null;
          return '/home';
        }
        return offline.pinConfigurado ? '/offline/access' : '/login';
      }
      // [EXAMEN-2] Guarda de rol para el POS. El backend conserva la
      // autoridad sobre permisos; la app solo oculta funciones no autorizadas.
      if (uri.startsWith('/pos')) {
        final roles =
            auth.currentUser?.roles
                .map((rol) => rol.nombre.toLowerCase())
                .toSet() ??
            const <String>{};
        final permitido =
            roles.contains('cajero') ||
            roles.contains('encargado') ||
            roles.contains('encargado de sucursal') ||
            roles.contains('administrador');
        if (!permitido) {
          // [EXAMEN-2] Fase 3: sin rol Cajero/Encargado → /home con aviso.
          RolCajeroRedirect.onAviso?.call(
            'Solo el personal de tienda (cajero/encargado) puede usar el POS.',
          );
          return '/home';
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  },
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/change-password',
      builder: (context, state) => const ChangePasswordPage(),
    ),
    // [EXAMEN-2] CU17: acceso, configuración PIN y dispositivos.
    GoRoute(
      path: '/offline/access',
      builder: (context, state) => const OfflineAccessPage(),
    ),
    GoRoute(
      path: '/offline/pin',
      builder: (context, state) => const OfflinePinSetupPage(),
    ),
    GoRoute(
      path: '/offline/devices',
      builder: (context, state) => const OfflineDevicesPage(),
    ),
    // [EXAMEN-2] Fase 2: catálogo, sincronización, conflictos y pagos.
    GoRoute(
      path: '/offline/download',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OfflineDownloadPage(),
    ),
    GoRoute(
      path: '/offline/sync',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SyncCenterPage(),
    ),
    GoRoute(
      path: '/offline/conflicts',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ConflictsPage(),
    ),
    GoRoute(
      path: '/offline/payments',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PendingPaymentsPage(),
    ),
    GoRoute(
      path: '/pos',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PosHomePage(),
    ),
    GoRoute(
      path: '/pos/barcode',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BarcodeScannerPage(),
    ),
    GoRoute(
      path: '/pos/sale',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PosSalePage(),
    ),
    // [EXAMEN-2] C2.8: alias canónico del plan §6.1 junto a /pos/barcode.
    GoRoute(
      path: '/pos/sale/scan',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BarcodeScannerPage(),
    ),
    // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): guarda de rol cajero heredada de
    // /pos (Cajero/Encargado/Administrador; resto → /home con aviso).
    GoRoute(
      path: '/pos/return',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PosReturnPage(),
    ),
    GoRoute(
      path: '/pos/exchange',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PosExchangePage(),
    ),
    GoRoute(
      path: '/pos/compensations',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PosCompensationsPage(),
    ),
    GoRoute(
      path: '/pos/sale/receipt',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra is Map<String, dynamic>
            ? state.extra as Map<String, dynamic>
            : <String, dynamic>{};
        return SaleReceiptPage(
          uuidOffline: extra['uuidOffline']?.toString() ?? '',
          titulo: extra['titulo']?.toString() ?? 'Comprobante temporal',
          diferenciaPrecio: (extra['diferenciaPrecio'] as num?)?.toDouble(),
          tipoDiferencia: extra['tipoDiferencia']?.toString(),
          saldoFavor: (extra['saldoFavor'] as num?)?.toDouble(),
          rutaPdf: extra['rutaPdf']?.toString(),
        );
      },
    ),

    // Standalone detail & flow routes
    GoRoute(
      path: '/catalog/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return ProductDetailPage(productId: id);
      },
    ),
    GoRoute(
      path: '/search',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SearchPage(),
    ),
    GoRoute(
      path: '/checkout',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CheckoutPage(),
    ),
    GoRoute(
      path: '/checkout/stripe',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra is Map<String, dynamic>
            ? state.extra as Map<String, dynamic>
            : <String, dynamic>{};
        return StripeWebViewPage(
          order: extra['order'] as OrderModel,
          checkoutUrl: extra['checkoutUrl']?.toString() ?? '',
          sessionId: extra['sessionId']?.toString() ?? '',
        );
      },
    ),
    GoRoute(
      path: '/checkout/success',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        // Compat: antes se pasaba el OrderModel directo; ahora un Map con
        // la orden + IDs de pasarela para verificar el pago.
        OrderModel? order;
        String? stripeSessionId;
        String? paypalOrderId;
        if (state.extra is OrderModel) {
          order = state.extra as OrderModel;
        } else if (state.extra is Map<String, dynamic>) {
          final extra = state.extra as Map<String, dynamic>;
          order = extra['order'] as OrderModel?;
          stripeSessionId = extra['stripeSessionId']?.toString();
          paypalOrderId = extra['paypalOrderId']?.toString();
        }
        return OrderSuccessPage(
          order: order,
          stripeSessionId: stripeSessionId,
          paypalOrderId: paypalOrderId,
        );
      },
    ),
    GoRoute(
      path: '/reservations/create',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra is Map<String, dynamic>
            ? state.extra as Map<String, dynamic>
            : <String, dynamic>{};
        final rawItems = extra['items'];
        return CreateReservationPage(
          product: extra['product'] as ProductModel?,
          variant: extra['variant'] as VarianteProducto?,
          quantity: extra['quantity'] as int? ?? 1,
          initialBranchId: extra['sucursalId'] as int?,
          initialItems: rawItems is List
              ? rawItems.whereType<Map<String, dynamic>>().toList()
              : null,
        );
      },
    ),
    GoRoute(
      path: '/reservations/branch-select',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BranchSelectorPage(),
    ),
    GoRoute(
      path: '/reservations/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return ReservationDetailPage(reservationId: id);
      },
    ),

    // Profile & Orders routes
    GoRoute(
      path: '/profile/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const EditProfilePage(),
    ),
    GoRoute(
      path: '/favorites',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FavoritesPage(),
    ),
    GoRoute(
      path: '/profile/orders',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OrdersHistoryPage(),
    ),
    GoRoute(
      path: '/profile/orders/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return OrderDetailPage(orderId: id);
      },
    ),
    GoRoute(
      path: '/profile/orders/:id/return',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return RequestReturnPage(orderId: id);
      },
    ),
    GoRoute(
      path: '/profile/returns',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const MyReturnsPage(),
    ),
    GoRoute(
      path: '/profile/returns/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return ReturnDetailPage(solicitudId: id);
      },
    ),

    // AI & Virtual Fitting routes
    GoRoute(
      path: '/ai-assistant',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AiAssistantPage(),
    ),
    GoRoute(
      path: '/ar-fitting',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final productIdStr = state.uri.queryParameters['productId'];
        final prodId = productIdStr != null ? int.tryParse(productIdStr) : null;
        return ArFittingPage(initialProductId: prodId);
      },
    ),

    // Bottom Navigation Shell
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        // Tab 0: Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomePage(),
            ),
          ],
        ),

        // Tab 1: Catalog
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/catalog',
              builder: (context, state) => const CatalogPage(),
            ),
          ],
        ),

        // Tab 2: Cart
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cart',
              builder: (context, state) => const CartPage(),
            ),
          ],
        ),

        // Tab 3: Reservations
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/reservations',
              builder: (context, state) => const ReservationsPage(),
            ),
          ],
        ),

        // Tab 4: Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfilePage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
