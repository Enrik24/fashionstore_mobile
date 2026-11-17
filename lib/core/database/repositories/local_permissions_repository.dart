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

  /// [EXAMEN-2] B1.8.d: roles del usuario guardados localmente.
  ///
  /// En modo offline no hay sesión online de la que sacar los roles: se usan
  /// los que se descargaron con la sesión offline (`POST /offline/sesion/iniciar`
  /// → `LocalPermissionsRepository.guardar`). Antes esta información se
  /// guardaba pero **nunca se leía**, así que el POS quedaba bloqueado para
  /// el cajero que operaba sin conexión.
  Future<Set<String>> leerRoles({
    required int tenantId,
    required int usuarioId,
  }) async {
    final db = _database.database;
    if (db == null) return const {};
    final filas = await db.query(
      'permisos',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object>['actual_$usuarioId', tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return const {};
    final rol = filas.first['rol']?.toString() ?? '';
    if (rol.isEmpty) return const {};
    return rol
        .split(',')
        .map((r) => r.trim().toLowerCase())
        .where((r) => r.isNotEmpty)
        .toSet();
  }
}
