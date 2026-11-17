import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../config/constants.dart';
import '../models/reservation_model.dart';
import 'api_service.dart';
import '../database/local_database_service.dart';
import '../database/repositories/local_reservation_repository.dart';
import 'local_crypto_service.dart';
import 'offline_queue_service.dart';

class ReservationService {
  final ApiService _apiService;
  final LocalDatabaseService? _database;
  final int? _tenantId;
  final OfflineQueueService? _queue;
  final Object? _documents; // OfflineDocumentService (evita ciclo de import si es null)
  LocalReservationRepository? _repository;
  final LocalCryptoService _crypto = LocalCryptoService();
  // [EXAMEN-2] B0.4: id del usuario para estampar `usuario_id`.
  final int? _usuarioId;

  ReservationService({
    required ApiService apiService,
    LocalDatabaseService? database,
    int? tenantId,
    OfflineQueueService? queue,
    Object? documents,
    int? usuarioId,
  }) : _apiService = apiService,
       _database = database,
       _tenantId = tenantId,
       _queue = queue,
       _documents = documents,
       _usuarioId = usuarioId;

  // [EXAMEN-2] C2.5 (§7.6) CU06: aviso visible "Stock no verificado" para offline.
  static const String avisoStockNoVerificado =
      'Stock no verificado — reserva pendiente de confirmación del servidor';

  // [EXAMEN-2] C2.5: alias canónicos del plan §7.6.
  Future<List<ReservationModel>> getMisReservasConRespaldo() => getReservas();

  /// [EXAMEN-2] B1.2.a: genera el comprobante temporal local de la reserva.
  ///
  /// Se invoca desde el camino offline de `crearReserva`. El `documents` se
  /// inyecta como `Object` (duck-typing) para no acoplar este servicio con el
  /// generador de PDF y evitar un ciclo de imports.
  Future<String?> _generarComprobanteTemporal({
    required String uuidReserva,
    required int sucursalId,
    required DateTime fechaReserva,
    String? horarioAproximado,
    String? notas,
    required List<Map<String, dynamic>> items,
    bool conAvisoStock = true,
  }) async {
    final docs = _documents;
    if (docs == null) return null;
    try {
      // ignore: respuesta dinámica por duck-typing para no acoplar tipos
      // ignore: avoid_dynamic_calls
      final ruta = await (docs as dynamic).generarComprobanteTemporal(
        uuidOffline: uuidReserva,
        tipo: 'RESERVA',
        datos: <String, Object?>{
          'sucursal_id': sucursalId,
          'fecha_reserva': fechaReserva.toUtc().toIso8601String(),
          'horario_aproximado': horarioAproximado,
          'notas': notas,
          'prendas': items.length,
          if (conAvisoStock) 'aviso': avisoStockNoVerificado,
        },
      );
      return ruta?.toString();
    } catch (_) {
      // El comprobante es un extra: su fallo no debe tumbar la reserva.
      return null;
    }
  }

  Future<void> marcarReservaEnviadaLocal(String uuidReserva) async {
    final db = _database?.database;
    if (db == null) return;
    await db.update(
      'reservas_locales',
      <String, Object?>{
        'estado': 'CONFIRMADA',
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'uuid_reserva = ?',
      whereArgs: <Object?>[uuidReserva],
    );
  }

  LocalReservationRepository get _local {
    final db = _database?.database;
    if (db == null) throw StateError('La base local no esta abierta.');
    return _repository ??= LocalReservationRepository(
      db,
      tenantId: _tenantId ?? 0,
      usuarioId: _usuarioId,
    );
  }

  Future<List<ReservationModel>> getReservas() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epMisReservas);
      if (response.data is List) {
        return (response.data as List)
            .map(
              (item) => ReservationModel.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      } else if (response.data is Map && response.data['items'] != null) {
        return (response.data['items'] as List)
            .map(
              (item) => ReservationModel.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      }
      return [];
    } catch (e) {
      final local = await _reservasLocales();
      if (local.isNotEmpty) return local;
      throw _apiService.handleError(e);
    }
  }

