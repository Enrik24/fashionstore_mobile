import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../core/models/product_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/favorites_provider.dart';
import '../../../core/providers/promotions_provider.dart';

class ProductCard extends StatelessWidget {
  final ProductModel product;

  const ProductCard({
    super.key,
    required this.product,
  });

  void _onFavoriteTap(BuildContext context, bool isFav) async {
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
    final added = await favs.toggle(product.id);
    if (!context.mounted) return;
    if (favs.errorMessage != null && added == isFav) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(favs.errorMessage!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'es_BO',
      symbol: 'Bs. ',
      decimalDigits: 2,
    );

    return InkWell(
      onTap: () {
        context.push('/catalog/${product.id}');
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image & Badges
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'product_image_${product.id}',
                    child: CachedNetworkImage(
                      imageUrl: product.primaryImage,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.surfaceVariant,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.surfaceVariant,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.textMuted,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  // Gradient overlay at top for badge legibility
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Badges
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Consumer<PromotionsProvider>(
                      builder: (context, promos, _) {
                        final descuento = promos.getDiscountForProduct(
                            product.id, product.categoriaId);
                        final es2x1 = promos.has2x1(
                            product.id, product.categoriaId);
                        return Row(
                          children: [
                            // Badge de promoción activa (espejo de la web)
                            if (descuento != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '-${descuento.toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if (es2x1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '2×1',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if (product.hasDiscount)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(8),
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
                        if (product.estado == 'AGOTADO')
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'AGOTADO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else if (product.estado == 'PROXIMO_INGRESO')
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'PRÓXIMAMENTE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    );
                      },
                    ),
                  ),
                  // Corazón de favorito (CU25)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Consumer<FavoritesProvider>(
                      builder: (context, favs, _) {
                        final isFav = favs.isFavorite(product.id);
                        return Material(
                          color: Colors.white.withOpacity(0.92),
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _onFavoriteTap(context, isFav),
                            child: Padding(
                              padding: const EdgeInsets.all(7),
                              child: Icon(
                                isFav
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 20,
                                color: isFav
                                    ? AppColors.accent
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Product Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category / Season
                  if (product.categoriaNombre != null)
                    Text(
                      product.categoriaNombre!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                    ),
                  const SizedBox(height: 2),
                  // Title
                  Text(
                    product.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                          height: 1.2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  // Valoración compacta (CU26): promedio real del backend.
                  Row(
                    children: [
                      const Icon(Icons.star,
                          size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          product.hasRatings
                              ? '${product.rating.toStringAsFixed(1)} (${product.totalReviews})'
                              : 'Sin valoraciones',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Price and Discount (con promoción activa si aplica)
                  Consumer<PromotionsProvider>(
                    builder: (context, promos, _) {
                      final descuento = promos.getDiscountForProduct(
                          product.id, product.categoriaId);
                      final precioPromo = descuento != null
                          ? product.precio * (1 - descuento / 100)
                          : null;
                      final showPromoPrice = precioPromo != null &&
                          !product.hasDiscount;
                      final mainPrice = showPromoPrice
                          ? precioPromo
                          : product.displayPrice;
                      final strikedPrice = showPromoPrice
                          ? product.precio
                          : (product.hasDiscount
                              ? product.precio
                              : null);
                      return Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              currencyFormatter.format(mainPrice),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: (showPromoPrice ||
                                            product.hasDiscount)
                                        ? AppColors.success
                                        : AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                            ),
                          ),
                          if (strikedPrice != null) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                currencyFormatter.format(strikedPrice),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      decoration:
                                          TextDecoration.lineThrough,
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
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
