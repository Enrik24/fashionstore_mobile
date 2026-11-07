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
  }) {
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
      'fecha_registro_local': DateTime.now().toUtc().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    });
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
