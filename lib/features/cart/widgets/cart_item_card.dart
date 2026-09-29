import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../core/models/cart_model.dart';
import 'quantity_selector.dart';

class CartItemCard extends StatelessWidget {
  final CartItemModel item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onDelete;
  final bool isUpdating;

  const CartItemCard({
    super.key,
    required this.item,
    required this.onQuantityChanged,
    required this.onDelete,
    this.isUpdating = false,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'es_BO',
      symbol: 'Bs. ',
      decimalDigits: 2,
    );

    return Dismissible(
      key: Key('cart_item_${item.id}_${item.varianteProductoId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              'Eliminar',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: item.productoImagen ??
                    'https://images.unsplash.com/photo-1523381210434-271e8be1f52b?auto=format&fit=crop&q=80&w=300',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.image, color: AppColors.textMuted),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productoNombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (item.skuVariante != null && item.skuVariante!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${item.skuVariante}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (item.tallaNombre != null && item.tallaNombre!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                          ),
                          child: Text(
                            'Talla: ${item.tallaNombre}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      if (item.colorNombre != null && item.colorNombre!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                          ),
                          child: Text(
                            'Color: ${item.colorNombre}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currencyFormatter.format(item.subtotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontSize: 15,
                            ),
                          ),
                          if (item.cantidad > 1)
                            Text(
                              '${currencyFormatter.format(item.precioUnitario)} c/u',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                      QuantitySelector(
                        quantity: item.cantidad,
                        maxStock: item.stockDisponible,
                        isLoading: isUpdating,
                        onChanged: onQuantityChanged,
                      ),
                    ],
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
