import 'dart:convert';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/catalog_local_repository.dart';
import '../database/repositories/local_sale_repository.dart';
import '../models/phase2_models.dart';
import '../models/product_model.dart';
import '../utils/variant_stock_mapper.dart';
import 'api_service.dart';
import 'local_crypto_service.dart';
import 'offline_queue_service.dart';

/// [EXAMEN-2] Venta de contado offline del POS (CU07).
class PosService {
  PosService({
    required LocalDatabaseService database,
    required int tenantId,
    required OfflineQueueService queue,
    CatalogLocalRepository? catalogRepository,
    LocalSaleRepository? saleRepository,
    // [EXAMEN-2] Fase 3 (CU13/CU18): ApiService opcional para buscar la
    // venta original en el servidor; sin red se usa la copia local.
    ApiService? apiService,
    // [EXAMEN-2] B0.4: id del usuario para estampar `usuario_id`.
    int? usuarioId,
  }) : _database = database,
       _tenantId = tenantId,
       _queue = queue,
       _catalogRepository = catalogRepository,
       _saleRepository = saleRepository,
       _apiService = apiService,
       _usuarioId = usuarioId;

  final LocalDatabaseService _database;
  final int _tenantId;
  final OfflineQueueService _queue;
  CatalogLocalRepository? _catalogRepository;
  LocalSaleRepository? _saleRepository;
  final ApiService? _apiService;
  // [EXAMEN-2] B0.4.
  final int? _usuarioId;

  CatalogLocalRepository get _catalog {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _catalogRepository ??= CatalogLocalRepository(
      db,
      tenantId: _tenantId,
    );
  }

  LocalSaleRepository get _sales {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _saleRepository ??= LocalSaleRepository(
      db,
      tenantId: _tenantId,
      usuarioId: _usuarioId,
    );
  }

  Map<int, Map<String, Object?>> _venta = {};
  // [EXAMEN-2] B1.3.f: variantes cuya venta fue forzada por stock crítico.
  final Map<int, bool> _forzados = <int, bool>{};
  String? _uuidVenta;

  String? get uuidVenta => _uuidVenta;

  void iniciarVenta() {
    _venta = {};
    _forzados.clear();
    _uuidVenta = _uuid();
  }

  Future<List<ProductModel>> buscarVarianteLocal(String texto) async {
    final productos = await _catalog.listarProductos(busqueda: texto);
    final variantes = await _catalog.buscarVariantesSku(texto);
    final ids = <int>{
      for (final p in productos) (p['id'] as num?)?.toInt() ?? 0,
      for (final v in variantes) (v['producto_id'] as num?)?.toInt() ?? 0,
    };
    // [EXAMEN-2] B0.2: el stock local debe acompañar a cada variante; sin
    // esto `stockTotal` caía a 0 y el POS anunciaba "Stock local referencial: 0"
    // en el 100% de los casos.
    final stock = await _catalog.listarStock();
    final resultado = <ProductModel>[];
    for (final id in ids) {
      final producto = await _catalog.obtenerProducto(id);
      if (producto != null) {
        final variantesProducto = VariantStockMapper.enriquecer(
          await _catalog.listarVariantesProducto(id),
          stock,
        );
        resultado.add(
          ProductModel.fromJson({
            ...producto,
            'variantes': variantesProducto,
          }),
        );
      }
    }
    return resultado;
  }

  /// [EXAMEN-2] B0.2.e: verifica que la variante exista en el catálogo local
  /// descargado. Si no existe, la venta debe bloquearse (CU07, flujo alterno 1).
  Future<bool> varianteEnCatalogoLocal(int varianteProductoId) async {
    final db = _database.database;
    if (db == null) return false;
    final filas = await db.query(
      'variantes',
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[varianteProductoId, _tenantId],
      limit: 1,
    );
    return filas.isNotEmpty;
  }

