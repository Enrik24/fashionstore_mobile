import '../database/local_database_service.dart';
import 'storage_service.dart';

/// [EXAMEN-2] CU07/CU13/CU18: resuelve la sucursal y el cajero de la sesión
/// para las operaciones POS offline, sin sucursalId/cajeroId fijos.
///
/// - Sucursal: primero la elegida por el usuario (persistida); si no existe,
///   la primera del paquete offline descargado (tabla `sucursales`).
/// - Cajero: el usuario autenticado en la sesión.
class PosSesionService {
  PosSesionService({
    required LocalDatabaseService database,
    required StorageService storage,
    required int tenantId,
  }) : _database = database,
       _storage = storage,
       _tenantId = tenantId;

  final LocalDatabaseService _database;
  final StorageService _storage;
  final int _tenantId;

  int? _sucursalMemoria;

  /// Sucursal vigente. Persiste el respaldo la primera vez que resuelve.
  Future<int> resolverSucursalId() async {
    final conocida =
        _sucursalMemoria ??
        _storage.readPosSucursalId();
    if (conocida != null && conocida > 0) return conocida;
    final db = _database.database;
    if (db != null) {
      try {
        final filas = await db.query(
          'sucursales',
          where: 'tenant_id = ?',
          whereArgs: <Object?>[_tenantId],
          orderBy: 'id',
          limit: 1,
        );
        final id = (filas.isEmpty ? null : filas.first['id'] as num?)
            ?.toInt();
        if (id != null && id > 0) {
          await guardarSucursal(id);
          return id;
        }
        // [EXAMEN-2] CU05: si la tabla de sucursales sigue vacía (el paquete
        // no las incluye), usa la sucursal objetivo guardada al descargar.
        final meta = await db.query(
          'meta',
          where: 'clave = ? AND tenant_id = ?',
          whereArgs: <Object?>['paquete_sucursal_id', _tenantId],
          limit: 1,
        );
        final idMeta = int.tryParse(
          (meta.isEmpty ? null : meta.first['valor'])?.toString() ?? '',
        );
        if (idMeta != null && idMeta > 0) {
          await guardarSucursal(idMeta);
          return idMeta;
        }
      } catch (_) {
        // La tabla puede no existir si aún no hubo descarga (CU05).
      }
    }
    return _storage.readPosSucursalId() ?? 0;
  }

  /// Fija la sucursal de la sesión y la persiste.
  Future<void> guardarSucursal(int sucursalId) async {
    if (sucursalId <= 0) return;
    _sucursalMemoria = sucursalId;
    await _storage.savePosSucursalId(sucursalId);
  }

  /// Cajero actual: el usuario de la sesión (permiso CAJERO/GESTOR).
  int get cajeroId => _storage.getUser()?.id ?? 0;
}
