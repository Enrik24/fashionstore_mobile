import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/review_provider.dart';
import '../../../core/widgets/star_rating.dart';

/// Bottom sheet para escribir o editar una valoración (CU26).
///
/// Si [valoracionId] es null se crea (POST); si no, se edita (PUT).
class WriteReviewSheet extends StatefulWidget {
  final int productoId;
  final int? valoracionId;
  final int initialPuntuacion;
  final String? initialComentario;
  final VoidCallback? onSaved;

  const WriteReviewSheet({
    super.key,
    required this.productoId,
    this.valoracionId,
    this.initialPuntuacion = 5,
    this.initialComentario,
    this.onSaved,
  });

  @override
  State<WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<WriteReviewSheet> {
  late int _puntuacion;
  late final TextEditingController _comentarioController;

  @override
  void initState() {
    super.initState();
    _puntuacion = widget.initialPuntuacion.clamp(1, 5);
    _comentarioController =
        TextEditingController(text: widget.initialComentario ?? '');
  }

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reviewProvider = context.read<ReviewProvider>();
    final ok = await reviewProvider.submitReview(
      widget.productoId,
      puntuacion: _puntuacion,
      comentario: _comentarioController.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      widget.onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Gracias por tu valoración!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reviewProvider.errorMessage ?? 'No se pudo guardar'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.valoracionId != null;
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
            Text(
              isEditing ? 'Editar tu valoración' : 'Escribe tu valoración',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Center(
              child: StarRating(
                value: _puntuacion.toDouble(),
                size: 36,
                editable: true,
                onChanged: (v) => setState(() => _puntuacion = v),
              ),
            ),
            Center(
              child: Text(
                '$_puntuacion de 5 estrellas',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comentarioController,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: 'Cuéntanos qué te pareció la prenda... (opcional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.surfaceVariant.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Consumer<ReviewProvider>(
                builder: (context, provider, _) {
                  return ElevatedButton(
                    onPressed: provider.isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: provider.isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            isEditing
                                ? 'Guardar cambios'
                                : 'Publicar valoración',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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
  }
}

/// Muestra el [WriteReviewSheet] si hay sesión; si no, pide login.
void showWriteReviewSheet(
  BuildContext context, {
  required int productoId,
  int? valoracionId,
  int initialPuntuacion = 5,
  String? initialComentario,
  VoidCallback? onSaved,
}) {
  final auth = context.read<AuthProvider>();
  if (!auth.isAuthenticated) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Inicia sesión para valorar productos'),
        backgroundColor: AppColors.primary,
        action: SnackBarAction(
          label: 'Ingresar',
          textColor: Colors.white,
          onPressed: () {},
        ),
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
    builder: (_) => WriteReviewSheet(
      productoId: productoId,
      valoracionId: valoracionId,
      initialPuntuacion: initialPuntuacion,
      initialComentario: initialComentario,
      onSaved: onSaved,
    ),
  );
}
