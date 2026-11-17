import 'tenant_local_repository.dart';

/// [EXAMEN-2] CachÃ© local de conflictos para poder revisarlos sin red.
class ConflictRepository extends TenantLocalRepository {
  ConflictRepository(super.db, {required super.tenantId});

  Future<int> crear({
    required String tipo,
    required String motivo,
    String? uuidOperacion,
    String? datosLocal,
    String? datosCentral,
    String? accion,
    String estado = 'PENDIENTE',
  }) async {
    final ahora = DateTime.now().toUtc().toIso8601String();
    // [FIX-SYNC] Un solo conflicto por operación: antes cada reintento
    // insertaba una fila nueva y el contador de conflictos se inflaba sin
    // límite (p. ej. "Conflictos: 2" para una única orden rechazada).
    if (uuidOperacion != null && uuidOperacion.isNotEmpty) {
      final existentes = await consultar(
        'conflictos',
        where: 'uuid_operacion = ? AND tenant_id = ?',
        whereArgs: <Object?>[uuidOperacion, tenantId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (existentes.isNotEmpty) {
        final id = (existentes.first['id'] as num).toInt();
        await db.update(
          'conflictos',
          <String, Object?>{
            'tipo': tipo,
            'motivo': motivo,
            'datos_local': datosLocal,
            'datos_central': datosCentral,
            'accion': accion,
            'estado': estado,
            'resuelto': estado == 'RESUELTO' ? 1 : 0,
            'fecha_actualizacion': ahora,
          },
          where: 'id = ? AND tenant_id = ?',
          whereArgs: <Object?>[id, tenantId],
        );
        return id;
      }
    }
    return db.insert('conflictos', <String, Object?>{
      'tenant_id': tenantId,
      'uuid_operacion': uuidOperacion,
      'tipo': tipo,
      'motivo': motivo,
      'datos_local': datosLocal,
      'datos_central': datosCentral,
      'accion': accion,
      'estado': estado,
      'resuelto': estado == 'RESUELTO' ? 1 : 0,
      'fecha_registro_local': ahora,
      'fecha_actualizacion': ahora,
    });
  }

  /// [FIX-SYNC] Elimina los duplicados heredados: por cada `uuid_operacion`
  /// con varios conflictos sin resolver, conserva el más reciente.
  Future<int> deduplicarPendientes() async {
    final filas = await consultar(
      'conflictos',
      where: 'resuelto = 0 AND tenant_id = ? AND uuid_operacion IS NOT NULL',
      whereArgs: <Object?>[tenantId],
    );
    final porUuid = <String, List<int>>{};
    for (final fila in filas) {
      final uuid = fila['uuid_operacion']?.toString() ?? '';
      final id = (fila['id'] as num?)?.toInt();
      if (uuid.isEmpty || id == null) continue;
      porUuid.putIfAbsent(uuid, () => <int>[]).add(id);
    }
    var eliminados = 0;
    for (final ids in porUuid.values) {
      if (ids.length < 2) continue;
      ids.sort();
      for (final id in ids.sublist(0, ids.length - 1)) {
        eliminados += await eliminar(id);
      }
    }
    return eliminados;
  }

  /// [FIX-SYNC] Descarta los conflictos sin resolver de una operación que se
  /// reactivó con el payload corregido: el conflicto original ya no aplica.
  Future<int> descartarPorOperacion(String uuidOperacion) {
    return db.delete(
      'conflictos',
      where: 'uuid_operacion = ? AND tenant_id = ? AND resuelto = 0',
      whereArgs: <Object?>[uuidOperacion, tenantId],
    );
  }

  Future<void> guardar(Map<String, Object?> conflicto) async {
    final id = conflicto['id'];
    if (id is int) {
      await guardarPorClave('conflictos', 'id', id, conflicto);
    } else {
      await crear(
        tipo: conflicto['tipo'] as String? ?? 'DESCONOCIDO',
        motivo: conflicto['motivo'] as String? ?? '',
        uuidOperacion: conflicto['uuid_operacion'] as String?,
        datosLocal: conflicto['datos_local'] as String?,
        datosCentral: conflicto['datos_central'] as String?,
        accion: conflicto['accion'] as String?,
        estado: conflicto['estado'] as String? ?? 'PENDIENTE',
      );
    }
  }

  Future<Map<String, Object?>?> obtenerPorId(int id) async {
    final filas = await consultar(
      'conflictos',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[id, tenantId],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  Future<List<Map<String, Object?>>> listarPendientes() {
    return consultar(
      'conflictos',
      where: 'resuelto = 0 AND tenant_id = ?',
      whereArgs: <Object?>[tenantId],
      orderBy: 'fecha_registro_local DESC',
    );
  }

  Future<List<Map<String, Object?>>> listarPorEstado(String estado) {
    return consultar(
      'conflictos',
      where: 'estado = ? AND tenant_id = ?',
      whereArgs: <Object?>[estado, tenantId],
      orderBy: 'fecha_registro_local DESC',
    );
  }

  Future<int> resolver(
    int id, {
    required String accion,
    String estado = 'RESUELTO',
    String? datosCentral,
  }) {
    return db.update(
      'conflictos',
      <String, Object?>{
        'accion': accion,
        'estado': estado,
        'resuelto': 1,
        'datos_central': datosCentral,
        'fecha_resolucion': DateTime.now().toUtc().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[id, tenantId],
    );
  }

  Future<int> eliminar(int id) => eliminarRegistro('conflictos', 'id', id);
}
