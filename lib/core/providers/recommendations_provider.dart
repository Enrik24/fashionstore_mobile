import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/ai_service.dart';
import '../services/catalog_service.dart';

/// Estado de la sección "Recomendaciones" del home.
///
/// Espejo de la landing web (`landing.component.ts`):
/// - Con sesión: `POST /inteligencia/recomendaciones {limite}` (el backend
///   deriva el cliente desde el JWT) e hidrata cada recomendación con el
///   detalle completo del producto.
/// - Sin sesión o si la IA falla/devuelve vacío: fallback con
///   `GET /public/catalogo?limite=30` balanceado por género
///   (mitad HOMBRE, resto MUJER/UNISEX).
class RecommendationsProvider extends ChangeNotifier {
  final AiService _aiService;
  final CatalogService _catalogService;

  RecommendationsProvider({
    required AiService aiService,
    required CatalogService catalogService,
  })  : _aiService = aiService,
        _catalogService = catalogService;

  static const int limite = 6;

  List<ProductModel> _products = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isPersonalized = false;
  String? _badge;
  String? _message;
  bool _loadedOnce = false;

  List<ProductModel> get products => _products;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isPersonalized => _isPersonalized;
  String? get badge => _badge;
  String? get message => _message;

  /// Carga las recomendaciones. [isAuthenticated] decide IA vs fallback.
  Future<void> load({required bool isAuthenticated, bool refresh = false}) async {
    if (!refresh && (_isLoading || _loadedOnce)) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (isAuthenticated) {
        final loaded = await _loadPersonalized();
        if (loaded) {
          _finishLoading();
          return;
        }
      }
      await _loadFallback();
    } catch (e) {
      _errorMessage = e.toString();
      // Último recurso: lo que ya tenga el catálogo en memoria queda visible.
      if (_products.isEmpty) {
        try {
          await _loadFallback();
        } catch (_) {}
      }
    } finally {
      _finishLoading();
    }
  }

  void _finishLoading() {
    _isLoading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  /// IA personalizada. Retorna true si obtuvo productos.
  Future<bool> _loadPersonalized() async {
    final response =
        await _aiService.getRecomendaciones(limite: limite);
    final recs = response.recomendaciones
        .where((r) => r.productoId > 0)
        .take(limite)
        .toList();
    if (recs.isEmpty) return false;

    // Hidratar con el detalle completo (rating, oferta, variantes, stock).
    final hydrated = await Future.wait(
      recs.map((r) async {
        try {
          return await _catalogService.getProductoDetalle(r.productoId);
        } catch (_) {
          return null;
        }
      }),
    );
    final full = hydrated.whereType<ProductModel>().toList();
    if (full.isEmpty) return false;

    _products = full;
    _isPersonalized = true;
    final estilo = response.estiloDetectado;
    _badge = estilo != null && estilo.isNotEmpty
        ? 'Personalizado con IA • $estilo'
        : 'Personalizado con IA';
    _message = response.mensajePersonalizado.isNotEmpty
        ? response.mensajePersonalizado
        : null;
    return true;
  }

  /// Fallback público balanceado por género (igual que la web).
  Future<void> _loadFallback() async {
    final response =
        await _catalogService.getCatalogo(page: 1, pageSize: 30);
    final items = response.items;
    if (items.isEmpty) {
      _products = [];
      _isPersonalized = false;
      _badge = null;
      _message = null;
      return;
    }

    final hombres =
        items.where((p) => p.genero?.toUpperCase() == 'HOMBRE').toList();
    final resto = items
        .where((p) => p.genero?.toUpperCase() != 'HOMBRE')
        .toList();
    final picked = <ProductModel>[
      ...hombres.take(limite ~/ 2),
      ...resto,
    ].take(limite).toList();

    _products = picked.isNotEmpty ? picked : items.take(limite).toList();
    _isPersonalized = false;
    _badge = 'Selección especial • Novedades';
    _message = null;
  }

  void clearState() {
    _products = [];
    _errorMessage = null;
    _isPersonalized = false;
    _badge = null;
    _message = null;
    _loadedOnce = false;
    notifyListeners();
  }
}
