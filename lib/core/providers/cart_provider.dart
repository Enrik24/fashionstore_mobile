import 'package:flutter/material.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';

class CartProvider extends ChangeNotifier {
  final CartService _cartService;

  CartProvider({required CartService cartService}) : _cartService = cartService;

  CartModel _cart = CartModel.empty();
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _errorMessage;

  CartModel get cart => _cart;
  List<CartItemModel> get items => _cart.items;
  int get itemCount => _cart.totalItems;
  double get subtotal => _cart.subtotal;
  double get discount => _cart.descuentoAplicado;
  double get total => _cart.total;
  String? get cuponCodigo => _cart.cuponCodigo;
  bool get isEmpty => _cart.isEmpty;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;

  Future<void> loadCart() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _cart = await _cartService.getCarrito();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addToCart({
    required int variantId,
    int quantity = 1,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _cart = await _cartService.addItem(
        varianteProductoId: variantId,
        cantidad: quantity,
      );
      _isUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> updateQuantity(int itemId, int newQuantity) async {
    if (newQuantity <= 0) {
      await removeItem(itemId);
      return;
    }

    _isUpdating = true;
    notifyListeners();

    try {
      _cart = await _cartService.updateItem(
        itemId: itemId,
        cantidad: newQuantity,
      );
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<void> removeItem(int itemId) async {
    _isUpdating = true;
    notifyListeners();

    try {
      await _cartService.removeItem(itemId);
      // Recargar desde el servidor para mantener subtotal/descuento/cupón
      // consistentes (el backend recalcula el carrito tras cada cambio).
      _cart = await _cartService.getCarrito();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      // Reload on failure to restore state
      await loadCart();
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<void> clearCart() async {
    _isUpdating = true;
    notifyListeners();

    try {
      await _cartService.clearCart();
      _cart = CartModel.empty();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  /// Aplica un cupón al carrito (CU27). Retorna true si se aplicó.
  Future<bool> applyCoupon(String codigo) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _cart = await _cartService.applyCoupon(codigo);
      _isUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  /// Quita el cupón aplicado (CU27).
  Future<bool> removeCoupon() async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _cart = await _cartService.removeCoupon();
      _isUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  /// Elimina automáticamente los ítems sin stock (CU11: el sistema
  /// notifica y los retira del carrito). Retorna la cantidad eliminada.
  Future<int> removeOutOfStock() async {
    final agotados =
        _cart.items.where((i) => i.stockDisponible <= 0).toList();
    if (agotados.isEmpty) return 0;
    var removed = 0;
    for (final item in agotados) {
      try {
        await _cartService.removeItem(item.id);
        removed++;
      } catch (_) {}
    }
    await loadCart();
    return removed;
  }

  /// Ítems cuya cantidad supera el stock disponible.
  List<CartItemModel> itemsExceedingStock() {
    return _cart.items
        .where((i) => i.cantidad > i.stockDisponible)
        .toList();
  }

  /// Clears cart state locally without calling the API (used on logout)
  void clearCartState() {
    _cart = CartModel.empty();
    _errorMessage = null;
    notifyListeners();
  }
}
