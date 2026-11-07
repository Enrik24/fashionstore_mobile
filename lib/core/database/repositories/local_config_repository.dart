import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../models/offline_config_model.dart';
import '../local_database_service.dart';

/// [EXAMEN-2] Repositorio local de configuración offline del tenant.
class LocalConfigRepository {
  LocalConfigRepository(this._database);

  final LocalDatabaseService _database;

  Future<void> guardar(OfflineConfigModel config) async {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    await db.insert('configuracion', <String, Object?>{
      'clave': 'actual',
      'tenant_id': config.tenantId,
      'valor': jsonEncode(config.toJson()),
      'moneda': config.moneda,
      'impuestos': null,
      'clave_publica_stripe': config.clavePublicaStripe,
      'banderas_plan': jsonEncode(<String, bool>{
        'descarga_automatica': config.descargaAutomatica,
        'incluir_clientes': config.incluirClientes,
        'habilitar_carrito_offline': config.habilitarCarritoOffline,
      }),
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<OfflineConfigModel?> leer(int tenantId) async {
    final db = _database.database;
    if (db == null) return null;
    final filas = await db.query(
      'configuracion',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object>['actual', tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    final raw = filas.first['valor']?.toString();
    if (raw == null || raw.isEmpty) return null;
    try {
      return OfflineConfigModel.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
