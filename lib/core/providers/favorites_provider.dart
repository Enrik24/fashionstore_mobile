import 'package:flutter/material.dart';
import '../models/favorite_model.dart';
import '../services/favorites_service.dart';

/// Estado de favoritos del cliente (CU25).
///
/// Mantiene un [Set] de IDs (para los corazones del catálogo con una sola
/// carga) y la lista completa (para "Mis Favoritos"). El toggle usa
/// actualización optimista con rollback si el backend falla.
class FavoritesProvider extends ChangeNotifier {
  final FavoritesService _service;

  FavoritesProvider({required FavoritesService favoritesService})
      : _service = favoritesService;

  Set<int> _favoriteIds = {};
  List<FavoriteModel> _favorites = [];
  bool _isLoading = false;
  bool _isToggling = false;
  String? _errorMessage;

  Set<int> get favoriteIds => _favoriteIds;
  List<FavoriteModel> get favorites => _favorites;
  int get count => _favorites.isNotEmpty ? _favorites.length : _favoriteIds.length;
  bool get isLoading => _isLoading;
  bool get isToggling => _isToggling;
  String? get errorMessage => _errorMessage;

  bool isFavorite(int productoId) => _favoriteIds.contains(productoId);

  /// Carga los IDs (liviano, para marcar corazones). Llamar tras el login.
  Future<void> loadIds() async {
    try {
      _favoriteIds = await _service.getFavoritoIds();
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Carga la lista completa (para la pantalla "Mis Favoritos").
  Future<void> loadFavorites() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _favorites = await _service.getFavoritos();
      _favoriteIds = _favorites.map((f) => f.productoId).toSet();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Alterna el favorito con UI optimista. Devuelve el estado final.
  /// Si [wasAdded] importa al llamador, usar [isFavorite] tras el await.
  Future<bool> toggle(int productoId) async {
    final wasFavorite = _favoriteIds.contains(productoId);

    // Optimistic update
    if (wasFavorite) {
      _favoriteIds.remove(productoId);
      _favorites.removeWhere((f) => f.productoId == productoId);
    } else {
      _favoriteIds.add(productoId);
    }
    _isToggling = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (wasFavorite) {
        await _service.quitar(productoId);
      } else {
        final created = await _service.agregar(productoId);
        _favorites.add(created);
      }
      _isToggling = false;
      notifyListeners();
      return !wasFavorite;
    } catch (e) {
      // Rollback
      if (wasFavorite) {
        _favoriteIds.add(productoId);
      } else {
        _favoriteIds.remove(productoId);
        _favorites.removeWhere((f) => f.productoId == productoId);
      }
      _errorMessage = e.toString();
      _isToggling = false;
      notifyListeners();
      return wasFavorite;
    }
  }

  /// Quita un favorito (usado tras mover al carrito con esa opción).
  void removeLocal(int productoId) {
    _favoriteIds.remove(productoId);
    _favorites.removeWhere((f) => f.productoId == productoId);
    notifyListeners();
  }

  /// Limpia el estado local (usar al cerrar sesión).
  void clearState() {
    _favoriteIds = {};
    _favorites = [];
    _errorMessage = null;
    notifyListeners();
  }
}
