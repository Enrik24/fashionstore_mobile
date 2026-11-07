import 'package:flutter/material.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';

class CartProvider extends ChangeNotifier {
  final CartService _cartService;

  CartProvider({required CartService cartService})
    : _cartService = cartService {
    loadCart();
  }

  CartModel _cart = CartModel.empty();
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _errorMessage;
  double? _nuevoTotalServidor;

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

  // [EXAMEN-2] C2.5 (§7.6) CU15: modo offline explícito y nuevo total pendiente.
  bool get esOffline => _cart.esOffline;
  double? get nuevoTotalServidor => _nuevoTotalServidor;
  bool get tieneNuevoTotalPendiente => _nuevoTotalServidor != null;

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

  Future<bool> addToCart({required int variantId, int quantity = 1}) async {
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
    final agotados = _cart.items.where((i) => i.stockDisponible <= 0).toList();
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
    return _cart.items.where((i) => i.cantidad > i.stockDisponible).toList();
  }

  /// Clears cart state locally without calling the API (used on logout)
  void clearCartState() {
    _cart = CartModel.empty();
    _errorMessage = null;
    _nuevoTotalServidor = null;
    notifyListeners();
  }

  // [EXAMEN-2] C2.5 CU15: valida contra servidor; si hay nuevo total lo expone.
  Future<Map<String, Object?>?> validarContraServidor() async {
    final uuid = _cart.uuidCarrito;
    if (uuid.isEmpty) return null;
    try {
      final data = await _cartService.validarCarritoOffline(uuid);
      final nuevo = (data['nuevo_total'] as num?)?.toDouble()
          ?? (data['total'] as num?)?.toDouble();
      if (nuevo != null && (nuevo - _cart.total).abs() > 0.01) {
        _nuevoTotalServidor = nuevo;
        _errorMessage = 'El servidor propone un nuevo total. Revise y acepte.';
        notifyListeners();
      }
      return data;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  // [EXAMEN-2] C2.5 CU15: acepta el nuevo total y limpia el pendiente.
  Future<bool> aceptarNuevoTotal() async {
    final uuid = _cart.uuidCarrito;
    final nuevo = _nuevoTotalServidor;
    if (uuid.isEmpty || nuevo == null) return false;
    try {
      final actualizado = await _cartService.aceptarNuevoTotalCarrito(
        uuid,
        nuevo,
      );
      if (actualizado != null) _cart = actualizado;
      _nuevoTotalServidor = null;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // [EXAMEN-2] C2.5 CU15: convierte el carrito offline en orden (tras validar/aceptar).
  Future<Map<String, Object?>?> convertirAOrden() async {
    final uuid = _cart.uuidCarrito;
    if (uuid.isEmpty) return null;
    try {
      final resultado = await _cartService.convertirCarritoAOrden(uuid);
      _nuevoTotalServidor = null;
      notifyListeners();
      return resultado;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  // [EXAMEN-2] C2.5 (§7.6) CU15: convierte y devuelve uuids (alias para checkout).
  Future<({String uuidOrden, String uuidPago, double total})?>
  convertirEnPagoDiferido({
    int? sucursalId,
    String? direccionEnvio,
    int? clienteId,
  }) async {
    try {
      final resultado = await _cartService.convertirEnPagoDiferido(
        sucursalId: sucursalId,
        direccionEnvio: direccionEnvio,
        clienteId: clienteId,
      );
      await loadCart();
      return resultado;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }
}
