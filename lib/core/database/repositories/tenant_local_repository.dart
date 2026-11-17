import 'package:sqflite_sqlcipher/sqflite.dart';

/// [EXAMEN-2] Base de los repositorios locales con aislamiento multitenant.
abstract class TenantLocalRepository {
  TenantLocalRepository(this.db, {required this.tenantId, this.usuarioId});

  final DatabaseExecutor db;
  final int tenantId;

  /// [EXAMEN-2] B0.4: id del usuario autenticado. Se estampa automáticamente
  /// en toda fila local que no lo traiga explícitamente, de modo que cada
  /// operación offline registre `tenant_id` + `usuario_id` + `dispositivo_id`
  /// + `uuid_operacion` (CU17).
  final int? usuarioId;

  Map<String, Object?> _conAuditoria(Map<String, Object?> datos) {
    return <String, Object?>{
      ...datos,
      'tenant_id': tenantId,
      'dispositivo_id': datos['dispositivo_id'],
      'usuario_id': datos['usuario_id'] ?? usuarioId,
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    };
  }

  // [EXAMEN-2] Defensa del esquema local: el backend puede agregar campos
  // nuevos al payload (ej. sku_producto/talla/color/precio_variante en
  // variantes). Si la tabla no conoce la columna, se descarta esa clave
  // para que la descarga nunca muera por un campo desconocido.
  static final Map<String, Set<String>?> _columnasPorTabla = <String, Set<String>?>{};

  Future<Set<String>> _columnasReales(String tabla) async {
    final enCache = _columnasPorTabla[tabla];
    if (enCache != null) return enCache;
    final filas = await db.rawQuery('PRAGMA table_info($tabla)');
    final nombres = filas
        .map((fila) => fila['name']?.toString())
        .whereType<String>()
        .toSet();
    _columnasPorTabla[tabla] = nombres;
    return nombres;
  }

  Future<Map<String, Object?>> _soloColumnasConocidas(
    String tabla,
    Map<String, Object?> datos,
  ) async {
    final columnas = await _columnasReales(tabla);
    if (columnas.isEmpty) return datos;
    final filtrados = <String, Object?>{
      for (final entrada in datos.entries)
        if (columnas.contains(entrada.key)) entrada.key: entrada.value,
    };
    // Las columnas de auditoría son obligatorias (NOT NULL en el esquema).
    filtrados['tenant_id'] = datos['tenant_id'] ?? tenantId;
    filtrados['fecha_actualizacion'] = datos['fecha_actualizacion'];
    return filtrados;
  }

  /// [EXAMEN-2] API pública para sub-repositorios que construyen INSERT/UPDATE
  /// propios: descarta las claves que la tabla local no conoce.
  Future<Map<String, Object?>> filtrarColumnasTabla(
    String tabla,
    Map<String, Object?> datos,
  ) => _soloColumnasConocidas(tabla, datos);

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

  Future<int> insertarRegistro(String tabla, Map<String, Object?> datos) async {
    final filtrados = await _soloColumnasConocidas(tabla, _conAuditoria(datos));
    return db.insert(tabla, filtrados);
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
    final auditados = await _soloColumnasConocidas(tabla, _conAuditoria(datos));
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
    final auditados = await _soloColumnasConocidas(tabla, _conAuditoria(datos));
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
