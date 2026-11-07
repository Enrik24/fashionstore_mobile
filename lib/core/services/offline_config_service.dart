import '../../config/constants.dart';
import '../database/repositories/local_config_repository.dart';
import '../models/api_response.dart';
import '../models/offline_config_model.dart';
import 'device_service.dart';

/// [EXAMEN-2] CU17: configuración offline remota con respaldo local.
class OfflineConfigService {
  OfflineConfigService({
    required LocalConfigRepository repository,
    required OfflineApiClient client,
  }) : _repository = repository,
       _client = client;

  final LocalConfigRepository _repository;
  final OfflineApiClient _client;

  Future<OfflineConfigModel> obtenerConfiguracion(int tenantId) async {
    try {
      final data = await _client.get(AppConstants.epOfflineConfiguracion);
      if (data is Map<String, dynamic>) {
        final config = OfflineConfigModel.fromJson(data);
        await _repository.guardar(config);
        return config;
      }
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
    final local = await _repository.leer(tenantId);
    if (local != null) return local;
    return OfflineConfigModel(tenantId: tenantId);
  }

  Future<OfflineConfigModel> refrescar(int tenantId) =>
      obtenerConfiguracion(tenantId);

  bool habilitarCarritoOffline(OfflineConfigModel config) =>
      config.habilitarCarritoOffline;

  int plazoSesionHoras(OfflineConfigModel config) =>
      config.maxHorasSesionOffline;

  int diasVigenciaOrden(OfflineConfigModel config) =>
      config.maxDiasOrdenPendiente;

  String? clavePublicaStripe(OfflineConfigModel config) =>
      config.clavePublicaStripe;
}
