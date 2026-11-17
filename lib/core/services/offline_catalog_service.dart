import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/catalog_local_repository.dart';
import '../database/repositories/local_config_repository.dart';
import '../database/repositories/local_customer_repository.dart';
import '../database/repositories/local_permissions_repository.dart';
import '../models/offline_config_model.dart';
import '../models/phase2_models.dart';
import '../models/product_model.dart';
import 'device_service.dart';
import 'storage_quota_service.dart';

/// [EXAMEN-2] Descarga y consulta del paquete offline (CU05).
class OfflineCatalogService {
  /// [EXAMEN-2] Mejora offline: tope de imágenes precacheadas por descarga
  /// (evita llenar la caché de disco con catálogos gigantes).
  static const int maxImagenesPrecache = 400;

  OfflineCatalogService({
    required LocalDatabaseService database,
    required int tenantId,
    required OfflineApiClient client,
    CatalogLocalRepository? repository,
    // [EXAMEN-2] CU05/RNF-14: cuota de espacio local para las descargas.
    StorageQuotaService? quotaService,
    // [EXAMEN-2] Mejora offline: descargador de imágenes inyectable (para
    // tests); por defecto usa `DefaultCacheManager` — la MISMA caché de disco
    // que `CachedNetworkImage` — de modo que la imagen precacheada se
    // encuentra offline sin cambios en la UI.
    Future<File> Function(String url)? precachearImagen,
  }) : _database = database,
       _tenantId = tenantId,
       _client = client,
       _repository = repository,
       _quotaService = quotaService,
       _precacheImagen = precachearImagen;

  final LocalDatabaseService _database;
  final int _tenantId;
  final OfflineApiClient _client;
  CatalogLocalRepository? _repository;
  StorageQuotaService? _quotaService;
  // [EXAMEN-2] Mejora offline: descargador de imágenes inyectable.
  final Future<File> Function(String url)? _precacheImagen;
  // [EXAMEN-2] B1.1: repositorios de configuración y permisos, para persistir
  // lo que el backend ya envía en el paquete (`impuestos`, `stripe`,
  // `permisos` y `configuracion_offline`).
  LocalConfigRepository? _configRepository;
  LocalPermissionsRepository? _permissionsRepository;
  // [EXAMEN-2] B1.1.e: temporizador de la descarga automática.
  Timer? _timerDescargaAuto;

  /// [EXAMEN-2] B1.1: inyecta los repositorios de configuración y permisos.
  void configurarRepositorios({
    LocalConfigRepository? config,
    LocalPermissionsRepository? permissions,
  }) {
    if (config != null) _configRepository = config;
    if (permissions != null) _permissionsRepository = permissions;
  }

  // [EXAMEN-2] CU05/RNF-14: alternativo cuando la cuota se construye después
  // de este servicio (dependencias de main.dart).
  void configurarQuota(StorageQuotaService servicio) {
    _quotaService = servicio;
  }

