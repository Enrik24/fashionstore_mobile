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

  /// [EXAMEN-2] B2.11 (§9.5 del plan padre): la operación se persiste en la
  /// tabla `operaciones` con el cuerpo en `payload_json` (JSON string). Al
  /// **enviar** (POST /offline/sync) se decodifica a `payload` (mapa JSON).
  /// El contrato completo del request/respuesta y los estados válidos está
  /// documentado en el bloque de cabecera de `core/services/sync_engine_service.dart`.
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
    // [FIX-SYNC] Sólo PENDIENTE/ERROR se reenvían (como el frontend web):
    // RECHAZADA/CONFLICTO son terminales y quedan para revisión manual;
    // incluirlas aquí reenviaba el mismo rechazo en bucle infinito.
    final ahora = DateTime.now().toUtc().toIso8601String();
    return consultar(
      'operaciones',
      where:
          "tenant_id = ? AND estado_sincronizacion IN ('PENDIENTE', 'ERROR') "
          "AND (proximo_intento IS NULL OR proximo_intento <= ?)",
      whereArgs: <Object?>[tenantId, ahora],
      orderBy: 'secuencia_local ASC',
      limit: limite,
    );
  }

  /// [EXAMEN-2] B1.4.b: pendientes **excluyendo** los tipos detenidos por un
  /// `ERROR_CRITICO` (RN-017: el tipo queda parado hasta que se regule).
  Future<List<Map<String, Object?>>> listarPendientesExcluyendo(
    List<String> tiposDetenidos, {
    int limite = 50,
  }) async {
    final ahora = DateTime.now().toUtc().toIso8601String();
    final condiciones = <String>[
      'tenant_id = ?',
      "estado_sincronizacion IN ('PENDIENTE', 'ERROR')",
      '(proximo_intento IS NULL OR proximo_intento <= ?)',
    ];
    final argumentos = <Object?>[tenantId, ahora];
    if (tiposDetenidos.isNotEmpty) {
      final marcadores = List<String>.filled(tiposDetenidos.length, '?').join(', ');
      condiciones.add('tipo_operacion NOT IN ($marcadores)');
      argumentos.addAll(tiposDetenidos);
    }
    return consultar(
      'operaciones',
      where: condiciones.join(' AND '),
      whereArgs: argumentos,
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

  /// [BUG-SYNC] Deja en NULL `proximo_intento` de las operaciones indicadas
  /// que sigan PENDIENTE/ERROR (las CONFIRMADA/RECHAZADA definitivas no se
  /// tocan), de modo que `listarPendientes` vuelva a incluirlas de inmediato.
  Future<int> limpiarProximoIntento(List<String> uuids) {
    final marcadores = List<String>.filled(uuids.length, '?').join(', ');
    return db.update(
      'operaciones',
      <String, Object?>{
        'proximo_intento': null,
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      },
      where:
          'uuid_operacion IN ($marcadores) AND tenant_id = ? AND '
          "estado_sincronizacion IN ('PENDIENTE', 'ERROR')",
      whereArgs: <Object?>[...uuids, tenantId],
    );
  }

  Future<int> eliminar(String uuid) =>
      eliminarRegistro('operaciones', 'uuid_operacion', uuid);

  /// [FIX-SYNC] Normaliza las órdenes diferidas encoladas con el payload
  /// antiguo (`acepta_nuevo_total: false`), que el servidor rechazaba en bucle
  /// con PRECIO_DESACTUALIZADO. Reescribe el payload a `true` (como el
  /// frontend web) y reactiva las que quedaron RECHAZADA sólo por ese motivo.
  /// Devuelve los UUID reactivados para limpiar sus conflictos heredados.
  Future<List<String>> normalizarOrdenesDiferidas() async {
    final filas = await consultar(
      'operaciones',
      where:
          "tipo_operacion = 'ORDEN_PAGO_DIFERIDO' AND tenant_id = ? AND "
          "estado_sincronizacion IN ('PENDIENTE', 'ERROR', 'ENVIADA', 'RECHAZADA', 'CONFLICTO')",
      whereArgs: <Object?>[tenantId],
    );
    final reactivadas = <String>[];
    for (final fila in filas) {
      final uuid = fila['uuid_operacion']?.toString() ?? '';
      if (uuid.isEmpty) continue;
      Map<String, Object?> payload;
      try {
        final decodificado = jsonDecode(
          fila['payload_json']?.toString() ?? '{}',
        );
        payload = decodificado is Map
            ? Map<String, Object?>.from(decodificado)
            : <String, Object?>{};
      } catch (_) {
        continue;
      }
      final cambios = <String, Object?>{};
      if (payload['acepta_nuevo_total'] != true) {
        payload['acepta_nuevo_total'] = true;
        cambios['payload_json'] = jsonEncode(payload);
      }
      final estado = fila['estado_sincronizacion']?.toString() ?? '';
      final resultado = fila['resultado_json']?.toString() ?? '';
      final motivo = (fila['ultimo_error']?.toString() ?? '').toLowerCase();
      final rechazadaPorPrecio =
          estado == 'RECHAZADA' &&
          (resultado.contains('requiere_aceptacion') ||
              resultado.contains('PRECIO_DESACTUALIZADO') ||
              motivo.contains('precio central cambió'));
      if (rechazadaPorPrecio) {
        cambios['estado_sincronizacion'] = 'PENDIENTE';
        cambios['proximo_intento'] = null;
        cambios['ultimo_error'] = null;
        reactivadas.add(uuid);
      }
      if (cambios.isEmpty) continue;
      cambios['fecha_actualizacion'] = DateTime.now().toUtc().toIso8601String();
      await db.update(
        'operaciones',
        cambios,
        where: 'uuid_operacion = ? AND tenant_id = ?',
        whereArgs: <Object?>[uuid, tenantId],
      );
    }
    return reactivadas;
  }

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
