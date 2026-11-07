import 'dart:convert';
import 'dart:math' as math;

import '../database/local_database_service.dart';
import '../database/repositories/conflict_repository.dart';
import '../database/repositories/offline_queue_repository.dart';
import '../models/phase2_models.dart';

/// [EXAMEN-2] Cola FIFO idempotente de operaciones offline (CU08).
class OfflineQueueService {
  OfflineQueueService({
    required LocalDatabaseService database,
    required int tenantId,
    required String dispositivoId,
    int? usuarioId,
    OfflineQueueRepository? repository,
    ConflictRepository? conflictRepository,
  }) : _database = database,
       _tenantId = tenantId,
       _dispositivoId = dispositivoId,
       _usuarioId = usuarioId,
       _repository = repository,
       _conflictRepository = conflictRepository;

  final LocalDatabaseService _database;
  final int _tenantId;
  final String _dispositivoId;
  final int? _usuarioId;
  OfflineQueueRepository? _repository;
  ConflictRepository? _conflictRepository;

  OfflineQueueRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _repository ??= OfflineQueueRepository(db, tenantId: _tenantId);
  }

  ConflictRepository get _conflictRepo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _conflictRepository ??= ConflictRepository(db, tenantId: _tenantId);
  }

  Future<int> siguienteSecuencia() => _repo.obtenerSiguienteSecuencia();

  Future<String> encolar({
    required String uuidOperacion,
    required String tipoOperacion,
    required Map<String, Object?> payload,
    int? secuenciaLocal,
    int? sucursalId,
    String estado = 'PENDIENTE',
  }) {
    return _repo.encolar(
      uuidOperacion: uuidOperacion,
      tipoOperacion: tipoOperacion,
      payload: payload,
      secuenciaLocal: secuenciaLocal,
      dispositivoId: _dispositivoId,
      usuarioId: _usuarioId,
      sucursalId: sucursalId,
      estado: estado,
    );
  }

  Future<List<OfflineOperationModel>> pendientes({int limite = 50}) async {
    final filas = await _repo.listarPendientes(limite: limite);
    return filas.map(OfflineOperationModel.fromMap).toList(growable: false);
  }

  Future<OfflineOperationModel?> obtener(String uuid) async {
    final fila = await _repo.obtenerPorUuid(uuid);
    return fila == null ? null : OfflineOperationModel.fromMap(fila);
  }

  Future<int> marcarEnviada(String uuid) =>
      _repo.actualizarEstado(uuid, 'ENVIADA');

  Future<int> reintentar(String uuid, {String? motivo}) async {
    await _repo.incrementarIntentos(uuid, ultimoError: motivo);
    final operacion = await obtener(uuid);
    final intentos = operacion?.intentos ?? 1;
    // Backoff exponencial: 2s, 4s, 8s... con un máximo seguro de 5 minutos.
    final retraso = Duration(
      seconds: math.min(300, math.pow(2, intentos.clamp(1, 8)).toInt()),
    );
    return _repo.actualizarEstado(
      uuid,
      'PENDIENTE',
      ultimoError: motivo,
      proximoIntento: DateTime.now().toUtc().add(retraso),
    );
  }

  Future<SyncSummaryModel> resumen() async {
    final counts = await _repo.resumir();
    return SyncSummaryModel.fromCounts(counts);
  }

  Future<int> limpiarConfirmadas({Duration? antiguedad}) async {
    final limite = DateTime.now()
        .subtract(antiguedad ?? const Duration(days: 30))
        .toUtc()
        .toIso8601String();
    final db = _database.database;
    if (db == null) return 0;
    return db.delete(
      'operaciones',
      where:
          "tenant_id = ? AND estado_sincronizacion IN "
          "('CONFIRMADA', 'DUPLICADA') AND "
          "COALESCE(fecha_confirmacion, fecha_actualizacion) < ?",
      whereArgs: <Object?>[_tenantId, limite],
    );
  }

  Future<void> aplicarResultado({
    required String uuidOperacion,
    required String estado,
    String? motivo,
    Map<String, Object?>? detalle,
    String? tipoConflicto,
    Map<String, Object?>? datosLocal,
    Map<String, Object?>? datosCentral,
  }) async {
    final normalizado = estado.toUpperCase();
    await _repo.actualizarEstado(
      uuidOperacion,
      normalizado,
      ultimoError: motivo,
      resultadoJson: detalle == null ? null : jsonEncode(detalle),
    );
    if (normalizado == 'CONFLICTO' || normalizado == 'RECHAZADA') {
      await _conflictRepo.crear(
        tipo: tipoConflicto ?? motivo ?? 'RECHAZADA',
        motivo: motivo ?? 'La operación fue rechazada por el servidor.',
        uuidOperacion: uuidOperacion,
        datosLocal: datosLocal == null ? null : jsonEncode(datosLocal),
        datosCentral: datosCentral == null ? null : jsonEncode(datosCentral),
        accion: 'REVISAR',
      );
    }
  }
}
