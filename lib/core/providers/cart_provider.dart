import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/api_response.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';

class CartProvider extends ChangeNotifier {
  final CartService _cartService;
  StreamSubscription<void>? _consumoSubscription;

  CartProvider({required CartService cartService})
    : _cartService = cartService {
    // [FIX] Cuando el carrito se convierte en orden con pago diferido, el
    // servicio lo borra de SQLite. Sin esto, `_cart` seguía con los ítems en
    // memoria y un fallo de red en `loadCart()` los volvía a sembrar
    // (asegurarCarritoConItems): el producto reaparecía tras sincronizar y
    // pagar. Limpiamos la memoria en el mismo momento de la conversión.
    _consumoSubscription = cartService.carritoConsumido.listen((_) {
      clearCartState();
    });
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

  /// [EXAMEN-2] B1.6.j: el tenant tiene **deshabilitado** el carrito offline
  /// (`habilitar_carrito_offline`); sólo se permite consultar.
  bool get carritoOfflineDeshabilitado =>
      !_cartService.habilitarCarritoOffline;

  Future<void> loadCart() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _cart = await _cartService.getCarrito();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e is ApiException ? e.message : e.toString();
      // [EXAMEN-2] CU15: sin conexión el carrito del servidor (con los ítems
      // agregados con ella) queda inaccesible y la lectura local está vacía.
      // Se siembran los ítems vigentes en memoria en el carrito local para
      // conservarlos en modo offline; luego se reintenta la lectura, que
      // ahora responde desde SQLite.
      if (_cartService.habilitarCarritoOffline &&
          _cart.items.isNotEmpty &&
          _esErrorDeConectividad(e)) {
        try {
          await _cartService.asegurarCarritoConItems(_cart.items);
          _cart = await _cartService.getCarrito();
          _errorMessage = null;
        } catch (_) {
          // Sin siembra posible: se conserva el carrito en memoria.
        }
      }
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
      // [EXAMEN-2] CU15: al perder la conexión, los ítems agregados con ella
      // viven sólo en memoria y el fallback crearía un carrito local nuevo
      // sin ellos (el usuario veía desaparecer lo agregado online). Se
      // siembran primero y se reintenta la alta en el carrito local: así el
      // carrito conserva lo agregado con conexión + lo nuevo offline.
      if (_cartService.habilitarCarritoOffline &&
          _esErrorDeConectividad(e)) {
        try {
          await _cartService.asegurarCarritoConItems(_cart.items);
          _cart = await _cartService.addItem(
            varianteProductoId: variantId,
            cantidad: quantity,
          );
          _errorMessage = null;
          _isUpdating = false;
          notifyListeners();
          return true;
        } catch (reintento) {
          _errorMessage = reintento is ApiException
              ? reintento.message
              : reintento.toString();
        }
      } else {
        _errorMessage = e is ApiException ? e.message : e.toString();
      }
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  /// [EXAMEN-2] B1.6.g: ¿el fallo es de **conectividad** (el servidor no
  /// respondió)? Un rechazo del servidor (4xx/5xx) trae código y no degrada
  /// a modo offline (misma regla que CheckoutProvider).
  bool _esErrorDeConectividad(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode != null) return false;
      return true;
    }
    if (error is SocketException) return true;
    if (error is ApiException) return error.statusCode == null;
    final texto = error.toString().toLowerCase();
    return texto.contains('socket') ||
        texto.contains('connection') ||
        texto.contains('conectar') ||
        texto.contains('conexión') ||
        texto.contains('conexion') ||
        texto.contains('network') ||
        texto.contains('failed host lookup') ||
        texto.contains('connection refused') ||
        texto.contains('timeout') ||
        texto.contains('timed out');
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

  /// Elimina automáticamente los ítems **sin stock conocido** (CU11).
  ///
  /// [EXAMEN-2] B1.6.c: sólo se retiran los ítems cuyo stock local se conoce
  /// y es 0. Los ítems **sin dato de stock** (`stockDisponible == null`)
  /// se conservan: sin dato no se puede afirmar que estén agotados.
  Future<int> removeOutOfStock() async {
    final agotados = _cart.items
        .where((i) => i.stockDisponible != null && i.stockDisponible! <= 0)
        .toList();
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

  /// Ítems cuya cantidad supera el stock **conocido**.
  ///
  /// [EXAMEN-2] B1.6.c: sin dato de stock no se bloquea el checkout (el
  /// servidor lo validará al sincronizar).
  List<CartItemModel> itemsExceedingStock() {
    return _cart.items
        .where(
          (i) => i.stockDisponible != null && i.cantidad > i.stockDisponible!,
        )
        .toList();
  }

  /// Clears cart state locally without calling the API (used on logout)
  void clearCartState() {
    _cart = CartModel.empty();
    _errorMessage = null;
    _nuevoTotalServidor = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _consumoSubscription?.cancel();
    super.dispose();
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