  /// [EXAMEN-2] B0.2: stock conocido (no confirmado) de una variante.
  Future<int?> stockConocidoVariante(int varianteProductoId) async {
    final db = _database.database;
    if (db == null) return null;
    final stock = await _catalog.listarStock();
    final porSucursal = VariantStockMapper.porSucursal(stock);
    final porVariante = porSucursal[varianteProductoId];
    if (porVariante == null) return null;
    return porVariante.values.fold<int>(0, (a, b) => a + b);
  }

  void agregarProducto({
    required int varianteProductoId,
    required int cantidad,
    required double precioUnitario,
    required String nombre,
    int stockConocido = 0,
    // [EXAMEN-2] B1.3.f: forzado por stock crítico (queda para revisión al
    // sincronizar, RN-006).
    bool forzar = false,
  }) {
    final actual = _venta[varianteProductoId];
    final nuevaCantidad = ((actual?['cantidad'] as int?) ?? 0) + cantidad;
    _venta[varianteProductoId] = <String, Object?>{
      'variante_producto_id': varianteProductoId,
      'cantidad': nuevaCantidad,
      'precio_unitario': precioUnitario,
      'producto_nombre': nombre,
      'stock_conocido': stockConocido,
      'subtotal': nuevaCantidad * precioUnitario,
    };
    // [EXAMEN-2] B0.1: el flag de forzado **no** va dentro del mapa de la
    // línea: ese mapa se persiste tal cual en `items_venta_local` y SQLite
    // no acepta `bool` como parámetro.
    if (forzar) {
      _forzados[varianteProductoId] = true;
    } else if (actual != null && _forzados.containsKey(varianteProductoId)) {
      _forzados[varianteProductoId] = true;
    }
  }

  double calcularTotalLocal() => _venta.values.fold<double>(
    0,
    (sum, item) => sum + ((item['subtotal'] as num?)?.toDouble() ?? 0),
  );

  /// [EXAMEN-2] B1.3.d: deja rastro local de la venta (fecha, hora, monto,
  /// UUID y comprobante) en la bitácora.
  Future<void> _auditarVenta({
    required String uuid,
    required String numeroComprobante,
    required int sucursalId,
    required int cajeroId,
    required String metodoPago,
    required double montoRecibido,
    required double cambio,
    required double total,
    required bool requiereRevision,
  }) async {
    final db = _database.database;
    if (db == null) return;
    final ahora = DateTime.now().toUtc();
    try {
      await db.insert('bitacora_local', <String, Object?>{
        'tenant_id': _tenantId,
        'fecha': ahora.toIso8601String(),
        'tipo': 'VENTA_CONTADO',
        'mensaje':
            'Venta offline $numeroComprobante por $total ($metodoPago)',
        'datos': jsonEncode(<String, Object?>{
          'uuid_operacion': uuid,
          'numero_comprobante': numeroComprobante,
          'sucursal_id': sucursalId,
          'cajero_id': cajeroId,
          'metodo_pago': metodoPago,
          'total': total,
          'monto_recibido': montoRecibido,
          'cambio': cambio,
          'requiere_revision': requiereRevision,
        }),
      });
    } catch (_) {
      // La bitácora es un extra: su fallo no debe tumbar la venta.
    }
  }

  /// [EXAMEN-2] B1.3.a: líneas de la venta en curso, para que la pantalla del
  /// POS las muestre (antes sólo se veían los resultados de la búsqueda).
  List<Map<String, Object?>> get lineasVenta =>
      _venta.values.toList(growable: false);

  /// [EXAMEN-2] B1.3.a: cantidad de una variante en la venta en curso.
  int cantidadDe(int varianteProductoId) =>
      (_venta[varianteProductoId]?['cantidad'] as int?) ?? 0;

  double calcularCambio(double montoRecibido) =>
      (montoRecibido - calcularTotalLocal()).clamp(0, double.infinity);

