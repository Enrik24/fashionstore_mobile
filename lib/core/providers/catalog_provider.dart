import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/catalog_service.dart';

class CatalogProvider extends ChangeNotifier {
  final CatalogService _catalogService;

  CatalogProvider({required CatalogService catalogService})
      : _catalogService = catalogService;

  // Catalog State
  List<ProductModel> _products = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;

  // Filter Options State
  List<CategoryModel> _categories = [];
  List<TemporadaModel> _seasons = [];
  List<TallaModel> _sizes = [];
  List<ColorFilterModel> _colors = [];
  bool _isLoadingFilterOptions = false;

  // Active Filters State
  int? _selectedCategoryId;
  String? _selectedCategoryName;
  int? _selectedTemporadaId;
  String? _selectedTemporadaName;
  int? _selectedTallaId;
  String? _selectedTallaValor;
  int? _selectedColorId;
  String? _selectedColorNombre;
  double? _minPrice;
  double? _maxPrice;
  String? _searchQuery;
  String? _ordering = 'recientes'; // 'recientes', 'precio_asc', 'precio_desc', 'nombre'
  String? _selectedGenero; // 'HOMBRE', 'MUJER', 'UNISEX' (null = Todos)

  // Selected Product Detail State
  ProductModel? _selectedProduct;
  bool _isLoadingDetail = false;
  String? _detailErrorMessage;

  // Availability State
  List<DisponibilidadItem> _availabilityList = [];
  bool _isLoadingAvailability = false;
  // true solo si la última consulta de disponibilidad respondió con éxito.
  // (El detalle del producto NO trae stock por variante, así que la
  // disponibilidad real solo se conoce tras consultar /disponibilidad.)
  bool _availabilityLoaded = false;

  // Search results
  List<ProductModel> _searchResults = [];
  bool _isSearching = false;

  // Getters
  List<ProductModel> get products => _products;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalItems => _totalItems;
  // _currentPage apunta a la SIGUIENTE página por cargar (se incrementa
  // tras cada carga), por eso la comparación es <=.
  bool get hasMore => _currentPage <= _totalPages;

  List<CategoryModel> get categories => _categories;
  List<TemporadaModel> get seasons => _seasons;
  List<TallaModel> get sizes => _sizes;
  List<ColorFilterModel> get colors => _colors;
  bool get isLoadingFilterOptions => _isLoadingFilterOptions;

  int? get selectedCategoryId => _selectedCategoryId;
  String? get selectedCategoryName => _selectedCategoryName;
  int? get selectedTemporadaId => _selectedTemporadaId;
  String? get selectedTemporadaName => _selectedTemporadaName;
  int? get selectedTallaId => _selectedTallaId;
  String? get selectedTallaValor => _selectedTallaValor;
  int? get selectedColorId => _selectedColorId;
  String? get selectedColorNombre => _selectedColorNombre;
  double? get minPrice => _minPrice;
  double? get maxPrice => _maxPrice;
  String? get searchQuery => _searchQuery;
  String? get ordering => _ordering;
  String? get selectedGenero => _selectedGenero;

  ProductModel? get selectedProduct => _selectedProduct;
  bool get isLoadingDetail => _isLoadingDetail;
  String? get detailErrorMessage => _detailErrorMessage;

  List<DisponibilidadItem> get availabilityList => _availabilityList;
  bool get isLoadingAvailability => _isLoadingAvailability;
  bool get availabilityLoaded => _availabilityLoaded;

  List<ProductModel> get searchResults => _searchResults;
  bool get isSearching => _isSearching;

  bool get hasActiveFilters =>
      _selectedCategoryId != null ||
      _selectedTemporadaId != null ||
      _selectedTallaId != null ||
      _selectedColorId != null ||
      _minPrice != null ||
      _maxPrice != null ||
      _selectedGenero != null ||
      (_ordering != null && _ordering != 'recientes');

