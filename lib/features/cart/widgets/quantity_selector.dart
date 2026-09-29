import 'package:flutter/material.dart';
import '../../../config/theme.dart';

class QuantitySelector extends StatelessWidget {
  final int quantity;
  final int maxStock;
  final ValueChanged<int> onChanged;
  final bool isLoading;

  const QuantitySelector({
    super.key,
    required this.quantity,
    this.maxStock = 99,
    required this.onChanged,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: isLoading
                ? null
                : () {
                    if (quantity > 1) {
                      onChanged(quantity - 1);
                    }
                  },
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Icon(Icons.remove, size: 16, color: AppColors.textPrimary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$quantity',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          InkWell(
            onTap: (isLoading || quantity >= maxStock)
                ? null
                : () {
                    onChanged(quantity + 1);
                  },
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Icon(
                Icons.add,
                size: 16,
                color: quantity >= maxStock ? AppColors.textMuted : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