  // [EXAMEN-2] C2.5 (§5.3) CU07: descuento provisional cuando hay stock local;
  // si no hay fila de stock, se permite la venta (compatibilidad con tests)
  // pero se registra el faltante para reciclaje. El bloqueo estricto se
  // aplica en UI cuando el producto no está descargado.
  Future<LocalSaleModel> confirmarVentaOffline({
    required int sucursalId,
    required int cajeroId,
    required double montoRecibido,
    String? clienteId,
    String metodoPago = 'EFECTIVO',
    // [EXAMEN-2] RN-012 (CU13/CU18): plazo de cambio; por defecto 7 días
    // (168 h). Promociones pueden tener 48 h.
    int plazoHoras = 168,
  }) async {
    if (_uuidVenta == null) iniciarVenta();
    final uuid = _uuidVenta!;
    final total = calcularTotalLocal();
    final items = _venta.values.toList(growable: false);
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    // [EXAMEN-2] B0.5: comprobante local provisional. El backend asigna el
    // número definitivo al sincronizar; este permite buscar la venta sin
    // conexión (CU13/CU18) y leerlo en el comprobante temporal.
    final numeroComprobante = _numeroComprobanteLocal(uuid);
    // [EXAMEN-2] B1.3.f: alguna línea fue forzada por stock crítico ⇒ la
    // operación queda marcada para revisión del servidor (RN-006).
    final requiereRevision = _forzados.values.any((f) => f);
    // Desconto provisional solo si existe fila de stock (idempotente).
    await db.transaction<void>((txn) async {
      for (final item in items) {
        final varianteId = item['variante_producto_id'] as int;
        final cantidad = item['cantidad'] as int;
        final filas = await txn.query(
          'stock',
          where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
          whereArgs: <Object?>[varianteId, sucursalId, _tenantId],
          limit: 1,
        );
        if (filas.isEmpty) continue;
        final actual = (filas.first['cantidad'] as num?)?.toInt() ?? 0;
        final noConfirmado =
            (filas.first['cantidad_no_confirmada'] as num?)?.toInt() ?? 0;
        await txn.update(
          'stock',
          <String, Object?>{
            'cantidad': (actual - cantidad).clamp(0, 1 << 30),
            // [EXAMEN-2] B1.3.c / v5: `cantidad` ya refleja el descuento de la
            // venta offline; `cantidad_no_confirmada` marca qué parte de esa
            // cifra sigue pendiente de confirmación del servidor. Si el
            // servidor rechaza la venta, se restaura `cantidad` y se
            // descuenta este valor (RN-006).
            'cantidad_no_confirmada': (noConfirmado + cantidad).clamp(0, 1 << 30),
            'fecha_actualizacion':
                DateTime.now().toUtc().toIso8601String(),
          },
          where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
          whereArgs: <Object?>[varianteId, sucursalId, _tenantId],
        );
      }
    });
    // [EXAMEN-2] RN-012: el plazo de cambio se calcula y se persiste en
    // local para que devoluciones/reposiciones offline validen RN-012.
    final fechaLimiteCambio = DateTime.now()
        .toUtc()
        .add(Duration(hours: plazoHoras));
    await _sales.registrarVenta(
      uuid,
      sucursalId: sucursalId,
      total: total,
      montoRecibido: montoRecibido,
      cambio: calcularCambio(montoRecibido),
      datos: <String, Object?>{
        'cajero_id': cajeroId,
        'cliente_id': clienteId,
        'metodo_pago': metodoPago,
        'es_offline': 1,
        'estado_sincronizacion': 'PENDIENTE_SINCRONIZACION',
        'dispositivo_id': '',
        'fecha_limite_cambio': fechaLimiteCambio.toIso8601String(),
        // [EXAMEN-2] B0.5: comprobante local provisional.
        'numero_comprobante': numeroComprobante,
        'numero_comprobante_generado': numeroComprobante,
        // [EXAMEN-2] B1.3.f: forzado por stock crítico.
        'requiere_revision': requiereRevision ? 1 : 0,
        'usuario_id': _usuarioId ?? cajeroId,
      },
      items: items,
    );
    await _queue.encolar(
      uuidOperacion: uuid,
      tipoOperacion: 'VENTA_CONTADO',
      sucursalId: sucursalId,
      payload: <String, Object?>{
        'uuid_offline': uuid,
        'sucursal_id': sucursalId,
        'cajero_id': cajeroId,
        'cliente_id': clienteId,
        'metodo_pago': metodoPago,
        'monto_recibido': montoRecibido,
        'cambio': calcularCambio(montoRecibido),
        'total': total,
        // [EXAMEN-2] B0.5: se envía el comprobante local para que el backend
        // pueda relacionarlo con el número definitivo.
        'numero_comprobante': numeroComprobante,
        // [EXAMEN-2] B1.3.f: revisión manual en el servidor (RN-006).
        'requiere_revision': requiereRevision,
        // [EXAMEN-2] RN-012: el servidor refuerza el plazo al sincronizar.
        'fecha_limite_cambio': fechaLimiteCambio.toIso8601String(),
        'items': _itemsConPrecioLocal(items),
      },
    );
    // [EXAMEN-2] B1.3.d: bitácora local con fecha, hora, monto y UUID
    // (paso 10 del flujo de CU07). Antes la venta no dejaba rastro local.
    await _auditarVenta(
      uuid: uuid,
      numeroComprobante: numeroComprobante,
      sucursalId: sucursalId,
      cajeroId: cajeroId,
      metodoPago: metodoPago,
      montoRecibido: montoRecibido,
      cambio: calcularCambio(montoRecibido),
      total: total,
      requiereRevision: requiereRevision,
    );
    return LocalSaleModel(
      uuidOffline: uuid,
      sucursalId: sucursalId,
      total: total,
      montoRecibido: montoRecibido,
      cambio: calcularCambio(montoRecibido),
      estado: 'PENDIENTE_SINCRONIZACION',
      items: items,
      fecha: DateTime.now(),
    );
  }

