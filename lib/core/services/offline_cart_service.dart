import 'dart:convert';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/offline_cart_repository.dart';
import '../database/repositories/local_order_repository.dart';
import '../models/cart_model.dart';
import 'device_service.dart';
import 'local_crypto_service.dart';
import 'offline_queue_service.dart';
import 'pending_payment_service.dart';

/// [EXAMEN-2] Carrito persistente y conversión a orden local (CU15).
class OfflineCartService {
  OfflineCartService({
    required LocalDatabaseService database,
    required int tenantId,
    required String dispositivoId,
    OfflineCartRepository? repository,
    OfflineApiClient? client,
    OfflineQueueService? queue,
    PendingPaymentService? pendingPayments,
    LocalCryptoService? crypto,
  }) : _database = database,
       _tenantId = tenantId,
       _dispositivoId = dispositivoId,
       _repository = repository,
       _client = client,
       _queue = queue,
       _pendingPayments = pendingPayments,
       _crypto = crypto ?? LocalCryptoService();

  final LocalDatabaseService _database;
  final int _tenantId;
  final String _dispositivoId;
  OfflineCartRepository? _repository;
  final OfflineApiClient? _client;
  final OfflineQueueService? _queue;
  final PendingPaymentService? _pendingPayments;
  // [EXAMEN-2] C2.1: UUID v4 reales.
  final LocalCryptoService _crypto;

  OfflineCartRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _repository ??= OfflineCartRepository(db, tenantId: _tenantId);
  }

  Future<CartModel?> obtenerCarritoLocal() async {
    final fila = await _repo.obtenerActivo();
    if (fila == null) return null;
    final items = await _repo.listarItems(fila['uuid_carrito'].toString());
    return CartModel(
      id: 0,
      clienteId: (fila['cliente_id'] as num?)?.toInt() ?? 0,
      items: items.map(_itemDesdeMapa).toList(),
      subtotal: (fila['subtotal'] as num?)?.toDouble() ?? 0,
      descuentoAplicado: (fila['descuento_aplicado'] as num?)?.toDouble() ?? 0,
      total: (fila['total'] as num?)?.toDouble() ?? 0,
      cuponCodigo: fila['cupon_codigo']?.toString(),
      uuidCarrito: fila['uuid_carrito'].toString(),
      dispositivoId: _dispositivoId,
      estado: fila['estado']?.toString() ?? 'ACTIVO',
      esOffline: true,
      estadoSincronizacion:
          fila['estado_sincronizacion']?.toString() ?? 'PENDIENTE',
    );
  }

  Future<CartModel> agregarItem({
    required int varianteProductoId,
    required int cantidad,
    required double precioUnitario,
    int? stockConocido,
  }) async {
    var carrito = await obtenerCarritoLocal();
    final uuid = carrito?.uuidCarrito ?? _uuid();
    if (carrito == null) {
      await _repo.crear(
        uuid,
        datos: <String, Object?>{
          'cliente_id': 0,
          'dispositivo_id': _dispositivoId,
          'es_offline': 1,
          'estado_sincronizacion': 'PENDIENTE',
        },
      );
    }
    await _repo.agregarItem(
      uuidCarrito: uuid,
      varianteProductoId: varianteProductoId,
      cantidad: cantidad,
      precioUnitario: precioUnitario,
      stockConocido: stockConocido,
    );
    carrito = await obtenerCarritoLocal();
    final subtotal = carrito!.items.fold<double>(
      0,
      (sum, item) => sum + item.subtotal,
    );
    await persistir(
      CartModel(
        id: carrito.id,
        clienteId: carrito.clienteId,
        items: carrito.items,
        subtotal: subtotal,
        descuentoAplicado: carrito.descuentoAplicado,
        total: subtotal - carrito.descuentoAplicado,
        cuponCodigo: carrito.cuponCodigo,
        uuidCarrito: carrito.uuidCarrito,
        dispositivoId: carrito.dispositivoId,
        estado: carrito.estado,
        esOffline: true,
        estadoSincronizacion: carrito.estadoSincronizacion,
      ),
    );
    return (await obtenerCarritoLocal())!;
  }

  Future<CartModel?> actualizarCantidad(int id, int cantidad) async {
    final carrito = await obtenerCarritoLocal();
    if (carrito == null) return null;
    final item = carrito.items.firstWhere((i) => i.id == id);
    await _repo.actualizarItem(
      id,
      cantidad: cantidad,
      precioUnitario: item.precioUnitario,
      stockConocido: item.stockLocalConocido,
    );
    final actualizado = await obtenerCarritoLocal();
    await persistir(actualizado!);
    return actualizado;
  }

  Future<CartModel?> eliminarItem(int id) async {
    final carrito = await obtenerCarritoLocal();
    if (carrito == null) return null;
    await _repo.quitarItem(id);
    final actualizado = await obtenerCarritoLocal();
    if (actualizado != null) await persistir(actualizado);
    return actualizado;
  }

  Future<void> vaciar() async {
    final carrito = await obtenerCarritoLocal();
    if (carrito != null) await _repo.eliminarCarrito(carrito.uuidCarrito);
  }

  Future<CartModel?> recalcularTotales() async {
    final carrito = await obtenerCarritoLocal();
    if (carrito == null) return null;
    final subtotal = carrito.items.fold<double>(
      0,
      (sum, i) => sum + i.subtotal,
    );
    await _repo.guardar(<String, Object?>{
      'uuid_carrito': carrito.uuidCarrito,
      'subtotal': subtotal,
      'total': subtotal - carrito.descuentoAplicado,
    });
    return obtenerCarritoLocal();
  }

  Future<void> persistir(CartModel carrito) async {
    await _repo.guardar(<String, Object?>{
      'uuid_carrito': carrito.uuidCarrito,
      'cliente_id': carrito.clienteId,
      'dispositivo_id': _dispositivoId,
      'estado': carrito.estado,
      'es_offline': 1,
      'estado_sincronizacion': carrito.estadoSincronizacion,
      'subtotal': carrito.subtotal,
      'descuento_aplicado': carrito.descuentoAplicado,
      'total': carrito.total,
      'cupon_codigo': carrito.cuponCodigo,
    });
  }

  Future<CartModel?> recuperarAlAbrir() => obtenerCarritoLocal();

  // [EXAMEN-2] C2.5 (§7.6) CU15: validar -> aceptar nuevo total -> convertir.
  Future<Map<String, Object?>> validarContraServidor(String uuid) async {
    if (_client == null) throw StateError('No hay conexión disponible.');
    final data = await _client.post(
      '${AppConstants.epCarritoOffline}/$uuid/validar',
    );
    return data is Map<String, dynamic> ? data : <String, Object?>{};
  }

  Future<Map<String, Object?>> convertirAOrden(String uuid) async {
    if (_client == null) throw StateError('No hay conexión disponible.');
    final data = await _client.post(
      '${AppConstants.epCarritoOffline}/$uuid/convertir',
    );
    return data is Map<String, dynamic> ? data : <String, Object?>{};
  }

  // [EXAMEN-2] C2.5 CU15: el usuario acepta el nuevo total del servidor.
  Future<CartModel?> aceptarNuevoTotal(String uuid, double nuevoTotal) async {
    final carrito = await obtenerCarritoLocal();
    if (carrito == null || carrito.uuidCarrito != uuid) return carrito;
    await _repo.guardar(<String, Object?>{
      'uuid_carrito': uuid,
      'total': nuevoTotal,
      'subtotal': nuevoTotal,
    });
    return obtenerCarritoLocal();
  }

  CartItemModel _itemDesdeMapa(Map<String, Object?> map) => CartItemModel(
    id: (map['id'] as num?)?.toInt() ?? 0,
    varianteProductoId: (map['variante_producto_id'] as num?)?.toInt() ?? 0,
    cantidad: (map['cantidad'] as num?)?.toInt() ?? 0,
    precioUnitario: (map['precio_unitario'] as num?)?.toDouble() ?? 0,
    subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
    productoNombre: map['producto_nombre']?.toString() ?? 'Prenda',
    stockDisponible: (map['stock_conocido'] as num?)?.toInt() ?? 0,
    precioUnitarioLocal: (map['precio_unitario'] as num?)?.toDouble(),
    stockLocalConocido: (map['stock_conocido'] as num?)?.toInt(),
  );

  // [EXAMEN-2] C2.1: UUID v4 reales (RN-005).
  String _uuid() => _crypto.generarUuid();

  /// Convierte el carrito local en una orden y un pago diferido, ambos con
  /// UUID persistidos. La cola HTTP es la via de sincronizacion idempotente.
  Future<({String uuidOrden, String uuidPago, double total})>
  convertirEnPagoDiferido({
    required int? sucursalId,
    required String? direccionEnvio,
    required int? clienteId,
  }) async {
    final carrito = await obtenerCarritoLocal();
    if (carrito == null || carrito.items.isEmpty) {
      throw StateError('El carrito local esta vacio.');
    }
    final uuidOrden = _uuid();
    final uuidPago = _uuid();
    final db = _database.database;
    if (db == null) throw StateError('La base local no esta abierta.');
    final repo = LocalOrderRepository(db, tenantId: _tenantId);
    final expiraEn = DateTime.now().toUtc().add(const Duration(hours: 24));
    await repo.crear(uuidOrden, <String, Object?>{
      'estado': 'PENDIENTE_PAGO_DIFERIDO',
      'cliente_id': clienteId,
      'subtotal': carrito.subtotal,
      'impuestos': 0,
      'total': carrito.total,
      'moneda': 'BOB',
      'uuid_carrito': carrito.uuidCarrito,
      'expira_en': expiraEn.toIso8601String(),
      'datos_json': jsonEncode(<String, Object?>{
        'direccion_envio': direccionEnvio,
        'sucursal_id': sucursalId,
      }),
      'fecha_registro_local': DateTime.now().toUtc().toIso8601String(),
    });
    await repo.guardarItems(
      uuidOrden,
      carrito.items.map(
        (item) => <String, Object?>{
          'variante_producto_id': item.varianteProductoId,
          'cantidad': item.cantidad,
          'precio_unitario': item.precioUnitario,
          'subtotal': item.subtotal,
          'stock_conocido': item.stockLocalConocido,
        },
      ),
    );
    await _pendingPayments?.registrarPago(
      uuidPago: uuidPago,
      uuidOrden: uuidOrden,
      monto: carrito.total,
      moneda: 'BOB',
      expiraEn: expiraEn,
    );
    await _queue?.encolar(
      uuidOperacion: uuidOrden,
      tipoOperacion: 'ORDEN_PAGO_DIFERIDO',
      sucursalId: sucursalId,
      payload: <String, Object?>{
        'uuid_carrito': carrito.uuidCarrito,
        'uuid_orden': uuidOrden,
        'uuid_pago': uuidPago,
        'sucursal_id': sucursalId,
        'cliente_id': clienteId,
        'direccion_envio': direccionEnvio,
        'acepta_nuevo_total': false,
        'items': carrito.items
            .map(
              (item) => <String, Object?>{
                'variante_producto_id': item.varianteProductoId,
                'cantidad': item.cantidad,
                'precio_unitario_local': item.precioUnitario,
                'stock_local_conocido': item.stockLocalConocido,
              },
            )
            .toList(),
      },
    );
    await _repo.eliminarCarrito(carrito.uuidCarrito);
    return (uuidOrden: uuidOrden, uuidPago: uuidPago, total: carrito.total);
  }
}
