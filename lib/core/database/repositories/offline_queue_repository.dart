import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../local_schema.dart';
import 'tenant_local_repository.dart';

/// [EXAMEN-2] Cola FIFO persistente de operaciones pendientes de sincronizar.
class OfflineQueueRepository extends TenantLocalRepository {
  OfflineQueueRepository(super.db, {required super.tenantId});

  static const String _metaSecuencia = '__secuencia_operaciones__';

  Future<int> obtenerSiguienteSecuencia() async {
    final database = db;
    if (database is Database) {
      return database.transaction<int>((txn) async {
        return _incrementarSecuencia(txn);
      });
    }
    return _incrementarSecuencia(database);
  }

  Future<int> _incrementarSecuencia(DatabaseExecutor executor) async {
    final filas = await executor.query(
      'meta',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>[_metaSecuencia, tenantId],
      limit: 1,
    );
    final siguiente = filas.isEmpty
        ? 1
        : ((filas.first['secuencia_local'] as num?)?.toInt() ?? 0) + 1;
    final ahora = DateTime.now().toUtc().toIso8601String();
    if (filas.isEmpty) {
      await executor.insert('meta', <String, Object?>{
        'clave': _metaSecuencia,
        'tenant_id': tenantId,
        'secuencia_local': siguiente,
        'version_esquema': LocalSchema.version,
        'fecha_actualizacion': ahora,
      });
    } else {
      await executor.update(
        'meta',
        <String, Object?>{
          'secuencia_local': siguiente,
          'fecha_actualizacion': ahora,
        },
        where: 'clave = ? AND tenant_id = ?',
        whereArgs: <Object?>[_metaSecuencia, tenantId],
      );
    }
    return siguiente;
  }

  Future<String> encolar({
    required String uuidOperacion,
    required String tipoOperacion,
    required Map<String, Object?> payload,
    int? secuenciaLocal,
    required String dispositivoId,
    int? usuarioId,
    int? sucursalId,
    String estado = 'PENDIENTE',
  }) async {
    final secuencia = secuenciaLocal ?? await obtenerSiguienteSecuencia();
    await guardarPorClave(
      'operaciones',
      'uuid_operacion',
      uuidOperacion,
      <String, Object?>{
        'uuid_operacion': uuidOperacion,
        'dispositivo_id': dispositivoId,
        'usuario_id': usuarioId,
        'sucursal_id': sucursalId,
        'secuencia_local': secuencia,
        'tipo_operacion': tipoOperacion,
        'estado_sincronizacion': estado,
        'payload_json': _json(payload),
        'intentos': 0,
        'fecha_registro_local': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return uuidOperacion;
  }

  Future<Map<String, Object?>?> obtenerPorUuid(String uuid) async {
    final filas = await consultar(
      'operaciones',
      where: 'uuid_operacion = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, tenantId],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  Future<List<Map<String, Object?>>> listarPendientes({int limite = 50}) {
    // [EXAMEN-2] C2.2: respetar backoff (proximo_intento) para no reintentar antes de tiempo.
    final ahora = DateTime.now().toUtc().toIso8601String();
    return consultar(
      'operaciones',
      where:
          "tenant_id = ? AND estado_sincronizacion IN ('PENDIENTE', 'ERROR', 'RECHAZADA') "
          "AND (proximo_intento IS NULL OR proximo_intento <= ?)",
      whereArgs: <Object?>[tenantId, ahora],
      orderBy: 'secuencia_local ASC',
      limit: limite,
    );
  }

  Future<List<Map<String, Object?>>> listarPorEstado(
    String estado, {
    int? limite,
  }) {
    return consultar(
      'operaciones',
      where: 'estado_sincronizacion = ? AND tenant_id = ?',
      whereArgs: <Object?>[estado, tenantId],
      orderBy: 'secuencia_local ASC',
      limit: limite,
    );
  }

  Future<int> actualizarEstado(
    String uuid,
    String estado, {
    String? ultimoError,
    String? resultadoJson,
    DateTime? proximoIntento,
  }) {
    final ahora = DateTime.now().toUtc().toIso8601String();
    return db.update(
      'operaciones',
      <String, Object?>{
        'estado_sincronizacion': estado,
        'ultimo_error': ultimoError,
        'resultado_json': resultadoJson,
        'fecha_envio': estado == 'ENVIADA' ? ahora : null,
        'fecha_confirmacion': estado == 'CONFIRMADA' ? ahora : null,
        'proximo_intento': proximoIntento?.toUtc().toIso8601String(),
        'fecha_actualizacion': ahora,
      },
      where: 'uuid_operacion = ? AND tenant_id = ?',
      whereArgs: <Object?>[uuid, tenantId],
    );
  }

  Future<int> incrementarIntentos(String uuid, {String? ultimoError}) {
    return db.rawUpdate(
      '''UPDATE operaciones SET intentos = intentos + 1, ultimo_error = ?,
         fecha_actualizacion = ? WHERE uuid_operacion = ? AND tenant_id = ?''',
      <Object?>[
        ultimoError,
        DateTime.now().toUtc().toIso8601String(),
        uuid,
        tenantId,
      ],
    );
  }

  Future<int> eliminar(String uuid) =>
      eliminarRegistro('operaciones', 'uuid_operacion', uuid);

  Future<Map<String, int>> resumir() async {
    final filas = await db.rawQuery(
      '''SELECT estado_sincronizacion AS estado, COUNT(*) AS total
         FROM operaciones WHERE tenant_id = ? GROUP BY estado_sincronizacion''',
      <Object?>[tenantId],
    );
    return <String, int>{
      for (final fila in filas)
        (fila['estado'] as String? ?? 'DESCONOCIDO'):
            (fila['total'] as num?)?.toInt() ?? 0,
    };
  }

  String _json(Map<String, Object?> value) => jsonEncode(value);
}