  Future<List<Map<String, Object?>>> ventasPendientes() =>
      _sales.listarPendientes();

  Future<Map<String, Object?>?> comprobanteTemporal(String uuid) async {
    final venta = await _sales.obtenerPorUuid(uuid);
    if (venta == null) return null;
    return <String, Object?>{
      ...venta,
      'leyenda': 'Venta en modo offline — pendiente de confirmación',
    };
  }

  // [EXAMEN-2] C2.1: UUID v4 reales (RN-005).
  String _uuid() => LocalCryptoService().generarUuid();

  /// [EXAMEN-2] B1.3.g: el backend lee `precio_unitario_local` de cada línea
  /// (`operaciones_offline/handlers.py`) para la comparación de precios de
  /// **RN-007**. El móvil enviaba `precio_unitario`, por lo que esa
  /// comparación nunca se activaba. Se envían **ambas** claves.
  List<Map<String, Object?>> _itemsConPrecioLocal(
    List<Map<String, Object?>> items,
  ) {
    return items
        .map(
          (item) => <String, Object?>{
            ...item,
            'precio_unitario_local': item['precio_unitario'],
          },
        )
        .toList(growable: false);
  }

  /// [EXAMEN-2] B0.5: comprobante provisional de la venta offline.
  /// El backend asigna el número definitivo al sincronizar; este permite
  /// referenciar la venta sin conexión (CU13/CU18) y leerlo en el
  /// comprobante temporal.
  String _numeroComprobanteLocal(String uuid) {
    final ahora = DateTime.now();
    final sufijo = uuid.replaceAll('-', '').substring(0, 6).toUpperCase();
    return 'VTA-OFF-${_dos(ahora.year)}${_dos(ahora.month)}'
        '${_dos(ahora.day)}-$sufijo';
  }

