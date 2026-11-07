import 'package:sqflite_sqlcipher/sqflite.dart';

import 'local_schema.dart';

/// [EXAMEN-2] Migraciones incrementales e idempotentes de la base local.
class LocalMigrations {
  const LocalMigrations._();

  static Future<void> migrar(DatabaseExecutor db, int versionActual) async {
    var version = versionActual;
    if (version < 1) {
      await LocalSchema.crearV1(db);
      await _registrarVersion(db, 1);
      version = 1;
    }
    // [EXAMEN-2] La v2 conserva la v1 y crea todas las tablas e índices de
    // catálogo, operación offline, pagos, conflictos y comprobantes.
    if (version < 2) {
      await LocalSchema.crearV2(db);
      await _registrarVersion(db, 2);
      version = 2;
    }
    // [EXAMEN-2] Fase 3 (CU13/CU18): v3 no borra v2 ni toca datos previos.
    if (version < 3) {
      await LocalSchema.crearV3(db);
      await _registrarVersion(db, 3);
      version = 3;
    }
    // [EXAMEN-2] Fase 3 (CU19): v4 con tipo/numero_reposicion + compensaciones.
    if (version < 4) {
      await LocalSchema.crearV4(db);
      await _registrarVersion(db, 4);
    }
  }

  static Future<void> _registrarVersion(
    DatabaseExecutor db,
    int version,
  ) async {
    final ahora = DateTime.now().toUtc().toIso8601String();
    await db.insert('meta', <String, Object?>{
      'clave': LocalSchema.schemaMetaKey,
      'tenant_id': LocalSchema.reservedGlobalTenantId,
      'secuencia_local': 0,
      'version_esquema': version,
      'fecha_actualizacion': ahora,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('bitacora_local', <String, Object?>{
      'tenant_id': LocalSchema.reservedGlobalTenantId,
      'fecha': ahora,
      'tipo': 'MIGRACION',
      'mensaje': 'Esquema local actualizado a v$version',
      'datos': null,
    });
  }
}
