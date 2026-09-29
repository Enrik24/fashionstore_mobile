import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/ai_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/favorites_provider.dart';

class RecommendationsSection extends StatelessWidget {
  final RecomendacionResponse? recommendations;
  final bool isLoading;
  final VoidCallback onRefresh;

  const RecommendationsSection({
    super.key,
    required this.recommendations,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        height: 180,
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.accent),
              SizedBox(height: 12),
              Text('Generando recomendaciones de moda personalizadas...'),
            ],
          ),
        ),
      );
    }

    if (recommendations == null || recommendations!.recomendaciones.isEmpty) {
      return const SizedBox.shrink();
    }

    final recs = recommendations!;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recomendaciones para Ti',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20, color: AppColors.textLight),
                onPressed: onRefresh,
                tooltip: 'Actualizar sugerencias',
              ),
            ],
          ),
          if (recs.estiloDetectado != null && recs.estiloDetectado!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Tu estilo detectado: ${recs.estiloDetectado}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          if (recs.mensajePersonalizado.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              recs.mensajePersonalizado,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recs.recomendaciones.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = recs.recomendaciones[index];
                return _buildProductCard(context, item);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Guarda o quita una recomendación de favoritos (CU21/CU25).
  Future<void> _toggleFavorite(BuildContext context,
      RecomendacionItem item, bool isFav) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Inicia sesión para guardar tus favoritos'),
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
    await favs.toggle(item.productoId);
    if (!context.mounted) return;
    if (favs.errorMessage != null &&
        favs.isFavorite(item.productoId) == isFav) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(favs.errorMessage!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildProductCard(BuildContext context, RecomendacionItem item) {    return InkWell(
      onTap: () => context.push('/catalog/${item.productoId}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: item.imagenUrl != null && item.imagenUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: item.imagenUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.checkroom, color: AppColors.accent, size: 28),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.checkroom, color: AppColors.accent, size: 28),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () {
                        context.push('/ar-fitting?productId=${item.productoId}');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.accessibility_new, size: 14, color: AppColors.accent),
                      ),
                    ),
                  ),
                  // Guardar recomendación en favoritos (CU21/CU25)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Consumer<FavoritesProvider>(
                      builder: (context, favs, _) {
                        final isFav =
                            favs.isFavorite(item.productoId);
                        return InkWell(
                          onTap: () =>
                              _toggleFavorite(context, item, isFav),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFav
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 14,
                              color: isFav
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.razon,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppColors.textLight,
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
