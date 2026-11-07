import 'dart:convert';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/catalog_local_repository.dart';
import '../database/repositories/local_customer_repository.dart';
import '../models/phase2_models.dart';
import '../models/product_model.dart';
import 'device_service.dart';

/// [EXAMEN-2] Descarga y consulta del paquete offline (CU05).
class OfflineCatalogService {
  OfflineCatalogService({
    required LocalDatabaseService database,
    required int tenantId,
    required OfflineApiClient client,
    CatalogLocalRepository? repository,
  }) : _database = database,
       _tenantId = tenantId,
       _client = client,
       _repository = repository;

  final LocalDatabaseService _database;
  final int _tenantId;
  final OfflineApiClient _client;
  CatalogLocalRepository? _repository;

  OfflineDownloadStatus _estado = const OfflineDownloadStatus();
  OfflineDownloadStatus get estadoDescarga => _estado;
  DateTime? get selloDescarga => _estado.sello;

  CatalogLocalRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _repository ??= CatalogLocalRepository(db, tenantId: _tenantId);
  }

  // [EXAMEN-2] C2.4: GET /offline/version compara sello/cursor antes de bajar paquete.
  Future<Map<String, dynamic>> consultarVersion() async {
    final data = await _client.get(AppConstants.epOfflineVersion);
    return data is Map<String, dynamic>
        ? data
        : <String, dynamic>{'version': data?.toString()};
  }

  // [EXAMEN-2] C2.4: GET /offline/stock incremental por sucursal.
  Future<void> descargarStock({int? sucursalId}) async {
    final data = await _client.get(
      AppConstants.epOfflineStock,
      queryParameters: sucursalId == null ? null : {'sucursal_id': sucursalId},
    );
    final paquete = data is Map<String, dynamic>
        ? data
        : {'stock': data};
    await guardarPaquete(paquete, sucursalId: sucursalId, incremental: true);
  }

  // [EXAMEN-2] C2.4: GET /offline/clientes (PII opcional; respetar incluirClientes).
  Future<void> descargarClientes() async {
    final data = await _client.get(AppConstants.epOfflineClientes);
    final lista = data is List ? data : data is Map ? data['clientes'] : null;
    if (lista is! List) return;
    final db = _database.database;
    if (db == null) return;
    final repo = LocalCustomerRepository(db, tenantId: _tenantId);
    await repo.guardarClientes(
      lista
          .whereType<Map>()
          .map((e) => Map<String, Object?>.from(e)..['tenant_id'] = _tenantId),
    );
  }

  // [EXAMEN-2] C2.4: GET /offline/promociones (sin tabla propia; se guarda en meta).
  Future<void> descargarPromociones() async {
    final data = await _client.get(AppConstants.epOfflinePromociones);
    await _guardarMeta(clave: 'promociones_offline', valor: jsonEncode(data));
  }

  // [EXAMEN-2] C2.4: POST /offline/descargas/registrar avisa al backend.
  Future<void> registrarDescarga({
    int? cantidadProductos,
    DateTime? sello,
  }) async {
    try {
      await _client.post(
        AppConstants.epOfflineDescargasRegistrar,
        data: <String, Object?>{
          'cantidad_productos': cantidadProductos,
          'sello': sello?.toUtc().toIso8601String(),
          'fecha': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } catch (_) {}
  }

  Future<OfflineDownloadStatus> descargarPaquete({
    int? sucursalId,
    bool incluirClientes = true,
  }) async {
    _estado = _estado.copyWith(enProgreso: true, error: null);
    try {
      final data = await _client.get(
        AppConstants.epOfflinePaquete,
        queryParameters: sucursalId == null
            ? null
            : {'sucursal_id': sucursalId},
      );
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Paquete offline inválido.');
      }
      await guardarPaquete(
        data,
        sucursalId: sucursalId,
        incluirClientes: incluirClientes,
      );
      final ahora = DateTime.now();
      await _guardarMeta(
        clave: 'ultima_descarga_completa',
        valor: ahora.toUtc().toIso8601String(),
      );
      await _guardarMeta(
        clave: 'sello_descarga',
        valor: ahora.toUtc().toIso8601String(),
      );
      _estado = OfflineDownloadStatus(
        ultimaDescargaCompleta: ahora,
        cursorCatalogo: data['cursor']?.toString(),
        sello: ahora,
      );
      await registrarDescarga(
        sello: ahora,
        cantidadProductos: (data['productos'] as List?)?.length,
      );
      return _estado;
    } catch (error) {
      _estado = _estado.copyWith(
        enProgreso: false,
        incompleto: true,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<OfflineDownloadStatus> descargarIncremental({String? cursor}) async {
    _estado = _estado.copyWith(enProgreso: true, error: null);
    try {
      final data = await _client.get(
        AppConstants.epOfflineCatalogo,
        queryParameters: cursor == null ? null : {'cursor': cursor},
      );
      final paquete = data is Map<String, dynamic> ? data : {'productos': data};
      await guardarPaquete(paquete, incremental: true);
      final ahora = DateTime.now();
      final nuevoCursor = paquete['cursor']?.toString() ?? cursor;
      if (nuevoCursor != null) {
        await _guardarMeta(clave: 'cursor_catalogo', valor: nuevoCursor);
      }
      _estado = _estado.copyWith(
        enProgreso: false,
        incompleto: false,
        cursorCatalogo: nuevoCursor,
        sello: ahora,
      );
      return _estado;
    } catch (error) {
      _estado = _estado.copyWith(
        enProgreso: false,
        incompleto: true,
        error: error.toString(),
      );
      rethrow;
    }
  }

  // [EXAMEN-2] C2.4: parsea clientes/promociones; incluirClientes=false no los toca.
  Future<void> guardarPaquete(
    Map<String, dynamic> paquete, {
    int? sucursalId,
    bool incremental = false,
    bool incluirClientes = true,
  }) async {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    await db.transaction<void>((txn) async {
      final repo = CatalogLocalRepository(txn, tenantId: _tenantId);
      for (final producto in _listaMapa(paquete['productos'])) {
        await repo.guardarProducto({...producto, 'tenant_id': _tenantId});
        for (final variante in _listaMapa(producto['variantes'])) {
          await repo.guardarVariante({...variante, 'tenant_id': _tenantId});
        }
      }
      for (final variante in _listaMapa(paquete['variantes'])) {
        await repo.guardarVariante({...variante, 'tenant_id': _tenantId});
      }
      for (final stock in _listaMapa(paquete['stock'])) {
        await repo.guardarStock({...stock, 'tenant_id': _tenantId});
      }
      for (final sucursal in _listaMapa(paquete['sucursales'])) {
        await repo.guardarSucursal({...sucursal, 'tenant_id': _tenantId});
      }
      for (final categoria in _listaMapa(paquete['categorias'])) {
        await repo.guardarCategoria({...categoria, 'tenant_id': _tenantId});
      }
      for (final talla in _listaMapa(paquete['tallas'])) {
        await repo.guardarTalla({...talla, 'tenant_id': _tenantId});
      }
      for (final color in _listaMapa(paquete['colores'])) {
        await repo.guardarColor({...color, 'tenant_id': _tenantId});
      }
      if (incluirClientes) {
        final repoClientes = LocalCustomerRepository(txn, tenantId: _tenantId);
        await repoClientes.guardarClientes(
          _listaMapa(paquete['clientes'])
              .map((c) => {...c, 'tenant_id': _tenantId}),
        );
      }
      if (paquete.containsKey('promociones')) {
        await _guardarMeta(
          clave: 'promociones_offline',
          valor: jsonEncode(paquete['promociones']),
        );
      }
    });
  }

  // [EXAMEN-2] C2.4: espacio usado real del SQLite (bytes).
  Future<int> espacioUsado() => _database.espacioUsado();

  // [EXAMEN-2] C2.4: limpia solo el catálogo del tenant (productos/variantes/stock).
  Future<void> limpiarCatalogo() async {
    final db = _database.database;
    if (db == null) return;
    await db.transaction<void>((txn) async {
      for (final tabla in <String>[
        'productos',
        'variantes',
        'stock',
        'sucursales',
        'categorias',
        'tallas',
        'colores',
        'clientes',
      ]) {
        await txn.delete(tabla, where: 'tenant_id = ?', whereArgs: <Object?>[_tenantId]);
      }
    });
    _estado = const OfflineDownloadStatus();
  }

  Future<List<ProductModel>> catalogoLocal({
    int? categoriaId,
    String? busqueda,
  }) async {
    final filas = await _repo.listarProductos(
      categoriaId: categoriaId,
      busqueda: busqueda,
    );
    return filas.map(_productoDesdeMapa).toList(growable: false);
  }

  Future<ProductModel?> detalleLocal(int id) async {
    final producto = await _repo.obtenerProducto(id);
    if (producto == null) return null;
    final variantes = await _repo.listarVariantesProducto(id);
    return _productoDesdeMapa({...producto, 'variantes': variantes});
  }

  Future<List<ProductModel>> buscarLocal(String texto) async {
    final productos = await _repo.listarProductos(busqueda: texto);
    final variantes = await _repo.buscarVariantesSku(texto);
    final ids = variantes
        .map((v) => (v['producto_id'] as num?)?.toInt() ?? 0)
        .toSet();
    for (final producto in productos) {
      ids.add((producto['id'] as num?)?.toInt() ?? 0);
    }
    final resultados = <ProductModel>[];
    for (final id in ids) {
      final producto = await detalleLocal(id);
      if (producto != null) resultados.add(producto);
    }
    return resultados;
  }

  Future<Map<int, int>> disponibilidadLocal({int? sucursalId}) async {
    final stock = await _repo.listarStock(sucursalId: sucursalId);
    return <int, int>{
      for (final fila in stock)
        ((fila['variante_id'] as num?)?.toInt() ?? 0):
            ((fila['cantidad'] as num?)?.toInt() ?? 0),
    };
  }

  Future<DateTime?> estadoSello() async {
    final db = _database.database;
    if (db == null) return null;
    final filas = await db.query(
      'meta',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>['sello_descarga', _tenantId],
      limit: 1,
    );
    return DateTime.tryParse(filas.firstOrNull?['valor']?.toString() ?? '');
  }

  Future<void> bajaLogica(int productoId) =>
      _repo.marcarProductoEliminado(productoId);

  List<Map<String, Object?>> _listaMapa(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  ProductModel _productoDesdeMapa(Map<String, Object?> map) {
    final datos = <String, Object?>{...map};
    final imagenes = datos['imagenes'];
    if (imagenes is String && imagenes.isNotEmpty) {
      try {
        final decoded = jsonDecode(imagenes);
        if (decoded is List) datos['imagenes'] = decoded;
      } catch (_) {}
    }
    final variantes = _listaMapa(map['variantes'])
        .map((v) {
          return VarianteProducto.fromJson({
            ...v,
            'stock_total': v['stock_total'] ?? v['cantidad'] ?? 0,
            'producto': {
              'id': map['id'],
              'nombre': map['nombre'],
              'imagenes': map['imagenes'],
            },
          });
        })
        .toList(growable: false);
    return ProductModel.fromJson({
      ...datos,
      'imagenes': datos['imagenes'] is List
          ? datos['imagenes']
          : const <String>[],
      'variantes': variantes,
    });
  }

  Future<void> _guardarMeta({
    required String clave,
    required String valor,
  }) async {
    final db = _database.database;
    if (db == null) return;
    final existentes = await db.query(
      'meta',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>[clave, _tenantId],
      limit: 1,
    );
    if (existentes.isEmpty) {
      await db.insert('meta', <String, Object?>{
        'clave': clave,
        'tenant_id': _tenantId,
        'valor': valor,
        'version_esquema': 2,
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      await db.update(
        'meta',
        <String, Object?>{
          'valor': valor,
          'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'clave = ? AND tenant_id = ?',
        whereArgs: <Object?>[clave, _tenantId],
      );
    }
  }
}