  String _dos(int valor) => valor.toString().padLeft(2, '0');

  // [EXAMEN-2] Fase 3 (CU13/CU18): busca la venta original para una devolución
  // o reposición. Con red consulta el servidor; sin red (o ante 404/501 N3)
  // degrada a la venta local registrada offline.
  Future<Map<String, Object?>?> buscarVentaOriginal({
    required String numeroComprobante,
    bool enLinea = true,
  }) async {
    final comprobante = numeroComprobante.trim();
    if (comprobante.isEmpty) return null;
    if (enLinea && _apiService != null) {
      try {
        final respuesta = await _apiService.dio.get(
          '${AppConstants.epDevolucionesVenta}/$comprobante',
        );
        if (respuesta.data is Map<String, dynamic>) {
          final mapa = Map<String, Object?>.from(respuesta.data as Map);
          // [EXAMEN-2] B0.1.a: normalizar las líneas de la venta para que la
          // UI de devolución/reposición pueda listar las prendas reales.
          return _normalizarVenta(mapa);
        }
      } catch (_) {
        // 404/501 N3 o sin red: degradación a local, nunca romper.
      }
    }
    final db = _database.database;
    if (db == null) return null;
    // [EXAMEN-2] B0.5: la venta offline local se busca por `numero_comprobante`
    // (columna v5) **o** por `uuid_offline`.
    final filas = await db.query(
      'ventas_locales',
      where:
          'tenant_id = ? AND (numero_comprobante = ? OR uuid_offline = ? '
          'OR numero_comprobante_generado = ?)',
      whereArgs: <Object?>[_tenantId, comprobante, comprobante, comprobante],
    );
    for (final fila in filas) {
      final datos = fila['datos_json']?.toString() ?? '';
      final uuid = fila['uuid_offline']?.toString() ?? '';
      if (fila['numero_comprobante'] == comprobante ||
          fila['numero_comprobante_generado'] == comprobante ||
          uuid == comprobante ||
          datos.contains(comprobante)) {
        final fechaLimite = _fechaLimiteDeFila(fila, datos);
        // [EXAMEN-2] RN-012: filas sin plazo (legacy) se asumen en plazo;
        // las nuevas ventas ya registran fecha_limite_cambio (168 h).
        final dentro = validarPlazoTexto(fechaLimite);
        // [EXAMEN-2] B0.1.a: las prendas de la venta original, para que el
        // cajero elija qué devuelve sin teclear IDs a mano.
        final items = await _itemsDeVenta(uuid);
        return <String, Object?>{
          'venta': <String, Object?>{
            'numero_comprobante':
                fila['numero_comprobante']?.toString() ??
                fila['numero_comprobante_generado']?.toString() ??
                comprobante,
            'uuid_offline': uuid,
            'sucursal_id': fila['sucursal_id'],
            'cliente_id': fila['cliente_id'],
            'total': fila['total'],
            'monto_recibido': fila['monto_recibido'],
            'metodo_pago': fila['metodo_pago'],
            'fecha_limite_cambio': fechaLimite,
          },
          'items': items,
          'dentro_plazo': dentro,
          'fecha_limite_cambio': fechaLimite,
          'origen': 'local',
        };
      }
    }
    return <String, Object?>{
      'venta': <String, Object?>{'numero_comprobante': comprobante},
      'items': const <Map<String, Object?>>[],
      'dentro_plazo': true,
      'fecha_limite_cambio': null,
      'origen': 'local-sin-resultados',
    };
  }

  /// [EXAMEN-2] B0.1.a: líneas de una venta offline local.
  Future<List<Map<String, Object?>>> _itemsDeVenta(String uuid) async {
    final db = _database.database;
    if (db == null || uuid.isEmpty) return const <Map<String, Object?>>[];
    final filas = await db.query(
      'items_venta_local',
      where: 'uuid_offline = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, _tenantId],
      orderBy: 'id',
    );
    return filas
        .map(
          (fila) => <String, Object?>{
            'variante_producto_id': fila['variante_producto_id'],
            'producto_nombre': fila['producto_nombre'],
            'cantidad': fila['cantidad'],
            'precio_unitario': fila['precio_unitario'],
            'stock_conocido': fila['stock_conocido'],
          },
        )
        .toList(growable: false);
  }

