import 'dart:convert';

import '../database/local_database_service.dart';

/// [EXAMEN-2] Bitácora local mínima, sin secretos ni payloads completos.
class LocalAuditService {
  LocalAuditService(this._database);

  final LocalDatabaseService _database;

  Future<void> registrar({
    required int tenantId,
    required String tipo,
    required String mensaje,
    Map<String, dynamic>? datos,
  }) async {
    final db = _database.database;
    if (db == null) return;
    await db.insert('bitacora_local', <String, Object?>{
      'tenant_id': tenantId,
      'fecha': DateTime.now().toUtc().toIso8601String(),
      'tipo': tipo,
      'mensaje': mensaje,
      'datos': datos == null ? null : jsonEncode(datos),
    });
  }

  Future<List<Map<String, Object?>>> listar({int limit = 100}) async {
    final db = _database.database;
    if (db == null) return const [];
    return db.query('bitacora_local', orderBy: 'fecha DESC', limit: limit);
  }

  // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): tipos de auditoría de la fase.
  static const String tipoDevolucion = 'DEVOLUCION';
  static const String tipoReposicion = 'REPOSICION';
  static const String tipoCompensacion = 'COMPENSACION';

  Future<void> limpiar({required int tenantId}) async {
    final db = _database.database;
    if (db == null) return;
    await db.delete(
      'bitacora_local',
      where: 'tenant_id = ?',
      whereArgs: <Object>[tenantId],
    );
  }
}
