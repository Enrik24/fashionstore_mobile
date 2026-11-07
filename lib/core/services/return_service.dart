import 'package:dio/dio.dart';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/local_return_repository.dart';
import '../models/api_response.dart';
import '../models/return_request_model.dart';
import 'api_service.dart';
import 'local_audit_service.dart';
import 'local_crypto_service.dart';
import 'offline_queue_service.dart';

/// Item para crear una solicitud (`ItemSolicitudDevolucionCreate` del backend).
class ReturnItemCreate {
  final int detalleOrdenId;
  final int cantidad;
  final int? varianteCambioId;

  ReturnItemCreate({
    required this.detalleOrdenId,
    this.cantidad = 1,
    this.varianteCambioId,
  });

  Map<String, dynamic> toJson() {
    return {
      'detalle_orden_id': detalleOrdenId,
      'cantidad': cantidad,
      if (varianteCambioId != null) 'variante_cambio_id': varianteCambioId,
    };
  }
}

/// Servicio de devoluciones y cambios del cliente (CU28).
/// Sigue el patrón de [CartService]: HTTP delgado con `dio` vía [ApiService].
class ReturnService {
  ReturnService({
    ApiService? apiService,
    // [EXAMEN-2] Fase 3 (CU13/CU18): base local y cola para crear sin red.
    LocalDatabaseService? database,
    int? tenantId,
    OfflineQueueService? queue,
    LocalAuditService? audit,
  }) : _apiService = apiService,
       _database = database,
       _tenantId = tenantId,
       _queue = queue,
       _audit = audit;

  final ApiService? _apiService;
  final LocalDatabaseService? _database;
  final int? _tenantId;
  final OfflineQueueService? _queue;
  final LocalAuditService? _audit;