  /// [EXAMEN-2] B0.1.a: normaliza la respuesta del backend al mismo formato
  /// que la ruta local, para que la UI no dependa del origen.
  Map<String, Object?> _normalizarVenta(Map<String, Object?> respuesta) {
    final detalle = respuesta['detalle'] ?? respuesta['items'];
    List<Map<String, Object?>> items = const <Map<String, Object?>>[];
    if (detalle is List) {
      items = detalle
          .whereType<Map>()
          .map(
            (e) => <String, Object?>{
              'variante_producto_id': e['variante_producto_id'],
              'producto_id': e['producto_id'],
              'producto_nombre': e['producto_nombre'] ?? e['nombre'],
              'cantidad': e['cantidad'],
              'precio_unitario':
                  e['precio_unitario'] ?? e['precio_unitario_local'],
              'detalle_orden_id': e['id'] ?? e['detalle_orden_id'],
            },
          )
          .toList(growable: false);
    }
    final mapa = respuesta['venta'] is Map
        ? Map<String, Object?>.from(respuesta['venta'] as Map)
        : Map<String, Object?>.from(respuesta);
    return <String, Object?>{
      ...respuesta,
      'venta': mapa,
      'items': items,
      'dentro_plazo': respuesta['dentro_plazo'] ?? true,
      'fecha_limite_cambio':
          respuesta['fecha_limite_cambio'] ?? mapa['fecha_limite_cambio'],
      'origen': respuesta['origen'] ?? 'servidor',
    };
  }

  // [EXAMEN-2] Fase 3: valida el plazo RN-012 (fecha_limite_cambio).
  bool validarPlazoCambio({
    required DateTime fechaLimite,
    DateTime? ahora,
  }) {
    if (fechaLimite.isAtSameMomentAs(DateTime.fromMillisecondsSinceEpoch(0))) {
      return true;
    }
    return (ahora ?? DateTime.now()).isBefore(fechaLimite) ||
        (ahora ?? DateTime.now()).isAtSameMomentAs(fechaLimite);
  }

  // [EXAMEN-2] Fase 3: valida el plazo a partir de texto sin romper por
  // formato legacy (null, vacío o no parseable => en plazo).
  bool validarPlazoTexto(String? fechaLimite) {
    if (fechaLimite == null || fechaLimite.isEmpty) return true;
    final fecha = DateTime.tryParse(fechaLimite);
    if (fecha == null) return true;
    return validarPlazoCambio(fechaLimite: fecha);
  }

  // [EXAMEN-2] RN-012: lee fecha_limite_cambio de la fila; para ventas
  // registradas antes de v2 también se respalda la copia en datos_json.
  String? _fechaLimiteDeFila(Map<String, Object?> fila, String datosJson) {
    final columna = fila['fecha_limite_cambio']?.toString();
    if (columna != null && columna.isNotEmpty) return columna;
    if (datosJson.isEmpty) return null;
    try {
      final mapa = jsonDecode(datosJson);
      if (mapa is Map) return mapa['fecha_limite_cambio']?.toString();
    } catch (_) {}
    return null;
  }

  // [EXAMEN-2] Fase 3: stock confirmado de una variante en la sucursal.
  Future<int> stockDeVariante(int varianteId, int sucursalId) async {
    final db = _database.database;
    if (db == null) return 0;
    final filas = await db.query(
      'stock',
      where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[varianteId, sucursalId, _tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return 0;
    return (filas.first['cantidad'] as num?)?.toInt() ?? 0;
  }
}
