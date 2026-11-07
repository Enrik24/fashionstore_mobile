import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/conflict_repository.dart';
import '../models/phase2_models.dart';
import '../utils/sync_messages.dart';
import 'device_service.dart';
import 'local_audit_service.dart';

/// [EXAMEN-2] Conflictos de sincronización visibles y resolubles (CU09).
class ConflictService {
  ConflictService({
    required LocalDatabaseService database,
    required int tenantId,
    ConflictRepository? repository,
    LocalAuditService? audit,
    OfflineApiClient? client,
  }) : _database = database,
       _tenantId = tenantId,
       _repository = repository,
       _audit = audit,
       _client = client;

  final LocalDatabaseService _database;
  final int _tenantId;
  ConflictRepository? _repository;
  final LocalAuditService? _audit;
  final OfflineApiClient? _client;

  ConflictRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _repository ??= ConflictRepository(db, tenantId: _tenantId);
  }

  Future<List<ConflictModel>> pendientes() async {
    final filas = await _repo.listarPendientes();
    return filas.map(ConflictModel.fromMap).toList(growable: false);
  }

  Future<ConflictModel?> detalle(int id) async {
    final fila = await _repo.obtenerPorId(id);
    return fila == null ? null : ConflictModel.fromMap(fila);
  }

  Future<int> contadorPendientes() async => (await pendientes()).length;

  // [EXAMEN-2] C2.6 CU09: resolución backend + local (orden y auditable).
  Future<int> resolver(int id, {required String accion}) async {
    try {
      await _client?.post(
        '${AppConstants.epOfflineConflictos}/$id/resolver',
        data: <String, Object?>{'accion': accion},
      );
    } catch (_) {}
    final resultado = await _repo.resolver(id, accion: accion);
    await _audit?.registrar(
      tenantId: _tenantId,
      tipo: 'CONFLICTO_RESUELTO',
      mensaje: 'Conflicto resuelto.',
      datos: <String, dynamic>{'conflicto_id': id, 'accion': accion},
    );
    return resultado;
  }

  // [EXAMEN-2] C2.6 CU09: descarte backend + local.
  Future<int> descartar(int id) async {
    try {
      await _client?.post(
        '${AppConstants.epOfflineConflictos}/$id/descartar',
      );
    } catch (_) {}
    final resultado = await _repo.resolver(
      id,
      accion: 'DESCARTADA',
      estado: 'DESCARTADA',
    );
    await _audit?.registrar(
      tenantId: _tenantId,
      tipo: 'CONFLICTO_DESCARTADO',
      mensaje: 'Conflicto descartado.',
      datos: <String, dynamic>{'conflicto_id': id},
    );
    return resultado;
  }

  // [EXAMEN-2] C2.8: delega en SyncMessages (lógica sacada de ConflictService).
  String traducirMotivo(String motivo) => SyncMessages.traducirMotivo(motivo);
}
