import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/catalog_local_repository.dart';
import '../database/repositories/local_sale_repository.dart';
import '../models/phase2_models.dart';
import '../models/product_model.dart';
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
  }) : _database = database,
       _tenantId = tenantId,
       _queue = queue,
       _catalogRepository = catalogRepository,
       _saleRepository = saleRepository,
       _apiService = apiService;

  final LocalDatabaseService _database;
  final int _tenantId;
  final OfflineQueueService _queue;
  CatalogLocalRepository? _catalogRepository;
  LocalSaleRepository? _saleRepository;
  final ApiService? _apiService;

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
    return _saleRepository ??= LocalSaleRepository(db, tenantId: _tenantId);
  }

  Map<int, Map<String, Object?>> _venta = {};
  String? _uuidVenta;

  String? get uuidVenta => _uuidVenta;

  void iniciarVenta() {
    _venta = {};
    _uuidVenta = _uuid();
  }

  Future<List<ProductModel>> buscarVarianteLocal(String texto) async {
    final productos = await _catalog.listarProductos(busqueda: texto);
    final variantes = await _catalog.buscarVariantesSku(texto);
    final ids = <int>{
      for (final p in productos) (p['id'] as num?)?.toInt() ?? 0,
      for (final v in variantes) (v['producto_id'] as num?)?.toInt() ?? 0,
    };
    final resultado = <ProductModel>[];
    for (final id in ids) {
      final producto = await _catalog.obtenerProducto(id);
      if (producto != null) {
        resultado.add(
          ProductModel.fromJson({
            ...producto,
            'variantes': await _catalog.listarVariantesProducto(id),
          }),
        );
      }
    }
    return resultado;
  }

  void agregarProducto({
    required int varianteProductoId,
    required int cantidad,
    required double precioUnitario,
    required String nombre,
    int stockConocido = 0,
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
  }

  double calcularTotalLocal() => _venta.values.fold<double>(
    0,
    (sum, item) => sum + ((item['subtotal'] as num?)?.toDouble() ?? 0),
  );

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
  }) async {
    if (_uuidVenta == null) iniciarVenta();
    final uuid = _uuidVenta!;
    final total = calcularTotalLocal();
    final items = _venta.values.toList(growable: false);
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
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
        await txn.update(
          'stock',
          <String, Object?>{
            'cantidad': (actual - cantidad).clamp(0, 1 << 30),
            'fecha_actualizacion':
                DateTime.now().toUtc().toIso8601String(),
          },
          where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
          whereArgs: <Object?>[varianteId, sucursalId, _tenantId],
        );
      }
    });
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
        'items': items,
      },
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
          return respuesta.data as Map<String, Object?>;
        }
      } catch (_) {
        // 404/501 N3 o sin red: degradación a local, nunca romper.
      }
    }
    final db = _database.database;
    if (db == null) return null;
    // Venta offline local por uuid_o ... datos_json de ventas_locales.
    final filas = await db.query(
      'ventas_locales',
      where: 'tenant_id = ?',
      whereArgs: <Object?>[_tenantId],
    );
    for (final fila in filas) {
      final datos = fila['datos_json']?.toString() ?? '';
      if (fila['uuid_offline'] == comprobante ||
          datos.contains(comprobante)) {
        final fechaLimite = fila['fecha_limite_cambio']?.toString();
        final dentro = fechaLimite == null
            ? true
            : validarPlazoCambio(fechaLimite: DateTime.parse(fechaLimite));
        return <String, Object?>{
          'venta': <String, Object?>{
            'numero_comprobante': comprobante,
            'uuid_offline': fila['uuid_offline'],
            'sucursal_id': fila['sucursal_id'],
            'total': fila['total'],
            'fecha_limite_cambio': fechaLimite,
          },
          'dentro_plazo': dentro,
          'fecha_limite_cambio': fechaLimite,
          'origen': 'local',
        };
      }
    }
    return <String, Object?>{
      'venta': <String, Object?>{'numero_comprobante': comprobante},
      'dentro_plazo': true,
      'fecha_limite_cambio': null,
      'origen': 'local-sin-resultados',
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

  // [EXAMEN-2] Fase 3 (CU18): reserva provisional de la prenda nueva.
  // Devuelve false si no hay stock local confirmado (RN-022 -> alternativas).
  Future<bool> reservarPrendaNueva({
    required int varianteCambioId,
    required int sucursalId,
    required int cantidad,
  }) async {
    final db = _database.database;
    if (db == null) return false;
    final filas = await db.query(
      'stock',
      where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[varianteCambioId, sucursalId, _tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return false;
    final disponible =
        ((filas.first['cantidad'] as num?)?.toInt() ?? 0) -
        ((filas.first['cantidad_reservada'] as num?)?.toInt() ?? 0);
    if (disponible < cantidad) return false;
    final reservada =
        ((filas.first['cantidad_reservada'] as num?)?.toInt() ?? 0) +
        cantidad;
    await db.update(
      'stock',
      <String, Object?>{
        'cantidad_reservada': reservada,
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[varianteCambioId, sucursalId, _tenantId],
    );
    return true;
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
