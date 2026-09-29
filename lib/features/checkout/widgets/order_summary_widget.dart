import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../core/models/cart_model.dart';

class OrderSummaryWidget extends StatelessWidget {
  final List<CartItemModel> items;
  final double subtotal;
  final double discount;
  final double shippingCost;
  final double total;
  final String deliveryType;
  final String? couponCode;

  const OrderSummaryWidget({
    super.key,
    required this.items,
    required this.subtotal,
    this.discount = 0.0,
    required this.shippingCost,
    required this.total,
    this.deliveryType = 'SHIPPING',
    this.couponCode,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'es_BO',
      symbol: 'Bs. ',
      decimalDigits: 2,
    );

    final isPickup = deliveryType == 'PICKUP';
    final effectiveShippingCost = isPickup ? 0.0 : shippingCost;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.accent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Resumen del Pedido',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 16),
            itemBuilder: (context, index) {
              final item = items[index];
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productoNombre,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${item.cantidad}x  ${item.tallaNombre ?? ''} ${item.colorNombre != null ? '• ${item.colorNombre}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    currencyFormatter.format(item.subtotal),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              );
            },
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal', style: Theme.of(context).textTheme.bodyMedium),
              Text(currencyFormatter.format(subtotal),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          if (discount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  couponCode != null
                      ? 'Descuento (cupón $couponCode)'
                      : 'Descuento cupón',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  '- ${currencyFormatter.format(discount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isPickup ? 'Retiro en sucursal' : 'Envío a domicilio',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                effectiveShippingCost == 0.0
                    ? 'GRATIS'
                    : currencyFormatter.format(effectiveShippingCost),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: effectiveShippingCost == 0.0
                      ? AppColors.success
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Final',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                currencyFormatter.format(total),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
