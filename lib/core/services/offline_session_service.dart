import '../../config/config.dart';
import '../../config/constants.dart';
import '../models/api_response.dart';
import 'device_service.dart';
import 'local_crypto_service.dart';
import 'storage_service.dart';
import '../database/local_database_service.dart';
import '../database/repositories/local_config_repository.dart';
import '../database/repositories/local_permissions_repository.dart';
import '../models/offline_config_model.dart';

/// [EXAMEN-2] CU17: PIN local, token offline, vigencia e intentos.
class OfflineSessionService {
  OfflineSessionService({
    required StorageService storageService,
    required LocalCryptoService cryptoService,
    required DeviceService deviceService,
    required OfflineApiClient client,
    LocalConfigRepository? configRepository,
    LocalPermissionsRepository? permissionsRepository,
    LocalDatabaseService? localDatabase,
  }) : _storage = storageService,
       _crypto = cryptoService,
       _devices = deviceService,
       _client = client,
       _configRepository = configRepository,
       _permissionsRepository = permissionsRepository,
       _localDatabase = localDatabase;

  final StorageService _storage;
  final LocalCryptoService _crypto;
  final DeviceService _devices;
  final OfflineApiClient _client;
  final LocalConfigRepository? _configRepository;
  final LocalPermissionsRepository? _permissionsRepository;
  // [EXAMEN-2] C1.2: borrado por tenant al cerrar sesión offline.
  final LocalDatabaseService? _localDatabase;

  static int get maxIntentos => AppConfig.pinIntentosMaximos;

  bool _pinConfigurado = false;
  int _intentos = 0;
  DateTime? _expiraEn;
  bool _inicializado = false;

  bool get pinConfigurado => _pinConfigurado;
  int get intentosRestantes => (maxIntentos - _intentos).clamp(0, maxIntentos);
  DateTime? get expiraEn => _expiraEn;

  /// Carga el estado seguro de la sesión antes de usar la interfaz.
  Future<void> initialize() async {
    if (_inicializado) return;
    _pinConfigurado =
        (await _storage.readPinHash() ?? '').isNotEmpty &&
        (await _storage.readPinSalt() ?? '').isNotEmpty;
    _intentos = await _storage.readOfflineAttempts();
    _expiraEn = await _storage.readOfflineSessionExpiry();
    _inicializado = true;
  }

  Duration get tiempoRestante {
    final expira = _expiraEn;
    if (expira == null) return Duration.zero;
    final restante = expira.difference(DateTime.now().toUtc());
    return restante.isNegative ? Duration.zero : restante;
  }

  bool get haySesionValida =>
      pinConfigurado && expiraEn != null && tiempoRestante > Duration.zero;

  // [EXAMEN-2] C1.2: sesión guardada pero vencida => solo consulta.
  bool get sesionVencida =>
      pinConfigurado && expiraEn != null && tiempoRestante == Duration.zero;

  Future<bool> configurarPin({
    required String pin,
    required String contrasenaActual,
  }) async {
    _validarPin(pin);
    await _client.post(
      AppConstants.epOfflineSesionPin,
      data: <String, dynamic>{
        'contrasena_actual': contrasenaActual,
        'pin': pin,
      },
    );
    final salt = _crypto.generarSalt();
    final hash = _crypto.hashearPin(pin, salt);
    await _storage.savePinSalt(salt);
    await _storage.savePinHash(hash);
    await _storage.saveOfflineAttempts(0);
    _pinConfigurado = true;
    _intentos = 0;
    return true;
  }

  /// Valida el PIN localmente. Si hay red, también exige un token vigente al backend.
  Future<bool> iniciarSesionOffline(String pin) async {
    if (!pinConfigurado) {
      throw ApiException(
        message: 'Configura tu PIN para poder operar sin conexión.',
      );
    }
    if (intentosRestantes <= 0) {
      throw ApiException(
        message:
            'Superaste los intentos permitidos. Debes iniciar sesión con conexión.',
      );
    }
    final hash = await _storage.readPinHash() ?? '';
    final salt = await _storage.readPinSalt() ?? '';
    if (!_crypto.verificarPin(pin, hash, salt)) {
      final intentos = await _storage.readOfflineAttempts();
      await _storage.saveOfflineAttempts(intentos + 1);
      _intentos = intentos + 1;
      if (intentosRestantes <= 0) {
        throw ApiException(
          message:
              'Superaste los intentos permitidos. Debes iniciar sesión con conexión.',
        );
      }
      throw ApiException(
        message: 'PIN incorrecto. Te quedan $intentosRestantes intentos.',
      );
    }
    await _storage.saveOfflineAttempts(0);
    _intentos = 0;
    // [EXAMEN-2] C1.2: PIN correcto pero sesión vencida => solo consulta (CU17 §12.1).
    // Si nunca tuvo expiración (null), se permite el primer acceso offline para
    // no romper flujo de alta; el enforcement real aplica tras iniciarSesiónRemota.
    if (expiraEn != null && !haySesionValida) {
      throw ApiException(
        message:
            'La sesión offline venció. Puedes consultar el catálogo, pero necesitas conexión para operar.',
      );
    }
    return true;
  }