  // Load Filter Options from API
  Future<void> loadFilterOptions() async {
    if (_categories.isNotEmpty && _seasons.isNotEmpty) return;
    _isLoadingFilterOptions = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _catalogService.getCategorias(),
        _catalogService.getTemporadas(),
        _catalogService.getTallas(),
        _catalogService.getColores(),
      ]);

      _categories = results[0] as List<CategoryModel>;
      _seasons = results[1] as List<TemporadaModel>;
      _sizes = results[2] as List<TallaModel>;
      _colors = results[3] as List<ColorFilterModel>;
    } catch (_) {
      // Ignorar fallos no críticos en carga de opciones de filtros
    } finally {
      _isLoadingFilterOptions = false;
      notifyListeners();
    }
  }

  // Load / Refresh Catalog
  Future<void> loadCatalog({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    } else {
      if (_isLoading || _isLoadingMore || !hasMore) return;
      _isLoadingMore = true;
      notifyListeners();
    }

    try {
      final response = await _catalogService.getCatalogo(
        page: _currentPage,
        pageSize: 12,
        categoriaId: _selectedCategoryId,
        temporadaId: _selectedTemporadaId,
        tallaId: _selectedTallaId,
        colorId: _selectedColorId,
        minPrecio: _minPrice,
        maxPrecio: _maxPrice,
        search: _searchQuery,
        orden: _ordering,
        genero: _selectedGenero,
      );

      if (refresh || _currentPage == 1) {
        _products = response.items;
      } else {
        _products.addAll(response.items);
      }

      _totalPages = response.totalPages;
      _totalItems = response.total;
      _currentPage++;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void setCategory(int? categoryId, [String? categoryName]) {
    _selectedCategoryId = categoryId;
    _selectedCategoryName = categoryName;
    loadCatalog(refresh: true);
  }

  void setTemporada(int? temporadaId, [String? temporadaName]) {
    _selectedTemporadaId = temporadaId;
    _selectedTemporadaName = temporadaName;
    loadCatalog(refresh: true);
  }

  void setTalla(int? tallaId, [String? tallaValor]) {
    _selectedTallaId = tallaId;
    _selectedTallaValor = tallaValor;
    loadCatalog(refresh: true);
  }

  void setColor(int? colorId, [String? colorNombre]) {
    _selectedColorId = colorId;
    _selectedColorNombre = colorNombre;
    loadCatalog(refresh: true);
  }

  void setPriceRange(double? min, double? max) {
    _minPrice = min;
    _maxPrice = max;
    loadCatalog(refresh: true);
  }

  void setOrdering(String? order) {
    _ordering = order;
    loadCatalog(refresh: true);
  }

  void setGenero(String? genero) {
    _selectedGenero = genero?.toUpperCase();
    loadCatalog(refresh: true);
  }

  void setSearchQuery(String? query) {
    _searchQuery = query;
    loadCatalog(refresh: true);
  }

  void applyFilters({
    int? categoryId,
    String? categoryName,
    int? temporadaId,
    String? temporadaName,
    int? tallaId,
    String? tallaValor,
    int? colorId,
    String? colorNombre,
    double? minPrice,
    double? maxPrice,
    String? ordering,
    String? genero,
  }) {
    _selectedCategoryId = categoryId;
    _selectedCategoryName = categoryName;
    _selectedTemporadaId = temporadaId;
    _selectedTemporadaName = temporadaName;
    _selectedTallaId = tallaId;
    _selectedTallaValor = tallaValor;
    _selectedColorId = colorId;
    _selectedColorNombre = colorNombre;
    _minPrice = minPrice;
    _maxPrice = maxPrice;
    _ordering = ordering ?? 'recientes';
    _selectedGenero = genero?.toUpperCase();
    loadCatalog(refresh: true);
  }

  void clearFilters() {
    _selectedCategoryId = null;
    _selectedCategoryName = null;
    _selectedTemporadaId = null;
    _selectedTemporadaName = null;
    _selectedTallaId = null;
    _selectedTallaValor = null;
    _selectedColorId = null;
    _selectedColorNombre = null;
    _minPrice = null;
    _maxPrice = null;
    _searchQuery = null;
    _ordering = 'recientes';
    _selectedGenero = null;
    loadCatalog(refresh: true);
  }

  // Load Product Details
  Future<void> loadProductDetails(int id) async {
    _isLoadingDetail = true;
    _detailErrorMessage = null;
    _selectedProduct = null;
    _availabilityList = [];
    _availabilityLoaded = false;
    notifyListeners();

    try {
      _selectedProduct = await _catalogService.getProductoDetalle(id);
      // Automatically load availability as well
      await loadAvailability(id);
    } catch (e) {
      _detailErrorMessage = e.toString();
    } finally {
      _isLoadingDetail = false;
      notifyListeners();
    }
  }

  // Load Availability by Branch
  Future<void> loadAvailability(int productId, {int? variantId}) async {
    _isLoadingAvailability = true;
    _availabilityLoaded = false;
    notifyListeners();

    try {
      _availabilityList = await _catalogService.getDisponibilidad(
        productId,
        varianteId: variantId,
      );
      _availabilityLoaded = true;
    } catch (e) {
      _availabilityList = [];
      // _availabilityLoaded queda en false: sin datos confirmados NO se
      // bloquea la compra (el backend valida el stock al confirmar).
    } finally {
      _isLoadingAvailability = false;
      notifyListeners();
    }
  }

  // Live Search
  Future<void> searchProducts(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    try {
      _searchResults = await _catalogService.buscarProductos(query);
    } catch (e) {
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    _isSearching = false;
    notifyListeners();
  }
}
