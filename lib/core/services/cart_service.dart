import 'dart:async';

import '../../config/constants.dart';
import '../models/cart_model.dart';
import 'api_service.dart';
import '../models/api_response.dart';
import 'offline_cart_service.dart';
import 'offline_catalog_service.dart';

class CartService {
  final ApiService _apiService;
  final OfflineCartService? _offline;
  final OfflineCatalogService? _catalog;

  // [EXAMEN-2] C2.5 (§7.6) CU15: bandera remota (OfflineConfigModel).
  // Si es false, agregarItem bloquea aunque haya datos locales.
  bool habilitarCarritoOffline = true;

  /// Se emite cuando el carrito local se convierte en orden con pago diferido
  /// y se borra de SQLite. La UI debe limpiar también su estado en memoria:
  /// si no, un fallo de red posterior en `loadCart()` vuelve a sembrar los
  /// ítems viejos desde `_cart.items` (producto fantasma tras sincronizar).
  final StreamController<void> _carritoConsumido =
      StreamController<void>.broadcast();
  Stream<void> get carritoConsumido => _carritoConsumido.stream;

  void notificarCarritoConsumido() {
    if (!_carritoConsumido.isClosed) _carritoConsumido.add(null);
  }

  void dispose() => _carritoConsumido.close();

  CartService({
    required ApiService apiService,
    OfflineCartService? offline,
    OfflineCatalogService? catalog,
    bool? habilitarCarritoOffline,
  }) : _apiService = apiService,
       _offline = offline,
       _catalog = catalog,
       habilitarCarritoOffline = habilitarCarritoOffline ?? true;

  // [EXAMEN-2] C2.5 CU15: guarda para UI (mensaje §19).
  static String get mensajeCarritoOfflineDeshabilitado =>
      'El carrito offline está deshabilitado para esta empresa. Puedes consultar el catálogo, pero no comprar sin conexión.';

  // [EXAMEN-2] §19: aviso de stock referencial en el carrito/POS offline.
  static String mensajeStockReferencial(int stock) =>
      'Stock local referencial: $stock. La cantidad se validará al sincronizar.';

  void _verificarHabilitado() {
    if (!habilitarCarritoOffline) {
      throw ApiException(message: mensajeCarritoOfflineDeshabilitado);
    }
  }