  Future<ReservationModel> getReservaDetalle(int id) async {
    try {
      final response = await _apiService.dio.get(
        '${AppConstants.epReservas}$id',
      );
      return ReservationModel.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<ReservationModel> crearReserva({
    required int sucursalId,
    required DateTime fechaReserva,
    String? horarioAproximado,
    String? notas,
    required List<Map<String, dynamic>> items,
    // [EXAMEN-2] B0.4.d: cliente asociado a la reserva (si se conoce).
    int? clienteId,
    // [EXAMEN-2] B1.2.d: forzada por stock local insuficiente.
    bool forzar = false,
  }) async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(fechaReserva);
    final startTime =
        (horarioAproximado != null && horarioAproximado.isNotEmpty)
        ? horarioAproximado.split(' ').first
        : '12:00';
    final payload = <String, Object?>{
      'sucursal_id': sucursalId,
      'fecha_reserva': '${formattedDate}T$startTime:00',
      if (horarioAproximado != null && horarioAproximado.isNotEmpty)
        'horario_aproximado': startTime,
      if (notas != null && notas.isNotEmpty) 'notas': notas,
      'detalles': items,
    };
    try {
      // The backend expects a valid time (HH:MM) in horario_aproximado.
      // The UI sends a human label like '15:00 - 18:00 (Tarde)', so we extract
      // the start time and also use it to build the full datetime for fecha_reserva.
      final startTime =
          (horarioAproximado != null && horarioAproximado.isNotEmpty)
          ? horarioAproximado.split(' ').first
          : '12:00';
      final payload = {
        'sucursal_id': sucursalId,
        'fecha_reserva': '${formattedDate}T$startTime:00',
        if (horarioAproximado != null && horarioAproximado.isNotEmpty)
          'horario_aproximado': startTime,
        if (notas != null && notas.isNotEmpty) 'notas': notas,
        'detalles': items,
      };

      final response = await _apiService.dio.post(
        AppConstants.epReservas,
        data: payload,
      );

      return ReservationModel.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      // [EXAMEN-2] B1.2.k: sólo los fallos de **conectividad** degradan a
      // reserva local. Un 4xx del servidor (validación, tenant suspendido…)
      // debe propagarse: antes se creaba una reserva local "fantasma" y el
      // usuario creía que se había registrado.
      if (!_esErrorDeRed(e)) {
        throw _apiService.handleError(e);
      }
      final uuid = _uuid();
      // [EXAMEN-2] B1.2.c: se valida el stock **local** antes de registrar.
      // Si no alcanza, se puede forzar (queda para revisión del servidor).
      final stockPorVariante = <int, int>{};
      var stockInsuficiente = false;
      for (final item in items) {
        final varianteId = (item['variante_producto_id'] as num?)?.toInt();
        if (varianteId == null) continue;
        final cantidad = (item['cantidad'] as num?)?.toInt() ?? 1;
        final stock = await _stockConocido(varianteId, sucursalId);
        stockPorVariante[varianteId] = stock;
        if (stock >= 0 && stock < cantidad) stockInsuficiente = true;
      }
      final requiereRevision = forzar || stockInsuficiente;
      await _local.crear(uuid, <String, Object?>{
        'estado': 'PENDIENTE_SINCRONIZACION',
        'sucursal_id': sucursalId,
        'fecha_reserva': payload['fecha_reserva'],
        'horario_aproximado': startTime,
        'notas': notas,
        'datos_json': _json(items),
        // [EXAMEN-2] B0.4.d: cliente y usuario de la reserva.
        'cliente_id': clienteId,
        'usuario_id': _usuarioId,
        // [EXAMEN-2] B1.2.d: forzada por stock local insuficiente.
        'requiere_revision': requiereRevision ? 1 : 0,
        'fecha_registro_local': DateTime.now().toUtc().toIso8601String(),
      });
      await _local.guardarItems(
        uuid,
        items.indexed.map(
          (entry) => <String, Object?>{
            'variante_producto_id': entry.$2['variante_producto_id'],
            'cantidad': entry.$2['cantidad'],
            // [EXAMEN-2] B1.2.e: stock local considerado al reservar.
            'stock_conocido':
                stockPorVariante[(entry.$2['variante_producto_id'] as num?)?.toInt() ??
                    -1] ??
                entry.$2['stock_conocido'],
          },
        ),
      );
      await _queue?.encolar(
        uuidOperacion: uuid,
        tipoOperacion: 'RESERVA',
        // [EXAMEN-2] B0.4.e: la sucursal viaja en la operación (§9.5).
        sucursalId: sucursalId,
        payload: <String, Object?>{
          'uuid_reserva': uuid,
          ...payload,
          'detalles': items,
          // [EXAMEN-2] B1.2.d: revisión manual en el servidor (RN-006).
          'requiere_revision': requiereRevision,
        },
      );
      // [EXAMEN-2] B1.2.b: el comprobante temporal se genera en el camino
      // vivo; antes la reserva offline salía sin comprobante.
      await _generarComprobanteTemporal(
        uuidReserva: uuid,
        sucursalId: sucursalId,
        fechaReserva: fechaReserva,
        horarioAproximado: startTime,
        notas: notas,
        items: items,
      );
      return ReservationModel(
        id: 0,
        numeroReserva: 'RES-OFFLINE-$uuid',
        clienteId: clienteId ?? 0,
        sucursalId: sucursalId,
        fechaReserva: fechaReserva,
        horarioAproximado: startTime,
        estado: 'PENDIENTE_SINCRONIZACION',
        notas: notas,
        items: items
            .map((item) => ReservationItemModel.fromJson(item))
            .toList(growable: false),
        uuidReserva: uuid,
        esOffline: true,
        estadoSincronizacion: 'PENDIENTE',
      );
    }
  }

  /// [EXAMEN-2] B1.2.k: ¿el fallo es de conectividad (y no del servidor)?
  bool _esErrorDeRed(Object error) {
    if (error is DioException) {
      // Si el servidor respondió (cualquier código), no es un problema de red.
      if (error.response?.statusCode != null) return false;
      return true;
    }
    if (error is SocketException) return true;
    final texto = error.toString().toLowerCase();
    return texto.contains('socket') ||
        texto.contains('connection') ||
        texto.contains('network') ||
        texto.contains('failed host lookup') ||
        texto.contains('connection refused');
  }

  /// [EXAMEN-2] B1.2.c: stock local conocido de una variante en la sucursal.
  /// Devuelve `-1` si no hay dato local (no se puede afirmar insufficiency).
  Future<int> _stockConocido(int varianteId, int sucursalId) async {
    final db = _database?.database;
    if (db == null) return -1;
    final filas = await db.query(
      'stock',
      where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[varianteId, sucursalId, _tenantId ?? 0],
      limit: 1,
    );
    if (filas.isEmpty) return -1;
    final cantidad = (filas.first['cantidad'] as num?)?.toInt() ?? 0;
    final reservada = (filas.first['cantidad_reservada'] as num?)?.toInt() ?? 0;
    return cantidad - reservada;
  }

  Future<void> cancelarReserva(int id) async {
    try {
      await _apiService.dio.post('${AppConstants.epReservas}$id/cancelar');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<BranchModel>> getSucursales() async {
    var sucursales = <BranchModel>[];
    try {
      final response = await _apiService.dio.get(AppConstants.epSucursales);
      if (response.data is List) {
        sucursales = (response.data as List)
            .map((item) => BranchModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map && response.data['items'] != null) {
        sucursales = (response.data['items'] as List)
            .map((item) => BranchModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // [FIX] Con conexión intermitente el GET puede fallar: en lugar de
      // propagar el error (que antes disparaba sucursales "de mentira" en el
      // provider), se degrada al respaldo local de abajo.
    }
    // [FIX] Respaldo offline: las sucursales reales descargadas por el paquete
    // (`descargarSucursales` de OfflineCatalogService) viven en la tabla local
    // `sucursales`; antes este servicio era solo-online y nunca las leía.
    if (sucursales.isEmpty) {
      final locales = await _sucursalesLocales();
      if (locales.isNotEmpty) return locales;
    }
    return sucursales;
  }

  /// [FIX] Sucursales reales del catálogo descargado (modo offline).
  Future<List<BranchModel>> _sucursalesLocales() async {
    final db = _database?.database;
    if (db == null) return const [];
    try {
      final filas = await db.query(
        'sucursales',
        where: 'tenant_id = ?',
        whereArgs: <Object?>[_tenantId ?? 0],
        orderBy: 'nombre COLLATE NOCASE',
      );
      return filas
          .map(
            (fila) => BranchModel(
              id: (fila['id'] as num?)?.toInt() ?? 0,
              nombre: fila['nombre']?.toString() ?? 'Sucursal',
              direccion: fila['direccion']?.toString() ?? '',
              telefono: fila['telefono']?.toString(),
              latitud: (fila['latitud'] as num?)?.toDouble() ?? -17.7833,
              longitud: (fila['longitud'] as num?)?.toDouble() ?? -63.1821,
              horarioApertura: fila['horario']?.toString(),
              activo: (fila['estado']?.toString() ?? 'ACTIVA')
                  .toUpperCase()
                  .contains('ACTIV'),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<ReservationModel>> _reservasLocales() async {
    final db = _database?.database;
    if (db == null) return const [];
    final filas = await _local.listarTodos();
    final resultado = <ReservationModel>[];
    for (final fila in filas) {
      final uuid = fila['uuid_reserva']?.toString() ?? '';
      // [EXAMEN-2] B1.2.j: las prendas de la reserva se recuperan del detalle
      // local; antes la tarjeta no mostraba ninguna.
      final items = await _itemsDeReserva(uuid);
      resultado.add(
        ReservationModel(
          id: 0,
          numeroReserva: 'RES-${fila['uuid_reserva']}',
          clienteId: (fila['cliente_id'] as num?)?.toInt() ?? 0,
          sucursalId: (fila['sucursal_id'] as num?)?.toInt() ?? 0,
          fechaReserva:
              DateTime.tryParse(fila['fecha_reserva']?.toString() ?? '') ??
              DateTime.now(),
          horarioAproximado: fila['horario_aproximado']?.toString(),
          estado: fila['estado']?.toString() ?? 'PENDIENTE_SINCRONIZACION',
          notas: fila['notas']?.toString(),
          uuidReserva: uuid,
          esOffline: true,
          estadoSincronizacion:
              fila['estado_sincronizacion']?.toString() ?? 'PENDIENTE',
          items: items,
        ),
      );
    }
    return resultado;
  }

  /// [EXAMEN-2] B1.2.j: detalle local de una reserva.
  Future<List<ReservationItemModel>> _itemsDeReserva(String uuid) async {
    if (uuid.isEmpty) return const [];
    try {
      final filas = await _local.listarItems(uuid);
      return filas
          .map(
            (fila) => ReservationItemModel.fromJson(
              Map<String, dynamic>.from(fila),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  // [EXAMEN-2] C2.1: UUID v4 reales (RN-005).
  String _uuid() => _crypto.generarUuid();

  String _json(Object value) => const JsonEncoder().convert(value);
}
