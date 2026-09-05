import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import '../models/user_model.dart';

class StorageService {
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  StorageService({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences prefs,
  })  : _secureStorage = secureStorage,
        _prefs = prefs;

  static Future<StorageService> init() async {
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    final prefs = await SharedPreferences.getInstance();
    return StorageService(secureStorage: secureStorage, prefs: prefs);
  }

  // Token Management
  Future<void> saveTokens(TokenResponse tokens) async {
    await _secureStorage.write(key: AppConstants.keyAccessToken, value: tokens.accessToken);
    await _secureStorage.write(key: AppConstants.keyRefreshToken, value: tokens.refreshToken);
  }

  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: AppConstants.keyAccessToken);
  }

  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: AppConstants.keyRefreshToken);
  }

  Future<void> clearTokens() async {
    await _secureStorage.delete(key: AppConstants.keyAccessToken);
    await _secureStorage.delete(key: AppConstants.keyRefreshToken);
  }

  // User Data Cache
  Future<void> saveUser(UserModel user) async {
    final raw = jsonEncode(user.toJson());
    await _prefs.setString(AppConstants.keyUserData, raw);
  }

  UserModel? getUser() {
    final raw = _prefs.getString(AppConstants.keyUserData);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearUser() async {
    await _prefs.remove(AppConstants.keyUserData);
  }

  // Client Profile Cache
  Future<void> saveClientProfile(ClienteProfile client) async {
    final raw = jsonEncode(client.toJson());
    await _prefs.setString(AppConstants.keyClientData, raw);
  }

  ClienteProfile? getClientProfile() {
    final raw = _prefs.getString(AppConstants.keyClientData);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ClienteProfile.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearClientProfile() async {
    await _prefs.remove(AppConstants.keyClientData);
  }

  // Remember Email
  Future<void> saveRememberedEmail(String email) async {
    await _prefs.setString(AppConstants.keyRememberEmail, email);
  }

  String? getRememberedEmail() {
    return _prefs.getString(AppConstants.keyRememberEmail);
  }

  // Full Session Clear
  Future<void> clearAllSession() async {
    await clearTokens();
    await clearUser();
    await clearClientProfile();
  }
}
