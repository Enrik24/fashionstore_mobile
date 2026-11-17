import 'dart:convert';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/offline_cart_repository.dart';
import '../database/repositories/local_config_repository.dart';
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
    // [EXAMEN-2] B0.4: id del usuario para estampar `usuario_id`.
    int? usuarioId,
  }) : _database = database,
       _tenantId = tenantId,
       _dispositivoId = dispositivoId,
       _repository = repository,
       _client = client,
       _queue = queue,
       _pendingPayments = pendingPayments,
       _crypto = crypto ?? LocalCryptoService(),
       _usuarioId = usuarioId;

  final LocalDatabaseService _database;
  final int _tenantId;
  final String _dispositivoId;
  OfflineCartRepository? _repository;
  final OfflineApiClient? _client;
  final OfflineQueueService? _queue;
  final PendingPaymentService? _pendingPayments;
  // [EXAMEN-2] C2.1: UUID v4 reales.
  final LocalCryptoService _crypto;
  // [EXAMEN-2] B0.4.
  final int? _usuarioId;
  // [EXAMEN-2] B1.1.d: configuración offline del tenant (vigencia de orden,
  // tasa de impuestos, habilitación del carrito).
  LocalConfigRepository? _configRepository;

  /// [EXAMEN-2] B1.1: inyecta el repositorio de configuración del tenant.
  void configurarRepositorioConfig(LocalConfigRepository? repository) {
    _configRepository = repository;
  }

  /// [EXAMEN-2] B1.1.a: tasa de impuestos vigente para el total estimado.
  Future<double> tasaImpuestos() async {
    final repo = _configRepository;
    if (repo == null) return 0;
    try {
      return await repo.leerTasaImpuestos(_tenantId);
    } catch (_) {
      return 0;
    }
  }

  OfflineCartRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _repository ??= OfflineCartRepository(
      db,
      tenantId: _tenantId,
      usuarioId: _usuarioId,
    );
  }

  Future<CartModel?> obtenerCarritoLocal() async {
    final fila = await _repo.obtenerActivo();
    if (fila == null) return null;
    final items = await _repo.listarItems(fila['uuid_carrito'].toString());
    // [FIX] La reconstrucción es async: los metadatos del producto (nombre,
    // imagen, talla, color) se resuelven contra el catálogo descargado.
    final itemsModel = <CartItemModel>[];
    for (final mapa in items) {
      itemsModel.add(await _itemDesdeMapa(mapa));
    }
    return CartModel(
      id: 0,
      clienteId: (fila['cliente_id'] as num?)?.toInt() ?? 0,
      items: itemsModel,
      subtotal: (fila['subtotal'] as num?)?.toDouble() ?? 0,
      descuentoAplicado: (fila['descuento_aplicado'] as num?)?.toDouble() ?? 0,
      total: (fila['total'] as num?)?.toDouble() ?? 0,
      // [EXAMEN-2] B1.1.a / B1.1.j.
      impuestos: (fila['impuestos'] as num?)?.toDouble() ?? 0,
      selloDescarga: fila['sello_descarga']?.toString(),
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
    // [EXAMEN-2] B1.1.a: el total estimado incluye los impuestos vigentes.
    final tasa = await tasaImpuestos();
    final impuestos = subtotal * tasa;
    await persistir(
      CartModel(
        id: carrito.id,
        clienteId: carrito.clienteId,
        items: carrito.items,
        subtotal: subtotal,
        descuentoAplicado: carrito.descuentoAplicado,
        total: subtotal + impuestos - carrito.descuentoAplicado,
        impuestos: impuestos,
        cuponCodigo: carrito.cuponCodigo,
        uuidCarrito: carrito.uuidCarrito,
        dispositivoId: carrito.dispositivoId,
        estado: carrito.estado,
        esOffline: true,
        estadoSincronizacion: carrito.estadoSincronizacion,
        selloDescarga: carrito.selloDescarga,
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
    // [EXAMEN-2] B1.6.a: al cambiar la cantidad hay que **recalcular** los
    // totales (subtotal, impuestos y total); antes se persistía el modelo
    // con los totales(old) de la base.
    if (actualizado != null) await persistir(actualizado);
    return await recalcularTotales();
  }

  Future<CartModel?> eliminarItem(int id) async {
    final carrito = await obtenerCarritoLocal();
    if (carrito == null) return null;
    await _repo.quitarItem(id);
    // [EXAMEN-2] B1.6.a: recalcular tras quitar una prenda.
    await recalcularTotales();
    return obtenerCarritoLocal();
  }

  Future<void> vaciar() async {
    final carrito = await obtenerCarritoLocal();
    if (carrito != null) await _repo.eliminarCarrito(carrito.uuidCarrito);
  }

  /// [EXAMEN-2] B1.1.a: recalcula subtotal, impuestos y total estimado.
  ///
  /// Antes este método era **código muerto** y el carrito guardaba siempre
  /// `impuestos = 0`, de modo que el total offline no coincidía con el del
  /// servidor. La tasa sale de la configuración vigente del tenant
  /// (`impuestos.tasa_total` del paquete offline).
  Future<CartModel?> recalcularTotales() async {
    final carrito = await obtenerCarritoLocal();
    if (carrito == null) return null;
    final subtotal = carrito.items.fold<double>(
      0,
      (sum, i) => sum + i.subtotal,
    );
    final tasa = await tasaImpuestos();
    final impuestos = subtotal * tasa;
    final total = subtotal + impuestos - carrito.descuentoAplicado;
    await _repo.guardar(<String, Object?>{
      'uuid_carrito': carrito.uuidCarrito,
      'subtotal': subtotal,
      'impuestos': impuestos,
      'total': total < 0 ? 0 : total,
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
      'impuestos': carrito.impuestos,
      'descuento_aplicado': carrito.descuentoAplicado,
      'total': carrito.total,
      'cupon_codigo': carrito.cuponCodigo,
      // [EXAMEN-2] B1.6.j: el carrito recuerda con qué sello de descarga se
      // calcularon sus precios (son referenciales hasta la sincronización).
      'sello_descarga': carrito.selloDescarga ?? await _selloDescargaActual(),
    });
  }

  /// [EXAMEN-2] B1.6.j: sello de la última descarga del catálogo.
  Future<String?> _selloDescargaActual() async {
    final db = _database.database;
    if (db == null) return null;
    final filas = await db.query(
      'meta',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>['sello_descarga', _tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return filas.first['valor']?.toString();
  }

  Future<CartModel?> recuperarAlAbrir() => obtenerCarritoLocal();

  /// [FIX] Garantiza que exista un carrito **local** con los ítems indicados
  /// antes de convertir a orden con pago diferido (CU15).
  ///
  /// Cubre el caso "agregué al carrito con conexión y me quedé sin red": el
  /// carrito del servidor no está disponible offline, pero los ítems ya
  /// cargados en memoria (mismos ids de variante, cantidades y precios que
  /// devolvió el servidor) se siembran en SQLite para poder diferir el pago.
  /// Si ya existe un carrito local con ítems, no toca nada (evita duplicados).
  Future<void> asegurarCarritoConItems(List<CartItemModel> items) async {
    if (items.isEmpty) return;
    final existente = await obtenerCarritoLocal();
    if (existente != null && existente.items.isNotEmpty) return;
    final uuid = existente?.uuidCarrito ?? _uuid();
    if (existente == null) {
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
    for (final item in items) {
      await _repo.agregarItem(
        uuidCarrito: uuid,
        varianteProductoId: item.varianteProductoId,
        cantidad: item.cantidad,
        precioUnitario: item.precioUnitario,
        stockConocido: item.stockLocalConocido ?? item.stockDisponible,
      );
    }
  }

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

  Future<CartItemModel> _itemDesdeMapa(Map<String, Object?> map) async {
    final varianteProductoId =
        (map['variante_producto_id'] as num?)?.toInt() ?? 0;
    var productoNombre = map['producto_nombre']?.toString() ?? 'Prenda';
    String? productoImagen = map['producto_imagen']?.toString();
    String? tallaNombre;
    String? colorNombre;
    String? colorHex;
    String? skuVariante;

    // [FIX] La tabla `items_carrito` no guarda metadatos del producto: el
    // nombre, la imagen, la talla, el color y el SKU se resuelven del
    // catálogo descargado (tablas `variantes`/`productos`). Antes la tarjeta
    // mostraba "Prenda" y una imagen genérica aunque el catálogo estuviera
    // disponible (online u offline).
    final datos = await _metadatosDeVariante(varianteProductoId);
    if (datos != null) {
      if (map['producto_nombre'] == null &&
          datos['producto_nombre'] != null) {
        productoNombre = datos['producto_nombre']!;
      }
      productoImagen ??= datos['producto_imagen'];
      tallaNombre = datos['talla'];
      colorNombre = datos['color'];
      colorHex = datos['color_hex'];
      skuVariante = datos['sku_variante'];
    }

    return CartItemModel(
      id: (map['id'] as num?)?.toInt() ?? 0,
      varianteProductoId: varianteProductoId,
      cantidad: (map['cantidad'] as num?)?.toInt() ?? 0,
      precioUnitario: (map['precio_unitario'] as num?)?.toDouble() ?? 0,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      productoNombre: productoNombre,
      productoImagen: productoImagen,
      tallaNombre: tallaNombre,
      colorNombre: colorNombre,
      colorHex: colorHex,
      skuVariante: skuVariante,
      // [EXAMEN-2] B1.6.c: `stock_conocido` nulo significa "sin dato local",
      // NO "sin stock". Antes se convertía en 0 y el carrito borraba el ítem.
      stockDisponible: (map['stock_conocido'] as num?)?.toInt(),
      precioUnitarioLocal: (map['precio_unitario'] as num?)?.toDouble(),
      stockLocalConocido: (map['stock_conocido'] as num?)?.toInt(),
    );
  }

  /// [FIX] Metadatos reales de la variante para los ítems del carrito local.
  ///
  /// `variantes` trae `talla`/`color` embebidos (payload del backend Examen 2)
  /// y `productos` trae `imagenes` (lista JSON de Cloudinary) o `imagen_url`.
  Future<Map<String, String?>?> _metadatosDeVariante(
    int varianteProductoId,
  ) async {
    final db = _database.database;
    if (db == null || varianteProductoId <= 0) return null;
    try {
      final filasVar = await db.query(
        'variantes',
        where: 'id = ? AND tenant_id = ?',
        whereArgs: <Object?>[varianteProductoId, _tenantId],
        limit: 1,
      );
      if (filasVar.isEmpty) return null;
      final variante = filasVar.first;
      final productoId = (variante['producto_id'] as num?)?.toInt() ?? 0;

      String? nombre;
      String? imagen;
      if (productoId > 0) {
        final filasProd = await db.query(
          'productos',
          where: 'id = ? AND tenant_id = ?',
          whereArgs: <Object?>[productoId, _tenantId],
          limit: 1,
        );
        if (filasProd.isNotEmpty) {
          final producto = filasProd.first;
          nombre = producto['nombre']?.toString();
          imagen = _primeraImagen(producto);
        }
      }

      String? talla = variante['talla']?.toString();
      String? color = variante['color']?.toString();
      String? colorHex;
      final tallaId = (variante['talla_id'] as num?)?.toInt();
      final colorId = (variante['color_id'] as num?)?.toInt();
      if ((talla == null || talla.isEmpty) && tallaId != null && tallaId > 0) {
        final filasTalla = await db.query(
          'tallas',
          where: 'id = ? AND tenant_id = ?',
          whereArgs: <Object?>[tallaId, _tenantId],
          limit: 1,
        );
        if (filasTalla.isNotEmpty) talla = filasTalla.first['nombre']?.toString();
      }
      if ((color == null || color.isEmpty) && colorId != null && colorId > 0) {
        final filasColor = await db.query(
          'colores',
          where: 'id = ? AND tenant_id = ?',
          whereArgs: <Object?>[colorId, _tenantId],
          limit: 1,
        );
        if (filasColor.isNotEmpty) {
          color = filasColor.first['nombre']?.toString();
          colorHex = filasColor.first['codigo']?.toString();
        }
      }
      return <String, String?>{
        'producto_nombre': nombre,
        'producto_imagen': imagen,
        'talla': (talla != null && talla.isNotEmpty) ? talla : null,
        'color': (color != null && color.isNotEmpty) ? color : null,
        'color_hex': (colorHex != null && colorHex.isNotEmpty) ? colorHex : null,
        'sku_variante': variante['sku_variante']?.toString(),
      };
    } catch (_) {
      return null;
    }
  }

  /// [FIX] Primera imagen real del producto local (`imagenes` es una lista
  /// JSON; `imagen_url` es el respaldo de una sola URL).
  String? _primeraImagen(Map<String, Object?> producto) {
    final crudo = producto['imagenes'];
    var lista = <String>[];
    if (crudo is List) {
      lista = crudo.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } else if (crudo is String && crudo.isNotEmpty) {
      try {
        final decodificado = jsonDecode(crudo);
        if (decodificado is List) {
          lista = decodificado
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList();
        } else {
          lista = <String>[crudo];
        }
      } catch (_) {
        lista = <String>[crudo];
      }
    }
    if (lista.isNotEmpty) return lista.first;
    final url = producto['imagen_url']?.toString();
    return (url != null && url.isNotEmpty) ? url : null;
  }

  // [EXAMEN-2] C2.1: UUID v4 reales (RN-005).
  String _uuid() => _crypto.generarUuid();

  /// [EXAMEN-2] B1.1.d: horas de vigencia de una orden con pago diferido.
  /// Viene de la configuración offline del tenant (`max_dias_orden_pendiente`);
  /// por defecto 24 h (RN-016).
  Future<int> _horasVigenciaOrden() async {
    final repo = _configRepository;
    if (repo == null) return 24;
    try {
      final config = await repo.leer(_tenantId);
      final dias = config?.maxDiasOrdenPendiente ?? 1;
      if (dias <= 0) return 24;
      return dias * 24;
    } catch (_) {
      return 24;
    }
  }

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
    final repo = LocalOrderRepository(
      db,
      tenantId: _tenantId,
      usuarioId: _usuarioId,
    );
    // [EXAMEN-2] B1.1.d: la vigencia de la orden pendiente la fija el tenant
    // (`max_dias_orden_pendiente`, por defecto 24 h según la RN-016).
    final expiraEn = DateTime.now()
        .toUtc()
        .add(Duration(hours: await _horasVigenciaOrden()));
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
        // RN-014: el servidor recalcula precios, impuestos y descuentos. Se
        // acepta el total vigente (igual que el frontend web); enviar `false`
        // provocaba el rechazo PRECIO_DESACTUALIZADO en bucle al sincronizar.
        'acepta_nuevo_total': true,
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
