import '../../config/constants.dart';
import '../models/user_model.dart';
import 'api_service.dart';
import 'offline_session_service.dart';
import '../database/local_database_service.dart';

class AuthService {
  final ApiService apiService;
  final OfflineSessionService? _offlineSessionService;
  final LocalDatabaseService? _localDatabaseService;

  AuthService({
    required this.apiService,
    OfflineSessionService? offlineSessionService,
    LocalDatabaseService? localDatabaseService,
  }) : _offlineSessionService = offlineSessionService,
       _localDatabaseService = localDatabaseService;

  /// [EXAMEN-2] CU17: configura, inicia, renueva y cierra la sesión offline.
  Future<bool> configurarPin({
    required String pin,
    required String contrasenaActual,
  }) async {
    final servicio = _offlineSessionService;
    if (servicio == null) {
      throw StateError('El servicio offline no está configurado.');
    }
    return servicio.configurarPin(pin: pin, contrasenaActual: contrasenaActual);
  }

  Future<void> eliminarPin() async {
    await _offlineSessionService?.eliminarPin();
  }

  Future<bool> iniciarSesionOffline(String pin) async {
    final servicio = _offlineSessionService;
    if (servicio == null) return false;
    return servicio.iniciarSesionOffline(pin);
  }

  // [EXAMEN-2] C1.2: dueños reales de la vigencia offline.
  bool get haySesionValidaOffline => _offlineSessionService?.haySesionValida ?? false;
  bool get sesionVencidaOffline => _offlineSessionService?.sesionVencida ?? false;
  Duration get tiempoRestanteOffline => _offlineSessionService?.tiempoRestante ?? Duration.zero;
  int get intentosRestantesOffline => _offlineSessionService?.intentosRestantes ?? 5;

  Future<bool> renovarSesionOffline() async {
    return await _offlineSessionService?.renovarToken() ?? false;
  }

  Future<void> cerrarSesionOffline() async {
    await _offlineSessionService?.cerrarSesionOffline();
  }

  Future<Map<String, dynamic>> estadoSesionOffline() async {
    return await _offlineSessionService?.estadoSesion() ?? <String, dynamic>{};
  }

  Future<void> borrarDatosDelTenant(int tenantId) async {
    await _localDatabaseService?.borrarPorTenant(tenantId);
  }

  /// Inicia sesión con correo y contraseña.
  /// POST /api/v1/auth/login
  Future<TokenResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await apiService.dio.post(
        AppConstants.epLogin,
        data: {'correo': email.trim().toLowerCase(), 'contrasena': password},
      );
      return TokenResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw apiService.handleError(e);
    }
  }

  /// Registra un nuevo cliente.
  /// POST /api/v1/auth/register
  Future<TokenResponse> register({
    required String nombre,
    required String apellido,
    required String correo,
    required String telefono,
    required String nitCi,
    String? direccionEnvio,
    required String contrasena,
  }) async {
    try {
      final response = await apiService.dio.post(
        AppConstants.epRegister,
        data: {
          'nombre': nombre.trim(),
          'apellido': apellido.trim(),
          'correo': correo.trim().toLowerCase(),
          'telefono': telefono.trim(),
          'nit_ci': nitCi.trim(),
          'direccion_envio':
              (direccionEnvio != null && direccionEnvio.trim().isNotEmpty)
              ? direccionEnvio.trim()
              : null,
          'contrasena': contrasena,
        },
      );
      return TokenResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw apiService.handleError(e);
    }
  }

  /// Obtiene los datos del usuario autenticado actual.
  /// GET /api/v1/auth/me
  Future<UserModel> getMe() async {
    try {
      final response = await apiService.dio.get(AppConstants.epMe);
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw apiService.handleError(e);
    }
  }

  /// Obtiene el perfil detallado del cliente actual.
  /// GET /api/v1/cliente/perfil
  Future<ClienteProfile> getClientProfile() async {
    try {
      final response = await apiService.dio.get(AppConstants.epClientProfile);
      return ClienteProfile.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw apiService.handleError(e);
    }
  }

  /// Actualiza los datos del perfil del cliente (nombre, apellido, teléfono, dirección).
  /// PUT /api/v1/cliente/perfil
  Future<ClienteProfile> updateProfile({
    String? nombre,
    String? apellido,
    String? telefono,
    String? direccionEnvio,
  }) async {
    try {
      final response = await apiService.dio.put(
        AppConstants.epClientProfile,
        data: {
          if (nombre != null) 'nombre': nombre.trim(),
          if (apellido != null) 'apellido': apellido.trim(),
          if (telefono != null) 'telefono': telefono.trim(),
          if (direccionEnvio != null) 'direccion_envio': direccionEnvio.trim(),
        },
      );
      return ClienteProfile.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw apiService.handleError(e);
    }
  }

  /// Actualiza la dirección de envío del cliente.
  /// PUT /api/v1/cliente/direccion
  Future<void> updateAddress(String direccion) async {
    try {
      await apiService.dio.put(
        AppConstants.epClientDireccion,
        queryParameters: {'direccion': direccion.trim()},
      );
    } catch (e) {
      throw apiService.handleError(e);
    }
  }

  /// Cierra la sesión en el servidor.
  /// POST /api/v1/auth/logout
  Future<void> logout() async {
    try {
      await apiService.dio.post(AppConstants.epLogout);
    } catch (_) {
      // Ignored if token expired or offline
    }
  }

  /// Cambia la contraseña del usuario autenticado.
  /// POST /api/v1/auth/change-password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await apiService.dio.post(
        AppConstants.epChangePassword,
        data: {
          'contrasena_actual': currentPassword,
          'contrasena_nueva': newPassword,
        },
      );
    } catch (e) {
      throw apiService.handleError(e);
    }
  }
}
