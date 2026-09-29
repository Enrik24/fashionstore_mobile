import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/product_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/providers/catalog_provider.dart';
import '../../../core/providers/favorites_provider.dart';
import '../../../core/services/favorites_service.dart';
import '../../../core/widgets/custom_app_bar.dart';

/// Pantalla "Mis Favoritos" (CU25).
///
/// Grid de productos favoritos con disponibilidad, botón "Agregar al
/// carrito" (bottom sheet para elegir variante) y eliminación por swipe.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FavoritesProvider>().loadFavorites();
    });
  }

  Future<void> _showVariantPicker(
      BuildContext context, int productoId, String nombre) async {
    final catalog = context.read<CatalogProvider>();
    await catalog.loadProductDetails(productoId);
    if (!context.mounted) return;

    final product = catalog.selectedProduct;
    if (product == null || product.variantes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron cargar las variantes del producto'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _VariantPickerSheet(
        product: product,
        onConfirm: (variant, quantity, quitarDeFavoritos) async {
          Navigator.of(sheetContext).pop();
          await _moveToCart(context, productoId, variant.id, quantity,
              quitarDeFavoritos, nombre);
        },
      ),
    );
  }

  Future<void> _moveToCart(
    BuildContext context,
    int productoId,
    int varianteId,
    int cantidad,
    bool quitarDeFavoritos,
    String nombre,
  ) async {
    final favoritesService = context.read<FavoritesService>();
    final cartProvider = context.read<CartProvider>();
    final favoritesProvider = context.read<FavoritesProvider>();
    try {
      await favoritesService.moverAlCarrito(
        productoId: productoId,
        varianteProductoId: varianteId,
        cantidad: cantidad,
        quitarDeFavoritos: quitarDeFavoritos,
      );
      await cartProvider.loadCart();
      if (quitarDeFavoritos) {
        favoritesProvider.removeLocal(productoId);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡$nombre añadido al carrito!'),
          backgroundColor: AppColors.success,
          action: SnackBarAction(
            label: 'Ver Carrito',
            textColor: Colors.white,
            onPressed: () => context.go('/cart'),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currencyFormatter = NumberFormat.currency(
      locale: 'es_BO',
      symbol: 'Bs. ',
      decimalDigits: 2,
    );

    if (!auth.isAuthenticated) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Mis Favoritos', showBackButton: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite_border,
                    size: 72, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text('Inicia sesión para ver tus favoritos',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
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
      appBar: const CustomAppBar(title: 'Mis Favoritos', showBackButton: true),
      body: Consumer<FavoritesProvider>(
        builder: (context, favs, _) {
          if (favs.isLoading && favs.favorites.isEmpty) {
            return const Center(
              child:
                  CircularProgressIndicator(color: AppColors.accent),
            );
          }

          if (favs.errorMessage != null && favs.favorites.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 56, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(favs.errorMessage!,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => favs.loadFavorites(),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (favs.favorites.isEmpty) {
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
                      child: const Icon(Icons.favorite_border,
                          size: 56, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    Text('Aún no tienes favoritos',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      'Toca el corazón en cualquier producto para guardarlo aquí.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => context.go('/catalog'),
                      icon: const Icon(Icons.storefront_outlined,
                          color: Colors.white),
                      label: const Text('Explorar catálogo',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => favs.loadFavorites(),
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              itemCount: favs.favorites.length,
              itemBuilder: (context, index) {
                final fav = favs.favorites[index];
                final product = fav.producto;
                return Dismissible(
                  key: ValueKey('fav_${fav.productoId}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    await favs.toggle(fav.productoId);
                    return false; // el provider ya actualiza la lista
                  },
                  child: _FavoriteCard(
                    product: product,
                    disponible: fav.disponible,
                    currencyFormatter: currencyFormatter,
                    onTap: () =>
                        context.push('/catalog/${product.id}'),
                    onDelete: () => favs.toggle(fav.productoId),
                    onAddToCart: () => _showVariantPicker(
                        context, fav.productoId, product.nombre),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final ProductModel product;
  final bool disponible;
  final NumberFormat currencyFormatter;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onAddToCart;

  const _FavoriteCard({
    required this.product,
    required this.disponible,
    required this.currencyFormatter,
    required this.onTap,
    required this.onDelete,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: product.primaryImage,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.image_not_supported_outlined,
                          color: AppColors.textMuted),
                    ),
                  ),
                  if (!disponible)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('NO DISPONIBLE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.white.withOpacity(0.92),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onDelete,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.favorite,
                              size: 18, color: AppColors.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    currencyFormatter.format(product.displayPrice),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: disponible ? onAddToCart : null,
                      icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                      label: const Text('Al carrito',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side:
                            const BorderSide(color: AppColors.accent),
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet para elegir variante y cantidad al mover un favorito al carrito.
class _VariantPickerSheet extends StatefulWidget {
  final ProductModel product;
  final void Function(VarianteProducto variant, int quantity, bool quitar)
      onConfirm;

  const _VariantPickerSheet({required this.product, required this.onConfirm});

  @override
  State<_VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends State<_VariantPickerSheet> {
  VarianteProducto? _selected;
  int _quantity = 1;
  bool _quitarDeFavoritos = false;

  @override
  void initState() {
    super.initState();
    if (widget.product.variantes.isNotEmpty) {
      _selected = widget.product.variantes.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Elige variante',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(widget.product.nombre,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.product.variantes.map((v) {
                final selected = _selected?.id == v.id;
                final label =
                    '${v.tallaNombre ?? 'Única'} • ${v.colorNombre ?? ''}';
                return ChoiceChip(
                  label: Text(label,
                      style: TextStyle(
                          color: selected
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontSize: 12)),
                  selected: selected,
                  selectedColor: AppColors.primary,
                  onSelected: (_) =>
                      setState(() => _selected = v),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Cantidad:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                ),
                Text('$_quantity',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () =>
                      setState(() => _quantity++),
                ),
                const Spacer(),
                Flexible(
                  child: CheckboxListTile(
                    value: _quitarDeFavoritos,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Quitar de favoritos',
                        style: TextStyle(fontSize: 12)),
                    onChanged: (v) =>
                        setState(() => _quitarDeFavoritos = v ?? false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selected == null
                    ? null
                    : () => widget.onConfirm(
                        _selected!, _quantity, _quitarDeFavoritos),
                icon: const Icon(Icons.shopping_bag_outlined,
                    color: Colors.white),
                label: const Text('Agregar al carrito',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
