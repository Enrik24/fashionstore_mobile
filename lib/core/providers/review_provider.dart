import 'package:flutter/material.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';

/// Estado de valoraciones por producto (CU26).
class ReviewProvider extends ChangeNotifier {
  final ReviewService _service;

  ReviewProvider({required ReviewService reviewService})
      : _service = reviewService;

  /// Caché de reseñas por producto.
  final Map<int, List<ReviewModel>> _reviewsByProduct = {};
  final Map<int, bool> _loadingByProduct = {};
  final Map<int, CanReviewModel?> _canReviewByProduct = {};
  final Map<int, ReviewModel?> _myReviewByProduct = {};

  String? _errorMessage;
  bool _isSubmitting = false;

  String? get errorMessage => _errorMessage;
  bool get isSubmitting => _isSubmitting;

  List<ReviewModel> reviewsOf(int productoId) =>
      _reviewsByProduct[productoId] ?? [];
  bool isLoadingReviews(int productoId) =>
      _loadingByProduct[productoId] ?? false;
  CanReviewModel? canReviewOf(int productoId) =>
      _canReviewByProduct[productoId];
  ReviewModel? myReviewOf(int productoId) => _myReviewByProduct[productoId];

  /// Carga la lista pública de reseñas de un producto.
  Future<void> loadReviews(int productoId, {bool refresh = false}) async {
    if (!refresh && _reviewsByProduct.containsKey(productoId)) return;
    _loadingByProduct[productoId] = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _reviewsByProduct[productoId] =
          await _service.getProductReviews(productoId);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _loadingByProduct[productoId] = false;
      notifyListeners();
    }
  }

  /// Consulta si el cliente autenticado puede valorar (+ su valoración previa).
  /// Si no hay sesión, el backend responde 401: se registra como no permitido.
  Future<void> loadCanReview(int productoId) async {
    try {
      final result = await _service.canReview(productoId);
      _canReviewByProduct[productoId] = result;
      if (result.valoracionExistente != null) {
        _myReviewByProduct[productoId] = result.valoracionExistente;
      } else {
        // Intentar vía endpoint dedicado (por si `valoracion_existente` es null).
        final mine = await _service.getMyReview(productoId);
        _myReviewByProduct[productoId] = mine;
      }
    } catch (_) {
      _canReviewByProduct[productoId] =
          CanReviewModel(puedeValorar: false, motivo: 'Inicia sesión para valorar');
      _myReviewByProduct[productoId] = null;
    }
    notifyListeners();
  }

  /// Crea o actualiza (si ya existe) la valoración del cliente.
  /// Retorna true si se guardó correctamente.
  Future<bool> submitReview(
    int productoId, {
    required int puntuacion,
    String? comentario,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final existing = _myReviewByProduct[productoId];
      final saved = existing == null
          ? await _service.createReview(
              productoId,
              puntuacion: puntuacion,
              comentario: comentario,
            )
          : await _service.updateReview(
              existing.id,
              puntuacion: puntuacion,
              comentario: comentario,
            );
      _myReviewByProduct[productoId] = saved;
      // Refrescar la lista pública para reflejar el cambio.
      await loadReviews(productoId, refresh: true);
      _isSubmitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
