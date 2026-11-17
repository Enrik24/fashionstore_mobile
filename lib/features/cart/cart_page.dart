import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../core/models/cart_model.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/cart_service.dart';
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
            '$removed producto(s) se agotaron y fueron retirados del carrito',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  /// Verifica stock antes de ir al checkout (CU11).
  void _goToCheckout(CartProvider provider) {
    final excedidos = provider.itemsExceedingStock();
    if (excedidos.isNotEmpty) {
      final nombres = excedidos.map((e) => e.productoNombre).take(3).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stock insuficiente para: $nombres. Ajusta las cantidades.',
          ),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    context.push('/checkout');
  }

  /// [EXAMEN-2] B1.6.d: reconciliación con el servidor (RN-014).
  ///
  /// Al recuperar la conexión el servidor recalcula precios, impuestos y
  /// total. Si el total cambió, el cliente **debe aceptarlo antes de
  /// cobrar**; si no lo acepta, se cancela la orden.
  Future<void> _validarConServidor(CartProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = await provider.validarContraServidor();
    if (!mounted) return;
    final nuevo = provider.nuevoTotalServidor;
    if (data == null || nuevo == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.errorMessage ??
                'No se pudo validar el carrito con el servidor.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    final acepta = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('El precio cambió'),
        content: Text(
          'El servidor recalculó el total con los precios, impuestos y '
          'descuentos vigentes.\n\n'
          'Total local: ${provider.total.toStringAsFixed(2)}\n'
          'Total del servidor: ${nuevo.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Aceptar nuevo total'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (acepta != true) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se aceptó el nuevo total: la orden se cancela.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    final ok = await provider.aceptarNuevoTotal();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Nuevo total aceptado: ${provider.total.toStringAsFixed(2)}'
              : provider.errorMessage ?? 'No se pudo aceptar el nuevo total',
        ),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  /// Reserva las prendas del carrito para probar en tienda (CU12).
  void _reserveFromCart(CartProvider provider) {
    final items = provider.items
        .map(
          (e) => {
            'variante_producto_id': e.varianteProductoId,
            'cantidad': e.cantidad,
          },
        )
        .toList();
    context.push('/reservations/create', extra: {'items': items});
  }

  /// [EXAMEN-2] §19 (CU15): ítems offline cuya cantidad excede el stock
  /// referencial guardado en el paquete standalone.
  List<CartItemModel> _itemsStockReferencial(CartProvider provider) => provider
      .items
      .where((item) {
        final local = item.stockLocalConocido;
        return local != null && item.cantidad > local;
      })
      .toList();

  void _confirmClearCart() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vaciar Carrito'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar todos los productos de tu carrito?',
        ),
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
            child: const Text(
              'Vaciar',
              style: TextStyle(color: AppColors.error),
            ),
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
                const Icon(
                  Icons.shopping_bag_outlined,
                  size: 72,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Inicia sesión para ver tu carrito',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  color: AppColors.textSecondary,
                ),
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
                      icon: const Icon(
                        Icons.storefront_outlined,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Explorar Catálogo',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
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
                // [EXAMEN-2] B1.6.j: si el tenant tiene el carrito offline
                // deshabilitado, sólo se permite consultar (no comprar sin
                // conexión).
                if (provider.carritoOfflineDeshabilitado)
                  _AvisoBanner(
                    icon: Icons.block_outlined,
                    color: AppColors.warning,
                    text: CartService.mensajeCarritoOfflineDeshabilitado,
                  )
                else if (provider.esOffline)
                  const _AvisoBanner(
                    icon: Icons.cloud_off_outlined,
                    color: AppColors.info,
                    text:
                        'Estás sin conexión: precios y stock son referenciales '
                        'y se confirmarán al sincronizar.',
                  ),
                // [EXAMEN-2] §19 (CU15): aviso de stock referencial offline.
                Builder(
                  builder: (context) {
                    final conAlerta = _itemsStockReferencial(provider);
                    if (conAlerta.isEmpty) return const SizedBox.shrink();
                    final detalle = conAlerta
                        .map(
                          (e) => '${e.productoNombre}: '
                              '${CartService.mensajeStockReferencial(e.stockLocalConocido ?? 0)}',
                        )
                        .join(' · ');
                    return _AvisoBanner(
                      icon: Icons.inventory_2_outlined,
                      color: AppColors.warning,
                      text: detalle,
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        '${provider.itemCount} '
                        '${provider.itemCount == 1 ? 'artículo' : 'artículos'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Desliza un producto para eliminarlo',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: CouponCard(),
                ),
                // [EXAMEN-2] B1.6.d: reconciliar con el servidor antes de
                // cobrar (RN-014). Sólo tiene sentido si el carrito es local.
                if (provider.esOffline)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: 'Validar total con el servidor',
                            child: OutlinedButton.icon(
                              onPressed: provider.isUpdating
                                  ? null
                                  : () => _validarConServidor(provider),
                              icon: const Icon(
                                Icons.sync_problem_outlined,
                                size: 16,
                              ),
                              label: const Text(
                                'Validar total',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                  color: AppColors.primary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Tooltip(
                            message: 'Reservar para probar en tienda',
                            child: OutlinedButton.icon(
                              onPressed: () => _reserveFromCart(provider),
                              icon: const Icon(
                                Icons.bookmark_add_outlined,
                                size: 16,
                              ),
                              label: const Text(
                                'Reservar prueba',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                  color: AppColors.primary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // Reservar para probar (CU12)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _reserveFromCart(provider),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Reservar para probar en tienda'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          minimumSize: const Size.fromHeight(44),
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
                  taxes: provider.cart.impuestos,
                  total: provider.total,
                  isLoading: provider.isUpdating,
                  esOffline: provider.esOffline,
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

/// [FIX-UI] Aviso unificado del carrito (mismo estilo para todos los banners).
class _AvisoBanner extends StatelessWidget {
  const _AvisoBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
