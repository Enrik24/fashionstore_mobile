import 'storage_service.dart';

/// [EXAMEN-2] C2.8: resuelve el tenant en cada uso sin congelarlo en main().
///
/// Lee la sesión cacheada o el último tenant offline; si es null devuelve 1
/// (backend sigue siendo autoridad).
class TenantResolver {
  TenantResolver(this._storage);
  final StorageService _storage;

  int resolver() =>
      _storage.getUser()?.tenantId ?? _storage.readLastTenant() ?? 1;

  Future<void> guardar(int tenantId) => _storage.saveLastTenant(tenantId);
}
