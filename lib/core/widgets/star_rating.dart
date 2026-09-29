import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Selector/visualizador de estrellas reutilizable (CU26).
///
/// [modo lectura]: muestra el promedio (con medias estrellas).
/// [modo edición]: permite tocar de 1 a 5 con feedback háptico.
class StarRating extends StatelessWidget {
  final double value;
  final double size;
  final bool editable;
  final ValueChanged<int>? onChanged;
  final Color color;

  const StarRating({
    super.key,
    required this.value,
    this.size = 18,
    this.editable = false,
    this.onChanged,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    final full = value.floor();
    final hasHalf = !editable && (value - full) >= 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starNumber = i + 1;
        IconData icon;
        if (editable) {
          icon = starNumber <= value.round()
              ? Icons.star
              : Icons.star_border;
        } else if (i < full) {
          icon = Icons.star;
        } else if (i == full && hasHalf) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_border;
        }

        final star = Icon(icon, size: size, color: color);

        if (!editable) return star;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged?.call(starNumber);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: star,
          ),
        );
      }),
    );
  }
}
