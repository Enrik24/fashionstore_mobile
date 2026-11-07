import '../../config/config.dart';
import '../database/local_database_service.dart';

/// [EXAMEN-2] Cuota, priorización y limpieza de datos locales (RNF-14).
class StorageQuotaService {
  StorageQuotaService({
    required LocalDatabaseService database,
    required int tenantId,
    int? limiteBytes,
  }) : _database = database,
       _tenantId = tenantId,
       // [EXAMEN-2] C2.3: límite desde AppConfig (§15.1).
       _limiteBytes = limiteBytes ?? AppConfig.offlineEspacioMaximoMb * 1024 * 1024;

  final LocalDatabaseService _database;
  final int _tenantId;
  final int _limiteBytes;

  int get limiteBytes => _limiteBytes;

  Future<int> espacioUsado() => _database.espacioUsado();

  // [EXAMEN-2] C2.3: respeta el límite inyectado (por defecto 200 MB de AppConfig).
  Future<int> espacioDisponible() async {
    final usado = await espacioUsado();
    final disponible = _limiteBytes - usado;
    return disponible < 0 ? 0 : disponible;
  }

  Future<bool> puedeDescargar(int estimadoBytes) async {
    final disponible = await espacioDisponible();
    return disponible >= estimadoBytes;
  }

  Future<List<Map<String, Object?>>> priorizarDescarga(
    List<Map<String, Object?>> productos,
  ) async {
    final priorizados = [...productos];
    priorizados.sort((a, b) {
      final ventaA = (a['ventas'] as num?)?.toInt() ?? 0;
      final ventaB = (b['ventas'] as num?)?.toInt() ?? 0;
      final stockA = (a['stock'] as num?)?.toInt() ?? 0;
      final stockB = (b['stock'] as num?)?.toInt() ?? 0;
      final scoreA = ventaA * 10 + (stockA > 0 ? 5 : 0);
      final scoreB = ventaB * 10 + (stockB > 0 ? 5 : 0);
      return scoreB.compareTo(scoreA);
    });
    return priorizados;
  }

  Future<int> limpiarSincronizados({int dias = 30}) async {
    final db = _database.database;
    if (db == null) return 0;
    final limite = DateTime.now()
        .subtract(Duration(days: dias))
        .toUtc()
        .toIso8601String();
    var eliminados = 0;
    eliminados += await db.delete(
      'operaciones',
      where:
          "tenant_id = ? AND estado_sincronizacion IN "
          "('CONFIRMADA', 'DUPLICADA') AND fecha_confirmacion < ?",
      whereArgs: <Object?>[_tenantId, limite],
    );
    eliminados += await db.delete(
      'comprobantes',
      where:
          "tenant_id = ? AND es_temporal = 1 AND "
          "fecha_actualizacion < ?",
      whereArgs: <Object?>[_tenantId, limite],
    );
    eliminados += await db.delete(
      'bitacora_local',
      where: 'tenant_id = ? AND fecha < ?',
      whereArgs: <Object?>[_tenantId, limite],
    );
    return eliminados;
  }

  Future<int> limpiarObsoletos() async {
    final db = _database.database;
    if (db == null) return 0;
    return db.delete(
      'conflictos',
      where: 'tenant_id = ? AND resuelto = 1',
      whereArgs: <Object?>[_tenantId],
    );
  }

  // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): limpia v3/v4 sincronizadas.
  // Nunca borra devoluciones pendientes ni compensaciones sin confirmar.
  Future<int> limpiarDevolucionesSincronizadas({int dias = 30}) async {
    final db = _database.database;
    if (db == null) return 0;
    final limite = DateTime.now()
        .subtract(Duration(days: dias))
        .toUtc()
        .toIso8601String();
    var eliminados = 0;
    eliminados += await db.delete(
      'devoluciones_locales',
      where:
          "tenant_id = ? AND estado NOT IN "
          "('PENDIENTE_SINCRONIZACION', 'PENDIENTE') AND "
          "fecha_actualizacion < ?",
      whereArgs: <Object?>[_tenantId, limite],
    );
    eliminados += await db.delete(
      'compensaciones',
      where:
          "tenant_id = ? AND estado = 'COMPLETADA' AND "
          "COALESCE(fecha_completado, fecha_actualizacion) < ?",
      whereArgs: <Object?>[_tenantId, limite],
    );
    return eliminados;
  }

  List<String> datosIntocables() => const [
    'operaciones PENDIENTES/ENVIADAS',
    'pagos sin confirmar',
    'carritos activos',
    'ventas pendientes de sincronización',
    // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): pendientes y compensaciones por
    // confirmar nunca se borran en la limpieza.
    'devoluciones PENDIENTE_SINCRONIZACION',
    'compensaciones sin confirmar (PENDIENTE/EN_PROCESO)',
  ];
}