  /// Canjea el PIN validado por un token offline del backend.
  Future<Map<String, dynamic>> iniciarSesionRemota(String pin) async {
    await iniciarSesionOffline(pin);
    final data = await _client.post(
      AppConstants.epOfflineSesionIniciar,
      data: <String, dynamic>{
        'dispositivo_id': await _devices.dispositivoId,
        'pin': pin,
        'plataforma': await _devices.plataforma,
      },
    );
    final respuesta = _map(data);
    final token = respuesta['token_offline']?.toString() ?? '';
    final expira = DateTime.tryParse(respuesta['expira_en']?.toString() ?? '');
    if (token.isEmpty || expira == null) {
      throw ApiException(
        message: 'El servidor no devolvió una sesión offline válida.',
      );
    }
    await _storage.saveOfflineToken(token);
    await _storage.saveOfflineSessionExpiry(expira);
    _expiraEn = expira;
    final tenantId = (respuesta['tenant_id'] as num?)?.toInt() ?? 0;
    final usuarioId = (respuesta['usuario_id'] as num?)?.toInt() ?? 0;
    await _storage.saveLastTenant(tenantId);
    final roles = (respuesta['roles'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final permisos = (respuesta['permisos'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    await _permissionsRepository?.guardar(
      tenantId: tenantId,
      usuarioId: usuarioId,
      roles: roles,
      permisos: permisos,
    );
    final configJson = respuesta['configuracion'];
    if (configJson is Map<String, dynamic>) {
      await _configRepository?.guardar(OfflineConfigModel.fromJson(configJson));
    }
    return respuesta;
  }

  Future<bool> renovarToken() async {
    final token = await _storage.readOfflineToken();
    if (token == null || token.isEmpty) return false;
    try {
      final data = await _client.post(
        AppConstants.epOfflineSesionRenovar,
        data: <String, dynamic>{'token_offline': token},
      );
      final respuesta = _map(data);
      final nuevo = respuesta['token_offline']?.toString();
      final expira = DateTime.tryParse(
        respuesta['expira_en']?.toString() ?? '',
      );
      if (nuevo != null && nuevo.isNotEmpty) {
        await _storage.saveOfflineToken(nuevo);
      }
      if (expira != null) {
        await _storage.saveOfflineSessionExpiry(expira);
        _expiraEn = expira;
      }
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<void> eliminarPin() async {
    await _client.delete(AppConstants.epOfflineSesionPin);
    await _storage.savePinHash('');
    await _storage.savePinSalt('');
    await _storage.saveOfflineToken('');
    await _storage.saveOfflineSessionExpiry(
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    await _storage.saveOfflineAttempts(0);
    _pinConfigurado = false;
    _intentos = 0;
    _expiraEn = null;
  }

  Future<void> cerrarSesionOffline({bool remoto = true}) async {
    if (remoto) {
      try {
        await _client.post(AppConstants.epOfflineSesionCerrar);
      } catch (_) {}
    }
    // [EXAMEN-2] C1.2: cerrar sesión borra datos del tenant (RN-019).
    final tenantId = _storage.readLastTenant();
    if (tenantId != null) {
      try {
        await _localDatabase?.borrarPorTenant(tenantId);
      } catch (_) {}
    }
    await _storage.saveOfflineToken('');
    await _storage.saveOfflineSessionExpiry(
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    await _storage.saveOfflineAttempts(0);
    _expiraEn = null;
  }

  Future<Map<String, dynamic>> estadoSesion() async {
    try {
      return _map(await _client.get(AppConstants.epOfflineSesionEstado));
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return <String, dynamic>{
          'usuario_id': 0,
          'tenant_id': _storage.readLastTenant() ?? 0,
          'dispositivo_id': await _storage.readDeviceId(),
          'pin_configurado': pinConfigurado,
          'dispositivo_activo': true,
          'intentos_restantes': intentosRestantes,
          'max_horas_sesion_offline': 12,
        };
      }
      rethrow;
    }
  }

  void _validarPin(String pin) {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin) ||
        pin.length < AppConfig.pinLongitudMinima) {
      throw ApiException(message: 'El PIN debe contener entre 6 y 12 dígitos.');
    }
  }

  Map<String, dynamic> _map(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw ApiException(message: 'Respuesta inválida del servidor.');
  }
}
