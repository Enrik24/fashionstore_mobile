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
      // [EXAMEN-2] B1.1.a: la tasa de impuestos vigente ya no se descarta;
      // antes se escribía `null` y los totales offline ignoraban el impuesto.
      'impuestos': jsonEncode(<String, Object?>{
        'tasa_total': config.tasaImpuestos,
        'moneda': config.moneda,
      }),
      'clave_publica_stripe': config.clavePublicaStripe,
      'banderas_plan': jsonEncode(<String, bool>{
        'descarga_automatica': config.descargaAutomatica,
        'incluir_clientes': config.incluirClientes,
        'habilitar_carrito_offline': config.habilitarCarritoOffline,
      }),
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// [EXAMEN-2] B1.1.a: tasa de impuestos vigente guardada localmente.
  Future<double> leerTasaImpuestos(int tenantId) async {
    final db = _database.database;
    if (db == null) return 0;
    final filas = await db.query(
      'configuracion',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object>['actual', tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return 0;
    final raw = filas.first['impuestos']?.toString();
    if (raw == null || raw.isEmpty) return 0;
    try {
      final mapa = jsonDecode(raw);
      if (mapa is Map) return (mapa['tasa_total'] as num?)?.toDouble() ?? 0;
    } catch (_) {}
    return 0;
  }

  /// [EXAMEN-2] B1.1.b: clave **pública** de Stripe (RNF-15: nunca la secreta).
  Future<String?> leerClavePublicaStripe(int tenantId) async {
    final db = _database.database;
    if (db == null) return null;
    final filas = await db.query(
      'configuracion',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object>['actual', tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    final valor = filas.first['clave_publica_stripe']?.toString();
    return (valor == null || valor.isEmpty) ? null : valor;
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