  /// `POST /devoluciones/` — 201.
  Future<ReturnRequestModel> crearSolicitud({
    required int ordenId,
    int? sucursalId,
    required String tipo,
    required String motivo,
    String? motivoDetalle,
    required List<ReturnItemCreate> items,
  }) async {
    final api = _apiService;
    if (api == null) throw const FormatException('Servicio no configurado');
    try {
      final response = await api.dio.post(
        AppConstants.epDevoluciones,
        data: {
          'orden_id': ordenId,
          if (sucursalId != null) 'sucursal_id': sucursalId,
          'tipo': tipo.toUpperCase(),
          'motivo': motivo.toUpperCase(),
          if (motivoDetalle != null && motivoDetalle.trim().isNotEmpty)
            'motivo_detalle': motivoDetalle.trim(),
          'items': items.map((e) => e.toJson()).toList(),
        },
      );
      if (response.data is Map<String, dynamic>) {
        return ReturnRequestModel.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw api.handleError(e);
    }
  }

  /// `GET /devoluciones/mis-solicitudes`.
  Future<List<ReturnRequestModel>> getMisSolicitudes({
    int skip = 0,
    int limit = 50,
  }) async {
    final api = _apiService;
    if (api == null) return const [];
    try {
      final response = await api.dio.get(
        AppConstants.epMisDevoluciones,
        queryParameters: {'skip': skip, 'limit': limit},
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) => ReturnRequestModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw api.handleError(e);
    }
  }

  /// `GET /devoluciones/{id}` — la propia (el backend valida el propietario).
  Future<ReturnRequestModel> getSolicitud(int solicitudId) async {
    final api = _apiService;
    if (api == null) throw const FormatException('Servicio no configurado');
    try {
      final response = await api.dio.get(
        '${AppConstants.epDevoluciones}$solicitudId',
      );
      if (response.data is Map<String, dynamic>) {
        return ReturnRequestModel.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
      throw const FormatException('Respuesta inesperada del servidor');
    } catch (e) {
      throw api.handleError(e);
    }
  }

  // ====================================================================
  // [EXAMEN-2] Fase 3 (CU13/CU18) — servicios offline y endpoints N3.
  // ====================================================================

  LocalReturnRepository get _returnRepo {
    final db = _database?.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return LocalReturnRepository(db, tenantId: _tenantId ?? 0);
  }

  /// Calcula la diferencia y su clasificación (RN-025).
  ({double diferencia, String tipo, double pagado, double saldo})
  _clasificarDiferencia(double diferencia) {
    final tipo = TipoDiferencia.clasificar(diferencia);
    return (
      diferencia: diferencia,
      tipo: tipo,
      pagado: tipo == TipoDiferencia.cobro ? diferencia : 0.0,
      saldo: tipo == TipoDiferencia.saldoFavor ? -diferencia : 0.0,
    );
  }

  /// Valida el plazo RN-012 en local (sin red).
  bool validarPlazoLocal(DateTime fechaCambioLimite, {DateTime? ahora}) {
    return (ahora ?? DateTime.now()).isBefore(fechaCambioLimite) ||
        (ahora ?? DateTime.now()).isAtSameMomentAs(fechaCambioLimite);
  }

  Future<String> _uuid() async {
    return LocalCryptoService().generarUuid();
  }

  void _validarPlazoOffline(DateTime? fechaCambioLimite) {
    if (fechaCambioLimite != null && !validarPlazoLocal(fechaCambioLimite)) {
      throw const FormatException('Fuera de período permitido (RN-012)');
    }
  }

  Future<void> _auditar(String tipo, String uuid) async {
    if (_audit == null || _tenantId == null) return;
    await _audit.registrar(
      tenantId: _tenantId,
      tipo: tipo,
      mensaje: 'Operación $tipo $uuid',
    );
  }

  /// CU13: crea una devolución pura offline (sin prenda nueva ni salida).
  ///
  /// - Valida el plazo RN-012 si se provee `fechaCambioLimite`.
  /// - Calcula reembolso o saldo a favor según [saldoFavor].
  /// - Solo reingresa inventario (entrada de la prenda devuelta).
  /// - Encola `DEVOLUCION` por `POST /offline/sync` (vía [_queue]).
  Future<ReturnRequestModel> crearDevolucionOffline({
    required String numeroComprobanteOrigen,
    int? ordenOrigenId,
    int? sucursalId,
    int? clienteId,
    String motivo = MotivosDevolucion.tallaIncorrecta,
    String? motivoDetalle,
    required List<LineaDevolucion> items,
    bool saldoFavor = false,
    DateTime? fechaCambioLimite,
  }) async {
    if (items.isEmpty) {
      throw const FormatException('La devolución exige al menos una prenda');
    }
    if (numeroComprobanteOrigen.trim().isEmpty) {
      throw const FormatException('Número de comprobante inválido');
    }
    _validarPlazoOffline(fechaCambioLimite);
    final uuid = await _uuid();
    final total = items.fold<double>(
      0,
      (sum, item) => sum + item.precioUnitario * item.cantidad,
    );
    final tipoDif = saldoFavor ? TipoDiferencia.saldoFavor : TipoDiferencia.sinDiferencia;
    final montoReembolso = saldoFavor ? 0.0 : total;
    final saldo = saldoFavor ? total : 0.0;

    final cabecera = <String, Object?>{
      'orden_origen_id': ordenOrigenId,
      'numero_comprobante_origen': numeroComprobanteOrigen.trim(),
      'numero_solicitud': 'DEV-LOCAL-$uuid',
      'tipo': 'DEVOLUCION',
      'motivo': motivo,
      'motivo_detalle': motivoDetalle,
      'estado': 'PENDIENTE_SINCRONIZACION',
      'estado_sincronizacion': 'PENDIENTE_SINCRONIZACION',
      'es_offline': 1,
      'diferencia_precio': total,
      'tipo_diferencia': tipoDif,
      'monto_pagado_diferencia': 0.0,
      'saldo_favor': saldo,
      'monto_reembolso': montoReembolso,
      'fecha_limite_cambio': fechaCambioLimite?.toUtc().toIso8601String(),
      'cliente_id': clienteId,
    };
    final itemsMap = items
        .map((item) => <String, Object?>{
          'detalle_orden_id': item.detalleOrdenId,
          'variante_producto_id': item.varianteProductoId,
          'variante_cambio_id': null,
          'producto_id': item.productoId,
          'cantidad': item.cantidad,
          'precio_unitario': item.precioUnitario,
          'precio_variante_nueva': null,
          'diferencia': 0.0,
          'subtotal_diferencia': 0.0,
          'estado_item': 'DEVUELTA',
          'producto_nombre': item.productoNombre,
        })
        .toList();
    // Solo entrada de la prenda devuelta; sin prenda nueva ni salida (CU13).
    final movimientos = items
        .map(
          (item) => (
            varianteId: item.varianteProductoId,
            delta: item.cantidad,
            deltaReserva: 0,
          ),
        )
        .toList();
    await _returnRepo.registrar(
      uuid: uuid,
      cabecera: cabecera,
      items: itemsMap,
      movimientosStock: movimientos,
      sucursalId: sucursalId ?? 0,
    );
    await _queue?.encolar(
      uuidOperacion: uuid,
      tipoOperacion: 'DEVOLUCION',
      sucursalId: sucursalId,
      payload: <String, Object?>{...cabecera, 'uuid_offline': uuid},
    );
    await _auditar('DEVOLUCION', uuid);
    return (await getSolicitudDesdeLocal(uuid))!;
  }

  /// CU18: crea una reposición offline (mismo producto obligatorio).
  ///
  /// - Solo dentro del plazo RN-012.
  /// - Exige `varianteCambioId` (prenda nueva) del **mismo producto**.
  /// - Verifica stock local y reserva provisionalmente la prenda nueva.
  /// - En una sola transacción: entrada de la devuelta + salida de la nueva
  ///   (RN-025) y diferencia clasificada COBRO/SALDO_FAVOR/SIN_DIFERENCIA.
  Future<ReturnRequestModel> crearReposicionOffline({
    required String numeroComprobanteOrigen,
    int? ordenOrigenId,
    int? sucursalId,
    int? clienteId,
    String motivo = MotivosDevolucion.tallaIncorrecta,
    String? motivoDetalle,
    required List<LineaDevolucion> items,
    DateTime? fechaCambioLimite,
    String metodoPagoDiferencia = 'EFECTIVO',
  }) async {
    if (items.isEmpty) {
      throw const FormatException('La reposición exige al menos una prenda');
    }
    _validarPlazoOffline(fechaCambioLimite);
    final codigoSucursal = sucursalId ?? 0;
    final repo = _returnRepo;
    // Mismo producto obligatorio (CU18): la variante nueva debe pertenecer
    // al mismo producto que la variante devuelta.
    for (final item in items) {
      final cambio = item.varianteCambioId;
      if (cambio == null) {
        throw const FormatException(
          'SIN_ALTERNATIVA: falta la prenda nueva (use devolución)',
        );
      }
      final productoNueva = await _productoDeVariante(cambio);
      if (productoNueva == null || (item.productoId != null && productoNueva != item.productoId)) {
        if (productoNueva != null) {
          throw const FormatException(
            'La prenda nueva debe ser del mismo producto (CU18)',
          );
        }
      }
    }
    // Stock verificado antes de reservar (central con red, local sin red).
    for (final item in items) {
      final cambio = item.varianteCambioId!;
      final disponibles = await _stockDisponible(cambio, codigoSucursal);
      if (disponibles < item.cantidad) {
        throw const FormatException(
          'SIN_ALTERNATIVA: sin stock de la talla pedida en la sucursal',
        );
      }
    }
    final uuid = await _uuid();
    var diferenciaTotal = 0.0;
    final itemsMap = <Map<String, Object?>>[];
    final movimientos = <({int varianteId, int delta, int deltaReserva})>[];
    for (final item in items) {
      final precioNueva = item.precioVarianteNueva ?? item.precioUnitario;
      final diferenciaLinea = (precioNueva - item.precioUnitario) * item.cantidad;
      diferenciaTotal += diferenciaLinea;
      itemsMap.add(<String, Object?>{
        'detalle_orden_id': item.detalleOrdenId,
        'variante_producto_id': item.varianteProductoId,
        'variante_cambio_id': item.varianteCambioId,
        'producto_id': item.productoId,
        'cantidad': item.cantidad,
        'precio_unitario': item.precioUnitario,
        'precio_variante_nueva': precioNueva,
        'diferencia': diferenciaLinea,
        'subtotal_diferencia': diferenciaLinea,
        'estado_item': 'NUEVA',
        'producto_nombre': item.productoNombre,
      });
      movimientos.add((
        varianteId: item.varianteProductoId,
        delta: item.cantidad,
        deltaReserva: 0,
      ));
      movimientos.add((
        varianteId: item.varianteCambioId!,
        delta: -item.cantidad,
        deltaReserva: -item.cantidad,
      ));
    }
    final clasificacion = _clasificarDiferencia(diferenciaTotal);
    final numeroReposicion = 'REP-LOCAL-${uuid.substring(0, 8).toUpperCase()}';
    final cabecera = <String, Object?>{
      'orden_origen_id': ordenOrigenId,
      'numero_comprobante_origen': numeroComprobanteOrigen.trim(),
      'numero_solicitud': 'REP-LOCAL-$uuid',
      'numero_reposicion': numeroReposicion,
      'tipo': 'REPOSICION',
      'motivo': motivo,
      'motivo_detalle': motivoDetalle,
      'estado': 'PENDIENTE_SINCRONIZACION',
      'estado_sincronizacion': 'PENDIENTE_SINCRONIZACION',
      'es_offline': 1,
      'diferencia_precio': clasificacion.diferencia,
      'tipo_diferencia': clasificacion.tipo,
      'monto_pagado_diferencia': clasificacion.pagado,
      'saldo_favor': clasificacion.saldo,
      'monto_reembolso': 0.0,
      'fecha_limite_cambio': fechaCambioLimite?.toUtc().toIso8601String(),
      'cliente_id': clienteId,
      'datos_json': '{"metodo_pago_diferencia":"$metodoPagoDiferencia"}',
    };
    await repo.registrar(
      uuid: uuid,
      cabecera: cabecera,
      items: itemsMap,
      movimientosStock: movimientos,
      sucursalId: codigoSucursal,
    );
    await _queue?.encolar(
      uuidOperacion: uuid,
      tipoOperacion: 'REPOSICION',
      sucursalId: sucursalId,
      payload: <String, Object?>{...cabecera, 'uuid_offline': uuid},
    );
    await _auditar('REPOSICION', uuid);
    return (await getSolicitudDesdeLocal(uuid))!;
  }

  /// Alias legacy: CAMBIO == reposición (compatibilidad con clientes viejos).
  Future<ReturnRequestModel> crearCambioOffline({
    required String numeroComprobanteOrigen,
    int? ordenOrigenId,
    int? sucursalId,
    int? clienteId,
    String motivo = MotivosDevolucion.tallaIncorrecta,
    String? motivoDetalle,
    required List<LineaDevolucion> items,
    DateTime? fechaCambioLimite,
  }) => crearReposicionOffline(
    numeroComprobanteOrigen: numeroComprobanteOrigen,
    ordenOrigenId: ordenOrigenId,
    sucursalId: sucursalId,
    clienteId: clienteId,
    motivo: motivo,
    motivoDetalle: motivoDetalle,
    items: items,
    fechaCambioLimite: fechaCambioLimite,
  );

  Future<int?> _productoDeVariante(int varianteId) async {
    final db = _database?.database;
    if (db == null) return null;
    final filas = await db.query(
      'variantes',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[varianteId, _tenantId ?? 0],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return (filas.first['producto_id'] as num?)?.toInt();
  }

  Future<int> _stockDisponible(int varianteId, int sucursalId) async {
    final db = _database?.database;
    if (db == null) return 0;
    final filas = await db.query(
      'stock',
      where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[varianteId, sucursalId, _tenantId ?? 0],
      limit: 1,
    );
    if (filas.isEmpty) return 0;
    final cantidad = (filas.first['cantidad'] as num?)?.toInt() ?? 0;
    final reservada =
        (filas.first['cantidad_reservada'] as num?)?.toInt() ?? 0;
    return cantidad - reservada;
  }

  /// CU13/CU18: solicitud guardada en local por su uuid offline.
  Future<ReturnRequestModel?> getSolicitudDesdeLocal(String uuidOffline) async {
    try {
      return await _returnRepo.detalle(uuidOffline);
    } catch (_) {
      return null;
    }
  }

  /// Mis devoluciones y reposiciones guardadas en local.
  Future<List<ReturnRequestModel>> listarDesdeLocal({String? tipo}) async {
    try {
      return await _returnRepo.listar(tipo: tipo);
    } catch (_) {
      return const [];
    }
  }

  /// CU13/CU18: ventas candidatas para un cambio (pendientes offline +
  /// reposiciones del servidor, tolerando 404/501 N3).
  Future<List<Map<String, Object?>>> getVentasParaCambio() async {
    final resultado = <Map<String, Object?>>[];
    try {
      final pendientes = await pendientesOffline();
      resultado.addAll(pendientes);
    } catch (_) {}
    try {
      final reposiciones = await listarReposiciones();
      resultado.addAll(reposiciones);
    } catch (_) {}
    return resultado;
  }

  // ====================================================================
  // [EXAMEN-2] Endpoints N3 en línea (toleran 404/501: degradan, no rompen).
  // ====================================================================

  /// `POST /devoluciones/cambio` (CU13 en línea) con `Idempotency-Key`.
  Future<Map<String, Object?>> registrarCambioOnline({
    required String numeroComprobanteOrigen,
    int? ordenOrigenId,
    int? sucursalId,
    String tipo = 'DEVOLUCION',
    String motivo = MotivosDevolucion.tallaIncorrecta,
    String? motivoDetalle,
    required List<ReturnItemCreate> items,
    String? uuidOffline,
  }) async {
    final api = _apiService;
    if (api == null) throw const FormatException('Servicio no configurado');
    try {
      final response = await api.dio.post(
        AppConstants.epDevolucionesCambio,
        data: {
          if (ordenOrigenId != null) 'orden_id': ordenOrigenId,
          'numero_comprobante': numeroComprobanteOrigen.trim(),
          'uuid_offline': uuidOffline,
          'tipo': tipo.toUpperCase(),
          'motivo': motivo.toUpperCase(),
          if (motivoDetalle != null) 'motivo_detalle': motivoDetalle.trim(),
          'sucursal_id': sucursalId,
          'items': items.map((item) => item.toJson()).toList(),
        },
        options: uuidOffline == null
            ? null
            : Options(headers: {'Idempotency-Key': uuidOffline}),
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, Object?>;
      }
      return const <String, Object?>{};
    } catch (e) {
      throw api.handleError(e);
    }
  }

  /// `POST /devoluciones/reposicion` (CU18 en línea).
  Future<Map<String, Object?>> registrarReposicionOnline({
    required String numeroComprobanteOrigen,
    int? ordenOrigenId,
    int? sucursalId,
    String motivo = MotivosDevolucion.tallaIncorrecta,
    String? motivoDetalle,
    required List<ReturnItemCreate> items,
    String? uuidOffline,
  }) => registrarCambioOnline(
    numeroComprobanteOrigen: numeroComprobanteOrigen,
    ordenOrigenId: ordenOrigenId,
    sucursalId: sucursalId,
    tipo: 'REPOSICION',
    motivo: motivo,
    motivoDetalle: motivoDetalle,
    items: items,
    uuidOffline: uuidOffline,
  );

  /// `GET /devoluciones/venta/{numero_comprobante}` (CU13/CU18).
  /// Devuelve null ante 404/501 N3 en vez de romper.
  Future<Map<String, Object?>?> buscarVentaOriginalOnline(
    String numeroComprobante,
  ) async {
    final api = _apiService;
    if (api == null) return null;
    try {
      final response = await api.dio.get(
        '${AppConstants.epDevolucionesVenta}/${numeroComprobante.trim()}',
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, Object?>;
      }
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 501) return null;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// `GET /devoluciones/validar-plazo/{orden_id}` (RN-012).
  /// Devuelve false ante 404/501 (degrada a la validación local).
  Future<bool> validarPlazoServidorOnline(int ordenId) async {
    final api = _apiService;
    if (api == null) return false;
    try {
      final response = await api.dio.get(
        '${AppConstants.epDevolucionesValidarPlazo}/$ordenId',
      );
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        return data['dentro_plazo'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// `GET /devoluciones/pendientes-offline` (CU13/CU18).
  Future<List<Map<String, Object?>>> pendientesOffline() async {
    final api = _apiService;
    if (api == null) return const [];
    try {
      final response = await api.dio.get(
        AppConstants.epDevolucionesPendientesOffline,
      );
      if (response.data is Map<String, dynamic>) {
        final lista = (response.data as Map)['pendientes'];
        if (lista is List) {
          return lista.map((e) => Map<String, Object?>.from(e)).toList();
        }
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// `GET /devoluciones/reposiciones` (CU18).
  Future<List<Map<String, Object?>>> listarReposiciones({
    String? estado,
    int skip = 0,
    int limit = 50,
  }) async {
    final api = _apiService;
    if (api == null) return const [];
    try {
      final response = await api.dio.get(
        AppConstants.epDevolucionesReposiciones,
        queryParameters: {
          if (estado != null) 'estado': estado,
          'skip': skip,
          'limit': limit,
        },
      );
      if (response.data is Map<String, dynamic>) {
        final lista = (response.data as Map)['reposiciones'];
        if (lista is List) {
          return lista.map((e) => Map<String, Object?>.from(e)).toList();
        }
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Desciende la nota de devolución (`GET .../nota`).
  /// Devuelve la ruta local o '' ante 404/501 (degradación).
  Future<String> descargarNotaDevolucion(int solicitudId) async {
    final api = _apiService;
    if (api == null) return '';
    try {
      final response = await api.dio.get(
        '${AppConstants.epDevolucionesNota}/$solicitudId/nota',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes is List<int> && bytes.isNotEmpty) {
        // La descarga definitiva la abre el visor; se reporta como lista.
        return 'nota-devolucion-$solicitudId:${bytes.length}';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// Desciende la nota de reposición (`GET .../nota-reposicion`).
  Future<String> descargarNotaReposicion(int solicitudId) async {
    final api = _apiService;
    if (api == null) return '';
    try {
      final response = await api.dio.get(
        '${AppConstants.epDevolucionesNotaReposicion}/$solicitudId/nota-reposicion',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes is List<int> && bytes.isNotEmpty) {
        return 'nota-reposicion-$solicitudId:${bytes.length}';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// `GET /devoluciones/alternativas-talla/{variante_id}` (RN-022).
  /// Vacío ante 404/501 N3.
  Future<List<Map<String, Object?>>> buscarAlternativaTalla({
    required int varianteId,
    int? sucursalId,
    String direccion = 'MAYOR',
    int cantidad = 1,
  }) async {
    final api = _apiService;
    if (api == null) return const [];
    try {
      final response = await api.dio.get(
        '${AppConstants.epDevolucionesAlternativasTalla}/$varianteId',
        queryParameters: {
          if (sucursalId != null) 'sucursal_id': sucursalId,
          'direccion': direccion.toUpperCase(),
          'cantidad': cantidad,
        },
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
      }
      if (response.data is Map<String, dynamic>) {
        final mapa = response.data as Map<String, dynamic>;
        final lista = mapa['alternativas'] ?? mapa['items'];
        if (lista is List) {
          return lista.map((e) => Map<String, Object?>.from(e)).toList();
        }
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// `POST /devoluciones/{solicitud_id}/notificar-alternativa` (RN-022).
  Future<bool> notificarSinAlternativa(int solicitudId) async {
    final api = _apiService;
    if (api == null) return false;
    try {
      await api.dio.post(
        '${AppConstants.epDevolucionesNotificarAlternativa}/$solicitudId/notificar-alternativa',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Aplica el resultado de sincronización a la devolución local.
  Future<int> aplicarResultadoSync({
    required String uuidOffline,
    required String estado,
    String? estadoSincronizacion,
    String? numeroReposicion,
  }) => _returnRepo.aplicarResultado(
    uuidOffline,
    estado: estado,
    estadoSincronizacion: estadoSincronizacion,
    numeroReposicion: numeroReposicion,
  );
}

/// [EXAMEN-2] Línea de prenda devuelta/devolución para la creación offline.
class LineaDevolucion {
  const LineaDevolucion({
    required this.varianteProductoId,
    this.detalleOrdenId,
    this.productoId,
    this.productoNombre,
    this.cantidad = 1,
    required this.precioUnitario,
    this.varianteCambioId,
    this.precioVarianteNueva,
  });

  final int varianteProductoId;
  final int? detalleOrdenId;
  final int? productoId;
  final String? productoNombre;
  final int cantidad;
  final double precioUnitario;
  final int? varianteCambioId;
  final double? precioVarianteNueva;
}
