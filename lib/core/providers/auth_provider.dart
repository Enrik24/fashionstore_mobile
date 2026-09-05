import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/api_response.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

enum AuthStatus {
  initial,
  authenticating,
  authenticated,
  unauthenticated,
  error,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final StorageService _storageService;

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  ClienteProfile? _clienteProfile;
  String? _errorMessage;
  bool _isLoading = false;

  AuthProvider({
    required AuthService authService,
    required StorageService storageService,
  })  : _authService = authService,
        _storageService = storageService;

  // Getters
  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated && _currentUser != null;
  bool get isLoading => _isLoading;
  UserModel? get currentUser => _currentUser;
  ClienteProfile? get clienteProfile => _clienteProfile;
  String? get errorMessage => _errorMessage;
  String? get rememberedEmail => _storageService.getRememberedEmail();

  /// Verifica el estado de autenticación al arrancar la app.
  Future<void> checkAuthStatus() async {
    _status = AuthStatus.initial;
    notifyListeners();

    try {
      final token = await _storageService.getAccessToken();
      if (token == null || token.isEmpty) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }

      // Try reading cached user first for faster UX
      _currentUser = _storageService.getUser();
      _clienteProfile = _storageService.getClientProfile();

      // Fetch fresh profile from API
      final user = await _authService.getMe();
      _currentUser = user;
      await _storageService.saveUser(user);

      try {
        final profile = await _authService.getClientProfile();
        _clienteProfile = profile;
        await _storageService.saveClientProfile(profile);
      } catch (_) {
        // Not a client or profile not found
      }

      _status = AuthStatus.authenticated;
    } catch (e) {
      // If token expired or network failed
      final cachedUser = _storageService.getUser();
      if (cachedUser != null) {
        // Keep offline user if available
        _currentUser = cachedUser;
        _clienteProfile = _storageService.getClientProfile();
        _status = AuthStatus.authenticated;
      } else {
        await _storageService.clearAllSession();
        _status = AuthStatus.unauthenticated;
      }
    } finally {
      notifyListeners();
    }
  }

  /// Inicia sesión con correo y contraseña.
  Future<bool> login({
    required String email,
    required String password,
    bool rememberEmail = false,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _status = AuthStatus.authenticating;
    notifyListeners();

    try {
      if (rememberEmail) {
        await _storageService.saveRememberedEmail(email);
      }

      final tokens = await _authService.login(email: email, password: password);
      await _storageService.saveTokens(tokens);

      final user = await _authService.getMe();
      _currentUser = user;
      await _storageService.saveUser(user);

      try {
        final profile = await _authService.getClientProfile();
        _clienteProfile = profile;
        await _storageService.saveClientProfile(profile);
      } catch (_) {}

      _status = AuthStatus.authenticated;
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e is ApiException ? e.message : e.toString();
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Registra un nuevo cliente y autentica automáticamente.
  Future<bool> register({
    required String nombre,
    required String apellido,
    required String correo,
    required String telefono,
    required String nitCi,
    String? direccionEnvio,
    required String contrasena,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _status = AuthStatus.authenticating;
    notifyListeners();

    try {
      final tokens = await _authService.register(
        nombre: nombre,
        apellido: apellido,
        correo: correo,
        telefono: telefono,
        nitCi: nitCi,
        direccionEnvio: direccionEnvio,
        contrasena: contrasena,
      );
      await _storageService.saveTokens(tokens);

      final user = await _authService.getMe();
      _currentUser = user;
      await _storageService.saveUser(user);

      try {
        final profile = await _authService.getClientProfile();
        _clienteProfile = profile;
        await _storageService.saveClientProfile(profile);
      } catch (_) {}

      _status = AuthStatus.authenticated;
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e is ApiException ? e.message : e.toString();
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Cambia la contraseña del usuario.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      await _authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e is ApiException ? e.message : e.toString();
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Cierra la sesión y limpia el almacenamiento.
  Future<void> logout() async {
    _setLoading(true);
    try {
      await _authService.logout();
    } catch (_) {}
    await _storageService.clearAllSession();
    _currentUser = null;
    _clienteProfile = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    _setLoading(false);
    notifyListeners();
  }

  /// Recarga los datos del perfil.
  Future<void> refreshProfile() async {
    try {
      final user = await _authService.getMe();
      _currentUser = user;
      await _storageService.saveUser(user);

      final profile = await _authService.getClientProfile();
      _clienteProfile = profile;
      await _storageService.saveClientProfile(profile);
      notifyListeners();
    } catch (_) {}
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
  }
}