  Future<CartModel> getCarrito() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epCarrito);
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return CartModel.empty();
    } catch (e) {
      final local = await _offline?.obtenerCarritoLocal();
      if (local != null) return local;
      throw _apiService.handleError(e);
    }
  }

  Future<CartModel> addItem({
    required int varianteProductoId,
    required int cantidad,
  }) async {
    _verificarHabilitado();
    try {
      final response = await _apiService.dio.post(
        AppConstants.epCarritoItems,
        data: {
          'variante_producto_id': varianteProductoId,
          'cantidad': cantidad,
        },
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return await getCarrito();
    } catch (e) {
      if (e is ApiException && e.message == mensajeCarritoOfflineDeshabilitado) {
        rethrow;
      }
      final variante = await _varianteLocal(varianteProductoId);
      // [EXAMEN-2] B1.6.b: si la variante **no está en el catálogo local
      // descargado**, no se puede agregar al carrito: antes se insertaba con
      // precio 0 y sin stock, lo que producía un carrito con total 0.
      if (variante == null) {
        throw ApiException(
          message:
              'El producto no está en el catálogo descargado. '
              'Conéctate y descarga los datos para agregarlo al carrito.',
        );
      }
      final local = await _offline?.agregarItem(
        varianteProductoId: varianteProductoId,
        cantidad: cantidad,
        precioUnitario: variante.precioVariante ?? variante.precio ?? 0,
        stockConocido: variante.stockTotal,
      );
      if (local != null) return local;
      throw _apiService.handleError(e);
    }
  }

  Future<CartModel> updateItem({
    required int itemId,
    required int cantidad,
  }) async {
    try {
      final response = await _apiService.dio.put(
        '${AppConstants.epCarritoItems}/$itemId',
        data: {'cantidad': cantidad},
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return await getCarrito();
    } catch (e) {
      final local = await _offline?.actualizarCantidad(itemId, cantidad);
      if (local != null) return local;
      throw _apiService.handleError(e);
    }
  }

  Future<void> removeItem(int itemId) async {
    try {
      await _apiService.dio.delete('${AppConstants.epCarritoItems}/$itemId');
    } catch (e) {
      await _offline?.eliminarItem(itemId);
      return;
    }
  }

  Future<void> clearCart() async {
    try {
      await _apiService.dio.delete(AppConstants.epCarrito);
    } catch (e) {
      // Sin red: igual se limpia la copia local (abajo).
    }
    // [FIX] Antes, con conexión sólo se borraba el carrito del servidor y la
    // copia SQLite seguía con los ítems offline: al volver a cargar reaparecían.
    await _offline?.vaciar();
    notificarCarritoConsumido();
  }

  /// `POST /carrito/aplicar-cupon` (CU27).
  Future<CartModel> applyCoupon(String codigo) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epCarritoAplicarCupon,
        data: {'codigo': codigo.trim().toUpperCase()},
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return await getCarrito();
    } catch (e) {
      if (_offline != null) {
        throw ApiException(
          message: 'Los cupones se validan solo con conexión.',
        );
      }
      throw _apiService.handleError(e);
    }
  }

  /// `DELETE /carrito/remover-cupon` (CU27).
  Future<CartModel> removeCoupon() async {
    try {
      final response = await _apiService.dio.delete(
        AppConstants.epCarritoRemoverCupon,
      );
      if (response.data is Map<String, dynamic>) {
        return CartModel.fromJson(response.data as Map<String, dynamic>);
      }
      return await getCarrito();
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<dynamic> _varianteLocal(int varianteProductoId) async {
    final productos = await _catalog?.catalogoLocal() ?? const [];
    for (final producto in productos) {
      for (final variante in producto.variantes) {
        if (variante.id == varianteProductoId) return variante;
      }
    }
    return null;
  }

  Future<({String uuidOrden, String uuidPago, double total})>
  convertirEnPagoDiferido({
    required int? sucursalId,
    required String? direccionEnvio,
    required int? clienteId,
  }) async {
    _verificarHabilitado();
    final offline = _offline;
    if (offline == null) {
      throw StateError('El carrito offline no esta disponible.');
    }
    final resultado = await offline.convertirEnPagoDiferido(
      sucursalId: sucursalId,
      direccionEnvio: direccionEnvio,
      clienteId: clienteId,
    );
    notificarCarritoConsumido();
    return resultado;
  }

  /// [FIX] Garantiza un carrito local con los ítems indicados antes de
  /// convertir a orden con pago diferido (delegación al servicio offline).
  Future<void> asegurarCarritoConItems(List<CartItemModel> items) async {
    final offline = _offline;
    if (offline == null) {
      throw StateError('El carrito offline no esta disponible.');
    }
    return offline.asegurarCarritoConItems(items);
  }

  // [EXAMEN-2] C2.5 CU15: flujo validar -> aceptar -> convertir (RN-014).
  Future<Map<String, Object?>> validarCarritoOffline(String uuid) async {
    final offline = _offline;
    if (offline == null) throw StateError('Carrito offline no disponible.');
    return offline.validarContraServidor(uuid);
  }

  Future<CartModel?> aceptarNuevoTotalCarrito(
    String uuid,
    double nuevoTotal,
  ) async {
    final offline = _offline;
    if (offline == null) throw StateError('Carrito offline no disponible.');
    return offline.aceptarNuevoTotal(uuid, nuevoTotal);
  }

  Future<Map<String, Object?>> convertirCarritoAOrden(String uuid) async {
    final offline = _offline;
    if (offline == null) throw StateError('Carrito offline no disponible.');
    return offline.convertirAOrden(uuid);
  }
}
