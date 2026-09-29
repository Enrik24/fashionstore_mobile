import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../core/models/product_model.dart';
import '../../../core/providers/catalog_provider.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/favorites_provider.dart';
import '../../../core/providers/promotions_provider.dart';
import 'availability_section.dart';
import 'reviews_section.dart';

class ProductDetailPage extends StatefulWidget {
  final int productId;

  const ProductDetailPage({
    super.key,
    required this.productId,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  int _currentImageIndex = 0;
  VarianteProducto? _selectedVariant;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CatalogProvider>().loadProductDetails(widget.productId);
      if (!mounted) return;
      final product = context.read<CatalogProvider>().selectedProduct;
      if (product != null && product.variantes.isNotEmpty) {
        setState(() {
          _selectedVariant = product.variantes.first;
        });
      }
    });
  }

  void _onVariantSelected(VarianteProducto variant) {
    setState(() {
      _selectedVariant = variant;
      _quantity = 1;
    });
    context.read<CatalogProvider>().loadAvailability(
          widget.productId,
          variantId: variant.id,
        );
  }

  Future<void> _toggleFavorite(ProductModel product) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Inicia sesión para guardar tus favoritos'),
          action: SnackBarAction(
            label: 'Ingresar',
            textColor: Colors.white,
            onPressed: () => context.push('/login'),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }
    final favs = context.read<FavoritesProvider>();
    final wasFav = favs.isFavorite(product.id);
    await favs.toggle(product.id);
    if (!mounted) return;
    if (favs.errorMessage != null && favs.isFavorite(product.id) == wasFav) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(favs.errorMessage!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Stock confirmado agotado (CU09).
  ///
  /// El detalle del producto NO trae stock por variante, así que solo se
  /// bloquea cuando: el producto está marcado AGOTADO, o la consulta de
  /// disponibilidad por sucursal respondió con éxito y todo es 0.
  /// Sin datos confirmados no se bloquea (el backend valida al confirmar).
  bool _sinStockConfirmado(
      ProductModel product, CatalogProvider provider) {
    if (product.isAgotado) return true;
    if (!provider.availabilityLoaded) return false;
    return provider.availabilityList.every((e) => e.stock <= 0);
  }

  Future<void> _addToCart(ProductModel product) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Inicia sesión para añadir productos al carrito'),
          action: SnackBarAction(
            label: 'Ingresar',
            textColor: Colors.white,
            onPressed: () => context.push('/login'),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    final variantId = _selectedVariant?.id ??
        (product.variantes.isNotEmpty ? product.variantes.first.id : null);
    if (variantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona una variante (talla/color)'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // CU09: defensa adicional aunque el botón esté inhabilitado.
    final catalogProv = context.read<CatalogProvider>();
    if (_sinStockConfirmado(product, catalogProv)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Producto no disponible por el momento'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final cartProvider = context.read<CartProvider>();
    final success = await cartProvider.addToCart(
      variantId: variantId,
      quantity: _quantity,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡${product.nombre} añadido al carrito!'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Ver Carrito',
            textColor: Colors.white,
            onPressed: () => context.go('/cart'),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cartProvider.errorMessage ?? 'Error al añadir al carrito'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _reserveGarment(ProductModel product) {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Inicia sesión para reservar prendas'),
          action: SnackBarAction(
            label: 'Ingresar',
            textColor: Colors.white,
            onPressed: () => context.push('/login'),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    context.push(
      '/reservations/create',
      extra: {
        'product': product,
        'variant': _selectedVariant,
        'quantity': _quantity,
      },
    );
  }

  /// Reserva directamente en la sucursal elegida desde disponibilidad (CU10).
  void _reserveInBranch(ProductModel product, int sucursalId) {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Inicia sesión para reservar prendas'),
          action: SnackBarAction(
            label: 'Ingresar',
            textColor: Colors.white,
            onPressed: () => context.push('/login'),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    context.push(
      '/reservations/create',
      extra: {
        'product': product,
        'variant': _selectedVariant,
        'quantity': _quantity,
        'sucursalId': sucursalId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'es_BO',
      symbol: 'Bs. ',
      decimalDigits: 2,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<CatalogProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingDetail) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            );
          }

          if (provider.detailErrorMessage != null || provider.selectedProduct == null) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text(
                        'No se pudo cargar el producto',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        provider.detailErrorMessage ?? 'Producto no encontrado',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => provider.loadProductDetails(widget.productId),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final product = provider.selectedProduct!;
          final images = product.imagenes.isNotEmpty ? product.imagenes : [product.primaryImage];

          return CustomScrollView(
            slivers: [
              // Sliver App Bar with Image Carousel
              SliverAppBar(
                expandedHeight: 380,
                pinned: true,
                backgroundColor: AppColors.surface,
                leading: CircleAvatar(
                  backgroundColor: Colors.black.withOpacity(0.4),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                ),
                actions: [
                  // Corazón de favorito (CU25)
                  Consumer<FavoritesProvider>(
                    builder: (context, favs, _) {
                      final product = provider.selectedProduct;
                      final isFav = product != null &&
                          favs.isFavorite(product.id);
                      return CircleAvatar(
                        backgroundColor: Colors.black.withOpacity(0.4),
                        child: IconButton(
                          icon: Icon(
                            isFav
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: isFav ? Colors.redAccent : Colors.white,
                          ),
                          onPressed: product == null
                              ? null
                              : () => _toggleFavorite(product),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.black.withOpacity(0.4),
                    child: IconButton(
                      icon: const Icon(Icons.share_outlined, color: Colors.white),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enlace copiado al portapapeles')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        itemCount: images.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentImageIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          return Hero(
                            tag: index == 0 ? 'product_image_${product.id}' : 'img_$index',
                            child: CachedNetworkImage(
                              imageUrl: images[index],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: AppColors.surfaceVariant,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.image, size: 60, color: AppColors.textMuted),
                              ),
                            ),
                          );
                        },
                      ),
                      // Carousel Indicator
                      if (images.length > 1)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(images.length, (index) {
                              return Container(
                                width: _currentImageIndex == index ? 20 : 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: _currentImageIndex == index
                                      ? AppColors.accent
                                      : Colors.white.withOpacity(0.6),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Product Info & Controls
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category & SKU
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (product.categoriaNombre != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                product.categoriaNombre!.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Text(
                            'SKU: ${product.sku}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Title
                      Text(
                        product.nombre,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 6),

                      // Promedio de valoraciones (CU26): dato real del backend.
                      _RatingRow(product: product),
                      const SizedBox(height: 12),

                      // Price & Discount (con promoción activa si aplica)
                      Consumer<PromotionsProvider>(
                        builder: (context, promos, _) {
                          final descuento =
                              promos.getDiscountForProduct(
                                  product.id,
                                  product.categoriaId);
                          final es2x1 = promos.has2x1(product.id,
                              product.categoriaId);
                          final precioPromo = descuento != null
                              ? product.precio *
                                  (1 - descuento / 100)
                              : null;
                          final showPromo = precioPromo != null &&
                              !product.hasDiscount;
                          final mainPrice = showPromo
                              ? precioPromo
                              : product.displayPrice;
                          return Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    currencyFormatter.format(mainPrice),
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(
                                          color: (showPromo ||
                                                  product.hasDiscount)
                                              ? AppColors.success
                                              : AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 26,
                                        ),
                                  ),
                                  if (product.hasDiscount ||
                                      showPromo) ...[
                                    const SizedBox(width: 10),
                                    Text(
                                      currencyFormatter.format(
                                          product.precio),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            decoration: TextDecoration
                                                .lineThrough,
                                            color:
                                                AppColors.textMuted,
                                          ),
                                    ),
                                    if (showPromo) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                            horizontal: 8,
                                            vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.success,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '-${descuento!.toStringAsFixed(0)}% DESCUENTO',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                            horizontal: 6,
                                            vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'OFERTA',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                              if (es2x1 && descuento == null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.purple,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    '2 × 1 en este producto',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const Divider(height: 32),

                      // Description
                      if (product.descripcion != null && product.descripcion!.isNotEmpty) ...[
                        Text(
                          'Descripción',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          product.descripcion!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                                color: AppColors.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Variants (Colors & Sizes)
                      if (product.variantes.isNotEmpty) ...[
                        Text(
                          'Variantes Disponibles',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: product.variantes.map((v) {
                            final isSelected = _selectedVariant?.id == v.id;
                            final label = '${v.tallaNombre ?? 'Talla única'} - ${v.colorNombre ?? 'Color'}';

                            return InkWell(
                              onTap: () => _onVariantSelected(v),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary : AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : AppColors.border,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (v.colorHex != null && v.colorHex!.isNotEmpty) ...[
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: _parseColor(v.colorHex!),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : AppColors.textPrimary,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Quantity Selector
                      Row(
                        children: [
                          Text(
                            'Cantidad:',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 18),
                                  onPressed: _quantity > 1
                                      ? () => setState(() => _quantity--)
                                      : null,
                                ),
                                Text(
                                  '$_quantity',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18),
                                  onPressed: () => setState(() => _quantity++),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),

                      // Availability Section per branch
                      AvailabilitySection(
                        availabilityList: provider.availabilityList,
                        isLoading: provider.isLoadingAvailability,
                        variantSelected: _selectedVariant != null,
                        onRefresh: () =>
                            provider.loadAvailability(
                          widget.productId,
                          variantId: _selectedVariant?.id,
                        ),
                        onReservarEnSucursal: (item) =>
                            _reserveInBranch(product, item.sucursalId),
                      ),
                      const Divider(height: 32),

                      // Reviews Section (CU26)
                      ReviewsSection(product: product),
                      const SizedBox(height: 100), // Space for bottom buttons
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      // Bottom Action Bar
      bottomNavigationBar: Consumer<CatalogProvider>(
        builder: (context, provider, _) {
          final product = provider.selectedProduct;
          if (product == null) return const SizedBox.shrink();

          // CU09: solo bloquear con stock confirmado agotado
          // (ver _sinStockConfirmado).
          final noDisponible = _sinStockConfirmado(product, provider);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Reserve Button
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: () => _reserveGarment(product),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1.5),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Reservar',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Add to cart Button
                  Expanded(
                    flex: 2,
                    child: Consumer<CartProvider>(
                      builder: (context, cartProv, _) {
                        return ElevatedButton.icon(
                          onPressed: (cartProv.isUpdating ||
                                  noDisponible)
                              ? null
                              : () => _addToCart(product),
                          icon: cartProv.isUpdating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  noDisponible
                                      ? Icons
                                          .remove_shopping_cart_outlined
                                      : Icons.shopping_bag_outlined,
                                  color: Colors.white),
                          label: Text(
                            noDisponible
                                ? 'No disponible'
                                : 'Añadir al Carrito',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: noDisponible
                                ? AppColors.textMuted
                                : AppColors.accent,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }
}

/// Fila de estrellas + promedio + total (CU26).
class _RatingRow extends StatelessWidget {
  final ProductModel product;

  const _RatingRow({required this.product});

  @override
  Widget build(BuildContext context) {
    if (!product.hasRatings) {
      return Row(
        children: [
          const Icon(Icons.star_border, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(
            'Sin valoraciones',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      );
    }
    final full = product.rating.floor();
    final hasHalf = (product.rating - full) >= 0.5;
    return Row(
      children: [
        ...List.generate(5, (i) {
          if (i < full) {
            return const Icon(Icons.star, size: 18, color: Colors.amber);
          }
          if (i == full && hasHalf) {
            return const Icon(Icons.star_half, size: 18, color: Colors.amber);
          }
          return const Icon(Icons.star_border,
              size: 18, color: AppColors.textMuted);
        }),
        const SizedBox(width: 6),
        Text(
          '${product.rating.toStringAsFixed(1)} (${product.totalReviews})',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
