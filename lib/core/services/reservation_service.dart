import 'dart:convert';

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

  ReservationService({
    required ApiService apiService,
    LocalDatabaseService? database,
    int? tenantId,
    OfflineQueueService? queue,
    Object? documents,
  }) : _apiService = apiService,
       _database = database,
       _tenantId = tenantId,
       _queue = queue,
       _documents = documents;

  // [EXAMEN-2] C2.5 (§7.6) CU06: aviso visible "Stock no verificado" para offline.
  static const String avisoStockNoVerificado =
      'Stock no verificado — reserva pendiente de confirmación del servidor';

  // [EXAMEN-2] C2.5 (§7.6) CU06: crea reserva local + comprobante temporal.
  Future<ReservationModel> crearReservaOffline({
    required int sucursalId,
    required DateTime fechaReserva,
    String? horarioAproximado,
    String? notas,
    required List<Map<String, dynamic>> items,
  }) async {
    final creada = await crearReserva(
      sucursalId: sucursalId,
      fechaReserva: fechaReserva,
      horarioAproximado: horarioAproximado,
      notas: notas,
      items: items,
    );
    if (creada.esOffline && creada.uuidReserva != null) {
      try {
        final docs = _documents;
        if (docs != null && docs.runtimeType.toString().contains('OfflineDocument')) {
          // ignore: respuesta dinámica por duck-typing para no acoplar tipos
          // ignore: avoid_dynamic_calls
          await (docs as dynamic).generarComprobanteTemporal(
            uuidOffline: creada.uuidReserva,
            tipo: 'RESERVA',
            datos: <String, Object?>{
              'sucursal_id': sucursalId,
              'fecha_reserva': creada.fechaReserva.toUtc().toIso8601String(),
              'aviso': avisoStockNoVerificado,
            },
          );
        }
      } catch (_) {}
    }
    return creada;
  }

  // [EXAMEN-2] C2.5: alias canónicos del plan §7.6.
  Future<List<ReservationModel>> getMisReservasConRespaldo() => getReservas();

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
      final uuid = _uuid();
      await _local.crear(uuid, <String, Object?>{
        'estado': 'PENDIENTE_SINCRONIZACION',
        'sucursal_id': sucursalId,
        'fecha_reserva': payload['fecha_reserva'],
        'horario_aproximado': startTime,
        'notas': notas,
        'datos_json': _json(items),
        'fecha_registro_local': DateTime.now().toUtc().toIso8601String(),
      });
      await _local.guardarItems(
        uuid,
        items.indexed.map(
          (entry) => <String, Object?>{
            'variante_producto_id': entry.$2['variante_producto_id'],
            'cantidad': entry.$2['cantidad'],
          },
        ),
      );
      await _queue?.encolar(
        uuidOperacion: uuid,
        tipoOperacion: 'RESERVA',
        payload: <String, Object?>{
          'uuid_reserva': uuid,
          ...payload,
          'detalles': items,
        },
      );
      return ReservationModel(
        id: 0,
        numeroReserva: 'RES-OFFLINE-$uuid',
        clienteId: 0,
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

  Future<void> cancelarReserva(int id) async {
    try {
      await _apiService.dio.post('${AppConstants.epReservas}$id/cancelar');
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<BranchModel>> getSucursales() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epSucursales);
      if (response.data is List) {
        return (response.data as List)
            .map((item) => BranchModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map && response.data['items'] != null) {
        return (response.data['items'] as List)
            .map((item) => BranchModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<ReservationModel>> _reservasLocales() async {
    final db = _database?.database;
    if (db == null) return const [];
    final filas = await _local.listarTodos();
    return filas
        .map((fila) {
          return ReservationModel(
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
            uuidReserva: fila['uuid_reserva']?.toString(),
            esOffline: true,
          );
        })
        .toList(growable: false);
  }

  // [EXAMEN-2] C2.1: UUID v4 reales (RN-005).
  String _uuid() => _crypto.generarUuid();

  String _json(Object value) => const JsonEncoder().convert(value);
}
