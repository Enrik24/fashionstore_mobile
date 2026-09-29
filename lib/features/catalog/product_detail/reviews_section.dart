import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/review_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/review_provider.dart';
import '../../../core/widgets/star_rating.dart';
import 'write_review_sheet.dart';

/// Sección "Valoraciones" del detalle de producto (CU26).
///
/// Muestra el promedio, la lista paginada de comentarios y el botón
/// "Escribir valoración" solo si el cliente compró el producto
/// (`ReviewProvider.canReview(...).puedeValorar`). Si ya valoró, muestra
/// su valoración con opción de editar.
class ReviewsSection extends StatefulWidget {
  final ProductModel product;

  const ReviewsSection({super.key, required this.product});

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  static const int _pageSize = 10;
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ReviewProvider>();
      provider.loadReviews(widget.product.id);
      if (context.read<AuthProvider>().isAuthenticated) {
        provider.loadCanReview(widget.product.id);
      }
    });
  }

  void _openWriteSheet({ReviewModel? existing}) {
    showWriteReviewSheet(
      context,
      productoId: widget.product.id,
      valoracionId: existing?.id,
      initialPuntuacion: existing?.puntuacion ?? 5,
      initialComentario: existing?.comentario,
      onSaved: () => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReviewProvider>(
      builder: (context, provider, _) {
        final reviews = provider.reviewsOf(widget.product.id);
        final canReview = provider.canReviewOf(widget.product.id);
        final myReview = provider.myReviewOf(widget.product.id);
        final isLoading = provider.isLoadingReviews(widget.product.id);
        final isAuthenticated =
            context.watch<AuthProvider>().isAuthenticated;

        final visible = reviews.take(_visibleCount).toList();
        final hasMore = reviews.length > _visibleCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Valoraciones',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (widget.product.hasRatings)
                  Row(
                    children: [
                      StarRating(
                          value: widget.product.rating, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.product.rating.toStringAsFixed(1)} (${widget.product.totalReviews})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Mi valoración (si existe) con opción de editar.
            if (myReview != null) ...[
              _MyReviewCard(
                review: myReview,
                onEdit: () => _openWriteSheet(existing: myReview),
              ),
              const SizedBox(height: 12),
            ],

            // Botón de escribir (solo compradores verificados).
            if (isAuthenticated &&
                canReview != null &&
                canReview.puedeValorar &&
                myReview == null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openWriteSheet(),
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: const Text('Escribir valoración'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Lista de comentarios.
            if (isLoading && reviews.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      color: AppColors.accent),
                ),
              )
            else if (reviews.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Aún no hay valoraciones para este producto. ¡Sé la primera persona en opinar!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              ...visible.map((r) => _ReviewCard(review: r)),

            if (hasMore)
              Center(
                child: TextButton(
                  onPressed: () => setState(
                      () => _visibleCount += _pageSize),
                  child: Text(
                      'Ver más (${reviews.length - _visibleCount} restantes)'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final ReviewModel review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final initial = review.clienteNombre.isNotEmpty
        ? review.clienteNombre[0].toUpperCase()
        : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary,
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.clienteNombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    if (review.fechaCreacion != null)
                      Text(
                        dateFormat.format(review.fechaCreacion!),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 11),
                      ),
                  ],
                ),
              ),
              StarRating(
                  value: review.puntuacion.toDouble(), size: 14),
            ],
          ),
          if (review.comentario != null &&
              review.comentario!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comentario!,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _MyReviewCard extends StatelessWidget {
  final ReviewModel review;
  final VoidCallback onEdit;

  const _MyReviewCard({required this.review, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.accent.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Tu valoración',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              StarRating(
                  value: review.puntuacion.toDouble(), size: 16),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.accent),
                tooltip: 'Editar',
                onPressed: onEdit,
              ),
            ],
          ),
          if (review.comentario != null &&
              review.comentario!.isNotEmpty)
            Text(review.comentario!),
          if (!review.isPublicada)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Tu comentario está en revisión de moderación.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.warning),
              ),
            ),
        ],
      ),
    );
  }
}
