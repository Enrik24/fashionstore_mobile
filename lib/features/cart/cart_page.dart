import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/auth_provider.dart';
import 'widgets/cart_item_card.dart';
import 'widgets/cart_summary.dart';
import 'widgets/coupon_card.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _checkedOutOfStock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCart();
    });
  }

  /// Carga el carrito y retira automáticamente los ítems agotados (CU11).
  Future<void> _initCart() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    final provider = context.read<CartProvider>();
    await provider.loadCart();
    if (!mounted || _checkedOutOfStock) return;
    _checkedOutOfStock = true;
    final removed = await provider.removeOutOfStock();
    if (!mounted) return;
    if (removed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '$removed producto(s) se agotaron y fueron retirados del carrito'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  /// Verifica stock antes de ir al checkout (CU11).
  void _goToCheckout(CartProvider provider) {
    final excedidos = provider.itemsExceedingStock();
    if (excedidos.isNotEmpty) {
      final nombres =
          excedidos.map((e) => e.productoNombre).take(3).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Stock insuficiente para: $nombres. Ajusta las cantidades.'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    context.push('/checkout');
  }

  /// Reserva las prendas del carrito para probar en tienda (CU12).
  void _reserveFromCart(CartProvider provider) {
    final items = provider.items
        .map((e) => {
              'variante_producto_id': e.varianteProductoId,
              'cantidad': e.cantidad,
            })
        .toList();
    context.push('/reservations/create', extra: {'items': items});
  }

  void _confirmClearCart() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vaciar Carrito'),
        content: const Text('¿Estás seguro de que deseas eliminar todos los productos de tu carrito?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<CartProvider>().clearCart();
            },
            child: const Text('Vaciar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mi Carrito')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 72, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(
                  'Inicia sesión para ver tu carrito',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tus productos guardados estarán disponibles en cualquier dispositivo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('Iniciar Sesión'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mi Carrito'),
        actions: [
          Consumer<CartProvider>(
            builder: (context, provider, _) {
              if (provider.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.textSecondary),
                tooltip: 'Vaciar carrito',
                onPressed: _confirmClearCart,
              );
            },
          ),
        ],
      ),
      body: Consumer<CartProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          if (provider.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shopping_cart_outlined,
                        size: 64,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Tu carrito está vacío',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '¡Explora nuestro catálogo y descubre las últimas tendencias de moda!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => context.go('/catalog'),
                      icon: const Icon(Icons.storefront_outlined, color: Colors.white),
                      label: const Text('Explorar Catálogo', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => provider.loadCart(),
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = provider.items[index];
                      return CartItemCard(
                        item: item,
                        isUpdating: provider.isUpdating,
                        onQuantityChanged: (qty) {
                          provider.updateQuantity(item.id, qty);
                        },
                        onDelete: () {
                          provider.removeItem(item.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${item.productoNombre} eliminado'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                // Cupón de descuento (CU27)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: CouponCard(),
                ),
                // Reservar para probar (CU12) + resumen
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _reserveFromCart(provider),
                      icon: const Icon(Icons.bookmark_add_outlined,
                          size: 18),
                      label: const Text('Reservar para probar en tienda'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                            color: AppColors.primary),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                // Bottom Summary
                CartSummaryWidget(
                  subtotal: provider.subtotal,
                  discount: provider.cart.descuentoAplicado,
                  couponCode: provider.cart.cuponCodigo,
                  shippingCost: 0.0,
                  total: provider.total,
                  isLoading: provider.isUpdating,
                  onCheckout: () {
                    _goToCheckout(provider);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