  OfflineDownloadStatus _estado = const OfflineDownloadStatus();
  OfflineDownloadStatus get estadoDescarga => _estado;
  DateTime? get selloDescarga => _estado.sello;
  Object? get errorBaseDatos => _database.ultimoErrorApertura;

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
    final paquete = data is Map<String, dynamic> ? data : {'stock': data};
    await guardarPaquete(paquete, sucursalId: sucursalId, incremental: true);
  }

  // [EXAMEN-2] C2.4: GET /offline/clientes (PII opcional; respetar incluirClientes).
  Future<void> descargarClientes() async {
    final data = await _client.get(AppConstants.epOfflineClientes);
    final lista = data is List
        ? data
        : data is Map
        ? data['clientes']
        : null;
    if (lista is! List) return;
    final db = _database.database;
    if (db == null) return;
    final repo = LocalCustomerRepository(db, tenantId: _tenantId);
    await repo.guardarClientes(
      lista.whereType<Map>().map(
        (e) => Map<String, Object?>.from(e)..['tenant_id'] = _tenantId,
      ),
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

  /// [EXAMEN-2] B1.1.e: **descarga automática** del catálogo.
  ///
  /// El tenant define `descarga_automatica` y `hora_descarga`
  /// (`ConfiguracionOfflineResponse`). Se programa un temporizador que
  /// dispara la descarga a esa hora y se rearma para el día siguiente.
  ///
  /// Antes el flag se guardaba pero **nunca se leía**: la descarga automática
  /// no existía.
  void programarDescargaAutomatica(OfflineConfigModel config) {
    _timerDescargaAuto?.cancel();
    _timerDescargaAuto = null;
    if (!config.descargaAutomatica) return;
    final hora = _parseHora(config.horaDescarga);
    if (hora == null) return;
    final ahora = DateTime.now();
    var siguiente = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      hora.hour,
      hora.minute,
    );
    if (!siguiente.isAfter(ahora)) {
      siguiente = siguiente.add(const Duration(days: 1));
    }
    _timerDescargaAuto = Timer(
      siguiente.difference(ahora),
      () async {
        try {
          await descargarPaquete();
        } catch (_) {
          // Sin red o con error: se reintenta en la siguiente ventana.
        }
        // Rearma para el día siguiente.
        programarDescargaAutomatica(config);
      },
    );
  }

  /// Cancela la descarga automática programada.
  void cancelarDescargaAutomatica() {
    _timerDescargaAuto?.cancel();
    _timerDescargaAuto = null;
  }

  /// [EXAMEN-2] B1.1.e: interpreta la hora de descarga del tenant ("HH:MM").
  TimeOfDay? _parseHora(String? valor) {
    if (valor == null || valor.isEmpty) return null;
    final partes = valor.split(':');
    if (partes.length < 2) return null;
    final h = int.tryParse(partes[0].trim());
    final m = int.tryParse(partes[1].trim());
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  /// [EXAMEN-2] B2.1: actualiza **de forma incremental** los datos locales.
  ///
  /// Usa los endpoints que ya estaban implementados pero **nadie invocaba**
  /// (`/offline/catalogo?desde_version=`, `/offline/stock`, `/offline/clientes`,
  /// `/offline/promociones`): son la vía rápida para refrescar sin volver a
  /// bajar el paquete completo.
  Future<Map<String, int>> actualizarDatos({int? sucursalId}) async {
    final resultado = <String, int>{};
    try {
      final cursor = await _leerCursor();
      await descargarIncremental(cursor: cursor);
      resultado['catalogo'] = 1;
    } catch (_) {
      resultado['catalogo'] = 0;
    }
    try {
      await descargarStock(sucursalId: sucursalId);
      resultado['stock'] = 1;
    } catch (_) {
      resultado['stock'] = 0;
    }
    try {
      await descargarClientes();
      resultado['clientes'] = 1;
    } catch (_) {
      resultado['clientes'] = 0;
    }
    try {
      await descargarPromociones();
      resultado['promociones'] = 1;
    } catch (_) {
      resultado['promociones'] = 0;
    }
    return resultado;
  }

  /// [EXAMEN-2] B1.1.l: compara la versión del paquete en el servidor con el
  /// cursor local. Si no cambió, la descarga completa se evita.
  ///
  /// Ante cualquier error se devuelve `true` (se descarga): es el
  /// comportamiento seguro.
  Future<bool> hayVersionNueva() async {    try {
      final data = await consultarVersion();
      final version =
          data['version']?.toString() ?? data['hash_paquete']?.toString();
      if (version == null || version.isEmpty) return true;
      final local = await _leerCursor();
      if (local == null || local.isEmpty) return true;
      return local != version;
    } catch (_) {
      return true;
    }
  }

  /// [EXAMEN-2] B1.1.l: cursor de catálogo guardado localmente.
  Future<String?> _leerCursor() async {
    final db = _database.database;
    if (db == null) return null;
    final filas = await db.query(
      'meta',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>['cursor_catalogo', _tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return filas.first['valor']?.toString();
  }

  Future<OfflineDownloadStatus> descargarPaquete({
    int? sucursalId,
    bool incluirClientes = true,
    // [EXAMEN-2] B1.1.i: descarga selectiva (sólo los N productos más
    // vendidos) cuando el paquete completo no cabe en el espacio local.
    int? limiteProductos,
    // [EXAMEN-2] B1.1.l: fuerza la descarga aunque la versión no haya cambiado.
    bool forzar = false,
  }) async {
    _estado = _estado.copyWith(
      enProgreso: true,
      incompleto: false,
      error: null,
    );
    try {
      // [EXAMEN-2] B1.1.l: si el catálogo no ha cambiado, no se vuelve a
      // bajar el paquete completo.
      if (!forzar && !await hayVersionNueva()) {
        final ahora = DateTime.now();
        _estado = _estado.copyWith(
          enProgreso: false,
          incompleto: false,
          sello: ahora,
        );
        return _estado;
      }
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
        limiteProductos: limiteProductos,
      );
      // [EXAMEN-2] CU05: el paquete no trae sucursales; se bajan aparte
      // (best-effort) para resolver la sesión POS sin conexión.
      await descargarSucursales();
      // [EXAMEN-2] Mejora offline: precachea las imágenes del catálogo para
      // que el modo avión muestre las fotos (RN-008: el paquete solo trae
      // datos; las imágenes se cachean a disco aparte, con límite).
      await precacheImagenes(maxImagenes: maxImagenesPrecache);
      final ahora = DateTime.now();
      await _guardarMeta(
        clave: 'ultima_descarga_completa',
        valor: ahora.toUtc().toIso8601String(),
      );
      await _guardarMeta(
        clave: 'sello_descarga',
        valor: ahora.toUtc().toIso8601String(),
      );
      // [EXAMEN-2] B1.1.l: se guarda la versión del paquete como cursor local
      // para poder saltarse la descarga cuando el catálogo no ha cambiado.
      final versionPaquete =
          data['cursor']?.toString() ??
          data['version']?.toString() ??
          data['hash_paquete']?.toString();
      if (versionPaquete != null && versionPaquete.isNotEmpty) {
        await _guardarMeta(clave: 'cursor_catalogo', valor: versionPaquete);
      }
      _estado = OfflineDownloadStatus(
        ultimaDescargaCompleta: ahora,
        cursorCatalogo: versionPaquete,
        sello: ahora,
      );
      await registrarDescarga(
        sello: ahora,
        cantidadProductos:
            (data['productos'] as List?)?.length ??
            (data['catalogo'] as List?)?.length,
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

  /// [EXAMEN-2] Mejora offline: precachea en disco las imágenes del catálogo.
  ///
  /// El paquete CU05 trae **datos** (precios, variantes, stock), no los bytes
  /// de las imágenes. Sin este paso, en modo avión sólo se veían las fotos
  /// que ya se habían mostrado con conexión (caché de `CachedNetworkImage`).
  ///
  /// Usa el **mismo** `DefaultCacheManager` que `CachedNetworkImage`, de modo
  /// que la imagen precacheada se encuentra offline sin cambios en la UI.
  /// Es *best-effort*: un fallo por imagen (404, DNS, cuota) no marca la
  /// descarga como incompleta. `downloadFile` respeta la frescura de la caché
  /// (por defecto 30 días), así que re-descargar no repite bytes ya cacheados.
  ///
  /// Devuelve la cantidad de imágenes precacheadas con éxito.
  Future<int> precacheImagenes({
    int maxImagenes = 400,
    Duration timeoutPorImagen = const Duration(seconds: 15),
  }) async {
    final db = _database.database;
    if (db == null) return 0;
    final filas = await db.query(
      'productos',
      columns: <String>['id', 'imagenes'],
      where: 'tenant_id = ?',
      whereArgs: <Object?>[_tenantId],
    );
    final urls = <String>[];
    for (final fila in filas) {
      final raw = fila['imagenes']?.toString() ?? '';
      if (raw.isEmpty) continue;
      urls.addAll(_extraerUrls(raw));
    }
    // [EXAMEN-2] El gestor por defecto se construye **solo** si no se inyectó
    // descargador (en tests se evita: `DefaultCacheManager` requiere
    // `path_provider`, que no existe en pruebas unitarias puras).
    final descargar =
        _precacheImagen ??
        (String url) async =>
            (await DefaultCacheManager().downloadFile(url).timeout(
                  timeoutPorImagen,
                )).file;
    var precacheadas = 0;
    for (final url in urls.take(maxImagenes)) {
      try {
        await descargar(url).timeout(timeoutPorImagen);
        precacheadas++;
      } catch (_) {
        // Best-effort: la imagen no disponible no rompe la descarga.
      }
    }
    return precacheadas;
  }

  /// Extrae URLs `http(s)://` de la columna `productos.imagenes` (que el
  /// repositorio guarda como JSON string, p. ej. `["https://..."]`).
  List<String> _extraerUrls(String raw) {
    final urls = <String>[];
    try {
      final decodificado = jsonDecode(raw);
      if (decodificado is List) {
        for (final item in decodificado) {
          final url = item?.toString() ?? '';
          if (url.startsWith('http://') || url.startsWith('https://')) {
            urls.add(url);
          }
        }
        return urls;
      }
    } catch (_) {
      // No era JSON válido: se cae al parseo simple por comas.
    }
    // Respaldo (mismo formato que `ProductModel.parseImagenes`):
    for (final parte in raw
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .split(',')) {
      final url = parte.trim();
      if (url.startsWith('http://') || url.startsWith('https://')) {
        urls.add(url);
      }
    }
    return urls;
  }

  /// [EXAMEN-2] B1.1.l: descarga **incremental** del catálogo.
  ///
  /// El backend expone `GET /offline/catalogo?desde_version=...`
  /// (`operaciones_offline/router.py` → `obtener_catalogo_incremental`). El
  /// móvil enviaba `cursor`, un parámetro que el router **ignora**, por lo que
  /// siempre descargaba el catálogo completo.
  Future<OfflineDownloadStatus> descargarIncremental({String? cursor}) async {
    _estado = _estado.copyWith(enProgreso: true, error: null);
    try {
      final data = await _client.get(
        AppConstants.epOfflineCatalogo,
        queryParameters: cursor == null ? null : {'desde_version': cursor},
      );
      final paquete = data is Map<String, dynamic> ? data : {'productos': data};
      await guardarPaquete(paquete, incremental: true);
      // [EXAMEN-2] Mejora offline: precachea las imágenes de los productos
      // nuevos/modificados (best-effort, límite compartido).
      await precacheImagenes(maxImagenes: maxImagenesPrecache);
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
    // [EXAMEN-2] B1.1.i: descarga selectiva (sólo los N productos más
    // vendidos) cuando el paquete completo no cabe en el espacio local.
    int? limiteProductos,
  }) async {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    // [EXAMEN-2] CU05/RNF-14 (§19): la cuota local limita la descarga; si no
    // hay espacio se avisa y no se escribe nada (idempotente).
    final quota = _quotaService;
    if (quota != null) {
      final estimado = jsonEncode(paquete).length;
      final disponible = await quota.espacioDisponible();
      if (!await quota.puedeDescargar(estimado)) {
        // [EXAMEN-2] B1.1.i: en vez de fallar sin más, se informa de cuántos
        // productos caben para ofrecer la descarga selectiva.
        final totalProductos =
            _listaMapa(paquete['productos'] ?? paquete['catalogo']).length;
        final maxProductos = await quota.maxProductosPorEspacio(
          totalProductos: totalProductos,
          bytesEstimadosPaquete: estimado,
        );
        if (limiteProductos == null) {
          _estado = _estado.copyWith(
            enProgreso: false,
            incompleto: true,
            error:
                'Espacio local insuficiente (RNF-14): se necesitan ~$estimado '
                'bytes y hay $disponible disponibles.',
          );
          throw CuotaInsuficienteException(
            estimadoBytes: estimado,
            disponibleBytes: disponible,
            maxProductos: maxProductos,
          );
        }
      }
    }
    // [EXAMEN-2] CU05: sucursal objetivo del paquete (parametro o del payload
    // del backend). Se persiste en meta para que POS la resuelva offline.
    final idSucursalObjetivo =
        sucursalId ?? ((paquete['sucursal_id'] as num?)?.toInt());
    await db.transaction<void>((txn) async {
      // Una descarga completa reemplaza el snapshot anterior del tenant. Si
      // cualquier fila del payload es inválida, SQLite revierte todos los
      // borrados y escrituras: nunca queda un paquete parcial.
      if (!incremental) {
        for (final tabla in <String>[
          'stock',
          'variantes',
          'productos',
          'categorias',
          'tallas',
          'colores',
        ]) {
          await txn.delete(
            tabla,
            where: 'tenant_id = ?',
            whereArgs: <Object?>[_tenantId],
          );
        }
        if (incluirClientes) {
          await txn.delete(
            'clientes',
            where: 'tenant_id = ?',
            whereArgs: <Object?>[_tenantId],
          );
        }
        // Una descarga completa reemplaza también las promociones del
        // snapshot anterior; de lo contrario podría quedar metadata de una
        // generación anterior mezclada con el catálogo nuevo.
        await txn.delete(
          'meta',
          where: 'clave = ? AND tenant_id = ?',
          whereArgs: <Object?>['promociones_offline', _tenantId],
        );
      }
      if (idSucursalObjetivo != null && idSucursalObjetivo > 0) {
        await _guardarMeta(
          executor: txn,
          clave: 'paquete_sucursal_id',
          valor: '$idSucursalObjetivo',
        );
      }
      final repo = CatalogLocalRepository(txn, tenantId: _tenantId);
      // [EXAMEN-2] Normalización del paquete del backend Examen 2: el payload
      // usa `catalogo` (productos), `datos_maestros` (categorias/tallas/colores)
      // y `clientes_frecuentes`; el stock usa `variante_producto_id`.
      final maestros = paquete['datos_maestros'] is Map
          ? Map<String, Object?>.from(paquete['datos_maestros'] as Map)
          : const <String, Object?>{};
      var productos = _listaMapa(paquete['productos'] ?? paquete['catalogo']);
      // [EXAMEN-2] CU05/RNF-14: priorización por ventas/stock en la
      // descarga completa (los incrementales respetan el orden del cursor).
      if (!incremental && quota != null && productos.length > 1) {
        productos = await quota.priorizarDescarga(productos);
      }
      // [EXAMEN-2] B1.1.i: la descarga selectiva **trunca** de verdad (antes
      // sólo ordenaba, por lo que no liberaba espacio).
      if (!incremental &&
          limiteProductos != null &&
          productos.length > limiteProductos) {
        productos = productos.take(limiteProductos).toList();
      }
      for (final producto in productos) {
        await repo.guardarProducto({...producto, 'tenant_id': _tenantId});
        for (final variante in _listaMapa(producto['variantes'])) {
          await repo.guardarVariante({...variante, 'tenant_id': _tenantId});
        }
      }
      for (final variante in _listaMapa(paquete['variantes'])) {
        await repo.guardarVariante({...variante, 'tenant_id': _tenantId});
      }
      for (final stock in _listaMapa(paquete['stock'])) {
        // El backend expone variante_producto_id y cantidad_disponible; la
        // tabla local usa variante_id y `cantidad` (disponible para pos POS).
        await repo.guardarStock(<String, Object?>{
          'variante_id': stock['variante_id'] ?? stock['variante_producto_id'],
          'sucursal_id': stock['sucursal_id'],
          'cantidad': stock['cantidad_disponible'] ?? stock['cantidad'] ?? 0,
          'cantidad_reservada': stock['cantidad_reservada'],
          'stock_minimo': stock['stock_minimo'],
          'tenant_id': _tenantId,
        });
      }
      for (final sucursal in _listaMapa(paquete['sucursales'])) {
        await repo.guardarSucursal({...sucursal, 'tenant_id': _tenantId});
      }
      final categorias = <Map<String, Object?>>[
        ..._listaMapa(paquete['categorias']),
        ..._listaMapa(maestros['categorias']),
      ];
      for (final categoria in categorias) {
        await repo.guardarCategoria({...categoria, 'tenant_id': _tenantId});
      }
      final tallas = <Map<String, Object?>>[
        ..._listaMapa(paquete['tallas']),
        // El backend envía tallas con `valor`; la tabla local usa `nombre`.
        ..._listaMapa(maestros['tallas']).map(
          (t) => <String, Object?>{
            ...t,
            'nombre': t['nombre']?.toString() ?? t['valor']?.toString() ?? '',
          },
        ),
      ];
      for (final talla in tallas) {
        await repo.guardarTalla({...talla, 'tenant_id': _tenantId});
      }
      final colores = <Map<String, Object?>>[
        ..._listaMapa(paquete['colores']),
        // El backend envía colores con `codigo_hex`; la tabla local usa `codigo`.
        ..._listaMapa(maestros['colores']).map(
          (c) => <String, Object?>{
            ...c,
            'codigo': c['codigo']?.toString() ?? c['codigo_hex']?.toString(),
          },
        ),
      ];
      for (final color in colores) {
        await repo.guardarColor({...color, 'tenant_id': _tenantId});
      }
      if (incluirClientes) {
        final repoClientes = LocalCustomerRepository(txn, tenantId: _tenantId);
        final clientesBackend = _listaMapa(paquete['clientes']);
        // El backend Examen 2 trae `clientes_frecuentes` sin `nombre`
        // (requerido NOT NULL localmente); se sintetiza con nit_ci o el id.
        final clientesNormales = clientesBackend.isNotEmpty
            ? clientesBackend
            : _listaMapa(
                paquete['clientes_frecuentes'],
              ).map(_clienteConNombre).toList(growable: false);
        // [EXAMEN-2] B1.1.k: se respeta `max_clientes` del tenant; antes se
        // guardaban **todas** las filas recibidas sin tope.
        final maxClientes = await _maxClientes(paquete);
        final limited = maxClientes > 0 && clientesNormales.length > maxClientes
            ? clientesNormales.take(maxClientes).toList(growable: false)
            : clientesNormales;
        await repoClientes.guardarClientes(
          limited.map((c) => {...c, 'tenant_id': _tenantId}),
        );
      }
      if (paquete.containsKey('promociones')) {
        await _guardarMeta(
          executor: txn,
          clave: 'promociones_offline',
          valor: jsonEncode(paquete['promociones']),
        );
      }
    });
    // [EXAMEN-2] B1.1.a–d: se consumen los bloques de configuración que el
    // backend **ya envía** en el paquete y que el móvil ignoraba:
    // `impuestos`, `stripe` (clave pública), `permisos` y
    // `configuracion_offline`.
    await _persistirConfiguracionPaquete(paquete);
  }

  /// [EXAMEN-2] B1.1.k: tope de clientes frecuentes según la configuración
  /// del tenant (`max_clientes`, por defecto 100).
  Future<int> _maxClientes(Map<String, dynamic> paquete) async {
    final configJson = paquete['configuracion_offline'];
    if (configJson is Map) {
      final valor = (configJson['max_clientes'] as num?)?.toInt();
      if (valor != null && valor > 0) return valor;
    }
    try {
      final config = await _configRepository?.leer(_tenantId);
      final valor = config?.maxClientes ?? 0;
      return valor > 0 ? valor : 100;
    } catch (_) {
      return 100;
    }
  }

  /// [EXAMEN-2] B1.1: persiste impuestos, clave pública de Stripe, permisos
  /// y la configuración offline del tenant que llegan en el paquete.
  Future<void> _persistirConfiguracionPaquete(
    Map<String, dynamic> paquete,
  ) async {
    final configRepo = _configRepository;
    final permisosRepo = _permissionsRepository;
    if (configRepo == null && permisosRepo == null) return;

    // `configuracion_offline`: es la configuración efectiva del tenant.
    final configJson = paquete['configuracion_offline'];
    final configMap = configJson is Map
        ? Map<String, dynamic>.from(configJson)
        : <String, dynamic>{};

    // `impuestos`: { moneda, impuestos: [], tasa_total }.
    final impuestosJson = paquete['impuestos'];
    final impuestosMap = impuestosJson is Map
        ? Map<String, dynamic>.from(impuestosJson)
        : <String, dynamic>{};
    final tasaImpuestos =
        (impuestosMap['tasa_total'] as num?)?.toDouble() ??
        (impuestosMap['tasa'] as num?)?.toDouble() ??
        0.0;

    // `stripe`: sólo la clave **pública** (RNF-15: nunca la secreta).
    final stripeJson = paquete['stripe'];
    final stripeMap = stripeJson is Map
        ? Map<String, dynamic>.from(stripeJson)
        : <String, dynamic>{};
    final clavePublica = stripeMap['stripe_publishable_key']?.toString();

    if (configRepo != null) {
      final previa = await configRepo.leer(_tenantId);
      final modelo = OfflineConfigModel(
        tenantId: _tenantId,
        descargaAutomatica:
            configMap['descarga_automatica'] as bool? ??
            previa?.descargaAutomatica ??
            true,
        horaDescarga:
            configMap['hora_descarga']?.toString() ??
            previa?.horaDescarga,
        incluirClientes:
            configMap['incluir_clientes'] as bool? ??
            previa?.incluirClientes ??
            true,
        maxClientes:
            (configMap['max_clientes'] as num?)?.toInt() ??
            previa?.maxClientes ??
            100,
        habilitarCarritoOffline:
            configMap['habilitar_carrito_offline'] as bool? ??
            previa?.habilitarCarritoOffline ??
            true,
        maxHorasSesionOffline:
            (configMap['max_horas_sesion_offline'] as num?)?.toInt() ??
            previa?.maxHorasSesionOffline ??
            12,
        maxDiasOrdenPendiente:
            (configMap['max_dias_orden_pendiente'] as num?)?.toInt() ??
            previa?.maxDiasOrdenPendiente ??
            1,
        moneda:
            impuestosMap['moneda']?.toString() ??
            stripeMap['moneda']?.toString() ??
            previa?.moneda ??
            'BOB',
        clavePublicaStripe:
            clavePublica ?? previa?.clavePublicaStripe,
        tasaImpuestos: tasaImpuestos,
      );
      await configRepo.guardar(modelo);
    }

    // `permisos`: { roles: [...], permisos: [...] }.
    if (permisosRepo != null) {
      final permisosJson = paquete['permisos'];
      if (permisosJson is Map) {
        final mapa = Map<String, dynamic>.from(permisosJson);
        final roles = (mapa['roles'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        final permisos = (mapa['permisos'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        final usuarioId =
            (paquete['usuario_id'] as num?)?.toInt() ??
            (mapa['usuario_id'] as num?)?.toInt() ??
            0;
        await permisosRepo.guardar(
          tenantId: _tenantId,
          usuarioId: usuarioId,
          roles: roles,
          permisos: permisos,
        );
      }
    }
  }

  /// [EXAMEN-2] Los clientes frecuentes del backend no traen `nombre`
  /// (solo nit_ci/telefono/correo/direccion); la tabla local lo exige.
  Map<String, Object?> _clienteConNombre(Map<String, Object?> cliente) {
    final nombre = cliente['nombre']?.toString();
    if (nombre != null && nombre.isNotEmpty) return cliente;
    final nit = cliente['nit_ci']?.toString();
    final id = cliente['id'];
    return {
      ...cliente,
      'nombre': (nit != null && nit.isNotEmpty) ? nit : 'Cliente #$id',
    };
  }

  // [EXAMEN-2] CU05: descarga las sucursales del tenant para operar offline
  // (el paquete no las incluye). Best-effort: si falla, POS usa la meta
  // `paquete_sucursal_id`.
  Future<void> descargarSucursales() async {
    final db = _database.database;
    if (db == null) return;
    try {
      final data = await _client.get(AppConstants.epSucursales);
      final lista = data is List
          ? data
          : data is Map
          ? data['sucursales']
          : null;
      if (lista is! List) return;
      await db.transaction<void>((txn) async {
        final repo = CatalogLocalRepository(txn, tenantId: _tenantId);
        for (final fila in lista.whereType<Map>()) {
          await repo.guardarSucursal({
            ...Map<String, Object?>.from(fila),
            'tenant_id': _tenantId,
            // [FIX] La tabla local guarda el horario en la columna `horario`;
            // sin esta línea se descartaba `horario_atencion` del backend.
            'horario': fila['horario_atencion'] ?? fila['horario'],
          });
        }
      });
    } catch (_) {
      // Sin sucursales locales: la resolución cae a la meta del paquete.
    }
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
        await txn.delete(
          tabla,
          where: 'tenant_id = ?',
          whereArgs: <Object?>[_tenantId],
        );
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
    final variantes = await _repo.listarVariantes();
    final stock = await _repo.listarStock();
    return filas
        .map(
          (producto) => _productoConInventario(
            producto,
            variantes: variantes,
            stock: stock,
          ),
        )
        .toList(growable: false);
  }

  Future<ProductModel?> detalleLocal(int id) async {
    final producto = await _repo.obtenerProducto(id);
    if (producto == null) return null;
    final variantes = await _repo.listarVariantesProducto(id);
    final stock = await _repo.listarStock();
    return _productoConInventario(producto, variantes: variantes, stock: stock);
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

  ProductModel _productoConInventario(
    Map<String, Object?> producto, {
    required List<Map<String, Object?>> variantes,
    required List<Map<String, Object?>> stock,
  }) {
    final idProducto = (producto['id'] as num?)?.toInt() ?? 0;
    final variantesProducto = variantes
        .where(
          (variante) =>
              (variante['producto_id'] as num?)?.toInt() == idProducto,
        )
        .map((variante) {
          final idVariante = (variante['id'] as num?)?.toInt() ?? 0;
          final stockVariante = stock.where(
            (fila) => (fila['variante_id'] as num?)?.toInt() == idVariante,
          );
          final porSucursal = <int, int>{};
          var total = 0;
          for (final fila in stockVariante) {
            final sucursal = (fila['sucursal_id'] as num?)?.toInt() ?? 0;
            final cantidad = (fila['cantidad'] as num?)?.toInt() ?? 0;
            porSucursal[sucursal] = cantidad;
            total += cantidad;
          }
          return <String, Object?>{
            ...variante,
            'stock_total': total,
            'stock_por_sucursal': porSucursal,
          };
        })
        .toList(growable: false);
    return _productoDesdeMapa({...producto, 'variantes': variantesProducto});
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
        .map(
          (v) => <String, Object?>{
            ...v,
            'stock_total': v['stock_total'] ?? v['cantidad'] ?? 0,
            'producto': <String, Object?>{
              'id': map['id'],
              'nombre': map['nombre'],
              'imagenes': map['imagenes'],
            },
          },
        )
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
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? _database.database;
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
