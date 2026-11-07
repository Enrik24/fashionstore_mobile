import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../local_database_service.dart';

/// [EXAMEN-2] Repositorio local de roles y permisos efectivos.
class LocalPermissionsRepository {
  LocalPermissionsRepository(this._database);

  final LocalDatabaseService _database;

  Future<void> guardar({
    required int tenantId,
    required int usuarioId,
    required List<String> roles,
    required List<String> permisos,
  }) async {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    await db.insert('permisos', <String, Object?>{
      'clave': 'actual_$usuarioId',
      'tenant_id': tenantId,
      'rol': roles.join(','),
      'permisos': jsonEncode(permisos),
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> leerPermisos({
    required int tenantId,
    required int usuarioId,
  }) async {
    final db = _database.database;
    if (db == null) return const [];
    final filas = await db.query(
      'permisos',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object>['actual_$usuarioId', tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return const [];
    try {
      final raw = filas.first['permisos']?.toString() ?? '[]';
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }
}
