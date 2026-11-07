import 'tenant_local_repository.dart';

/// [EXAMEN-2] Repositorio de pagos diferidos pendientes y su estado local.
class LocalPaymentRepository extends TenantLocalRepository {
  LocalPaymentRepository(super.db, {required super.tenantId});

  Future<void> crear(
    String uuidPago, {
    required double monto,
    String? uuidOrden,
    String? moneda,
    DateTime? fechaExpiracion,
    String? idempotencyKey,
    Map<String, Object?> datos = const {},
  }) {
    return guardarPorClave('pagos', 'uuid_pago', uuidPago, <String, Object?>{
      ...datos,
      'uuid_pago': uuidPago,
      'uuid_orden': uuidOrden,
      'estado': datos['estado'] ?? 'PENDIENTE',
      'monto': monto,
      'moneda': moneda,
      'fecha_expiracion': fechaExpiracion?.toUtc().toIso8601String(),
      'intentos': datos['intentos'] ?? 0,
      'idempotency_key': idempotencyKey ?? uuidPago,
      'fecha_registro_local':
          datos['fecha_registro_local'] ??
          DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> guardar(Map<String, Object?> pago) =>
      guardarPorClave('pagos', 'uuid_pago', pago['uuid_pago'], pago);

  Future<Map<String, Object?>?> obtenerPorUuid(String uuid) async {
    final filas = await consultar(
      'pagos',
      where: 'uuid_pago = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, tenantId],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  Future<List<Map<String, Object?>>> listarPorEstado(String estado) {
    return consultar(
      'pagos',
      where: 'estado = ? AND tenant_id = ?',
      whereArgs: <Object?>[estado, tenantId],
      orderBy: 'fecha_registro_local DESC',
    );
  }

  Future<List<Map<String, Object?>>> listarTodos() {
    return consultar(
      'pagos',
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantId],
      orderBy: 'fecha_registro_local DESC',
    );
  }

  Future<int> actualizarEstado(
    String uuid,
    String estado, {
    String? ultimoError,
    String? datosJson,
  }) {
    return db.update(
      'pagos',
      <String, Object?>{
        'estado': estado,
        'ultimo_error': ultimoError,
        'datos_json': datosJson,
        'fecha_confirmacion': estado == 'CONFIRMADO'
            ? DateTime.now().toUtc().toIso8601String()
            : null,
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'uuid_pago = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, tenantId],
    );
  }

  Future<int> registrarIntento(String uuid, {String? ultimoError}) {
    return db.rawUpdate(
      '''UPDATE pagos SET intentos = intentos + 1, ultimo_error = ?,
         fecha_actualizacion = ? WHERE uuid_pago = ? AND tenant_id = ?''',
      <Object?>[
        ultimoError,
        DateTime.now().toUtc().toIso8601String(),
        uuid,
        tenantId,
      ],
    );
  }

  Future<int> eliminar(String uuid) =>
      eliminarRegistro('pagos', 'uuid_pago', uuid);
}
