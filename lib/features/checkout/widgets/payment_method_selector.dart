import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../core/providers/checkout_provider.dart';

class PaymentMethodSelector extends StatelessWidget {
  const PaymentMethodSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final checkout = context.watch<CheckoutProvider>();

    final methods = [
      {
        'id': 'STRIPE',
        'title': 'Tarjeta de Crédito / Débito',
        'subtitle': 'Visa, Mastercard vía Stripe Segura',
        'icon': Icons.credit_card,
        'badge': 'Recomendado',
      },
      {
        'id': 'PAYPAL',
        'title': 'PayPal Checkout',
        'subtitle': 'Paga seguro con tu cuenta PayPal',
        'icon': Icons.account_balance_wallet_outlined,
        'badge': null,
      },
      {
        'id': 'QR',
        'title': 'Pago con QR Simple',
        'subtitle': 'Cualquier banco o billetera móvil boliviana',
        'icon': Icons.qr_code_2,
        'badge': null,
      },
      {
        'id': 'EFECTIVO',
        'title': 'Pago contra Entrega',
        'subtitle': 'Paga en efectivo al recibir tu pedido',
        'icon': Icons.payments_outlined,
        'badge': null,
      },
    ];

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
              const Icon(Icons.payment, color: AppColors.accent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Método de Pago',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...methods.map((m) {
            final isSelected = checkout.paymentMethod == m['id'];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.surfaceVariant : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: InkWell(
                onTap: () => checkout.setPaymentMethod(m['id'] as String),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      // Radio Circle
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? AppColors.accent : AppColors.textSecondary,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? Center(
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      // Text Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                Text(
                                  m['title'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                if (m['badge'] != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      m['badge'] as String,
                                      style: const TextStyle(
                                        color: AppColors.accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              m['subtitle'] as String,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Secondary Icon
                      Icon(
                        m['icon'] as IconData,
                        color: isSelected ? AppColors.accent : AppColors.textSecondary,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
