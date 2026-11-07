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
      'El carrito offline está deshabilitado para este tenant. Regularice su plan o conecte el dispositivo.';

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
      final local = await _offline?.agregarItem(
        varianteProductoId: varianteProductoId,
        cantidad: cantidad,
        precioUnitario: variante?.precioVariante ?? 0,
        stockConocido: variante?.stockTotal,
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
      await _offline?.vaciar();
      return;
    }
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
          message:
              'Los cupones requieren conexion y no se aplican sin conexion.',
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
    return offline.convertirEnPagoDiferido(
      sucursalId: sucursalId,
      direccionEnvio: direccionEnvio,
      clienteId: clienteId,
    );
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
