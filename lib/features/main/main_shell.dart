import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/conflict_provider.dart';
import '../../core/providers/pending_payment_provider.dart';
import '../../core/providers/sync_provider.dart';
import '../offline/widgets/sync_status_banner.dart';
import '../offline/widgets/offline_data_stamp.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SyncStatusBanner(),
          const OfflineDataStamp(),
          Consumer3<SyncProvider, ConflictProvider, PendingPaymentProvider>(
            builder: (context, sync, conflicts, payments, _) {
              final pending = sync.pendingCount;
              final conflictCount = conflicts.pendingCount;
              final paymentCount = payments.pendingCount;
              if (pending == 0 && conflictCount == 0 && paymentCount == 0) {
                return const SizedBox.shrink();
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    if (pending > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.sync, size: 18),
                          label: Text('Pendientes: $pending'),
                          onPressed: () => context.push('/offline/sync'),
                        ),
                      ),
                    if (conflictCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.merge_type, size: 18),
                          label: Text('Conflictos: $conflictCount'),
                          onPressed: () => context.push('/offline/conflicts'),
                        ),
                      ),
                    if (paymentCount > 0)
                      ActionChip(
                        avatar: const Icon(Icons.schedule_outlined, size: 18),
                        label: Text('Pagos: $paymentCount'),
                        onPressed: () => context.push('/offline/payments'),
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Consumer<CartProvider>(
          builder: (context, cartProvider, child) {
            final cartCount = cartProvider.itemCount;

            return BottomNavigationBar(
              currentIndex: navigationShell.currentIndex,
              onTap: (index) => _onTap(context, index),
              selectedItemColor: AppColors.accent,
              unselectedItemColor: AppColors.textSecondary,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppColors.surface,
              elevation: 0,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home_rounded),
                  label: 'Inicio',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.grid_view_outlined),
                  activeIcon: Icon(Icons.grid_view_rounded),
                  label: 'Catálogo',
                ),
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: cartCount > 0,
                    label: Text(
                      '$cartCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: AppColors.accent,
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                  activeIcon: Badge(
                    isLabelVisible: cartCount > 0,
                    label: Text(
                      '$cartCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: AppColors.accent,
                    child: const Icon(Icons.shopping_cart_rounded),
                  ),
                  label: 'Carrito',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.bookmark_outline_rounded),
                  activeIcon: Icon(Icons.bookmark_rounded),
                  label: 'Reservas',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded),
                  activeIcon: Icon(Icons.person_rounded),
                  label: 'Perfil',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
