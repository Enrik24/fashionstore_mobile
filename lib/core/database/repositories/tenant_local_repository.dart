import 'package:sqflite_sqlcipher/sqflite.dart';

/// [EXAMEN-2] Base de los repositorios locales con aislamiento multitenant.
abstract class TenantLocalRepository {
  TenantLocalRepository(this.db, {required this.tenantId});

  final DatabaseExecutor db;
  final int tenantId;

  Map<String, Object?> _conAuditoria(Map<String, Object?> datos) {
    return <String, Object?>{
      ...datos,
      'tenant_id': tenantId,
      'dispositivo_id': datos['dispositivo_id'],
      'usuario_id': datos['usuario_id'],
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<List<Map<String, Object?>>> consultar(
    String tabla, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    return db.query(
      tabla,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<int> insertarRegistro(String tabla, Map<String, Object?> datos) {
    return db.insert(tabla, _conAuditoria(datos));
  }

  /// Actualiza o inserta exigiendo que la clave existente pertenezca al tenant.
  Future<void> guardarPorClave(
    String tabla,
    String columnaClave,
    Object? clave,
    Map<String, Object?> datos,
  ) async {
    final existentes = await consultar(
      tabla,
      where: '$columnaClave = ? AND tenant_id = ?',
      whereArgs: <Object?>[clave, tenantId],
      limit: 1,
    );
    final auditados = _conAuditoria(datos);
    if (existentes.isEmpty) {
      await db.insert(tabla, auditados);
      return;
    }
    await db.update(
      tabla,
      auditados,
      where: '$columnaClave = ? AND tenant_id = ?',
      whereArgs: <Object?>[clave, tenantId],
    );
  }

  Future<int> eliminarRegistro(
    String tabla,
    String columnaClave,
    Object? clave, {
    String? whereExtra,
    List<Object?>? extraArgs,
  }) {
    final where = whereExtra == null
        ? '$columnaClave = ? AND tenant_id = ?'
        : '$columnaClave = ? AND tenant_id = ? AND $whereExtra';
    return db.delete(
      tabla,
      where: where,
      whereArgs: <Object?>[clave, tenantId, ...?extraArgs],
    );
  }

  /// [EXAMEN-2] Actualiza una fila por clave compuesta + tenant (Fase 3).
  /// No toca `dispositivo_id`/`usuario_id` salvo que vengan en [datos].
  Future<int> actualizarPorClaves(
    String tabla,
    Map<String, Object?> datos,
    Map<String, Object?> claves,
  ) async {
    final condiciones = <String>['tenant_id = ?'];
    final argumentos = <Object?>[tenantId];
    for (final entrada in claves.entries) {
      condiciones.add('${entrada.key} = ?');
      argumentos.add(entrada.value);
    }
    final auditados = _conAuditoria(datos);
    return db.update(
      tabla,
      auditados,
      where: condiciones.join(' AND '),
      whereArgs: argumentos,
    );
  }

  /// [EXAMEN-2] Cuenta filas por clave compuesta + tenant (Fase 3).
  Future<int> contarPorClaves(
    String tabla,
    Map<String, Object?> claves,
  ) async {
    final condiciones = <String>['tenant_id = ?'];
    final argumentos = <Object?>[tenantId];
    for (final entrada in claves.entries) {
      condiciones.add('${entrada.key} = ?');
      argumentos.add(entrada.value);
    }
    final filas = await consultar(
      tabla,
      where: condiciones.join(' AND '),
      whereArgs: argumentos,
      limit: 1,
    );
    return filas.length;
  }
}
