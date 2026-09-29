import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/models/order_model.dart';
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

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/change-password',
      builder: (context, state) => const ChangePasswordPage(),
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
              ? rawItems
                  .whereType<Map<String, dynamic>>()
                  .toList()
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
