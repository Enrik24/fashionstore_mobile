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
  }) : _secureStorage = secureStorage,
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
    await _secureStorage.write(
      key: AppConstants.keyAccessToken,
      value: tokens.accessToken,
    );
    await _secureStorage.write(
      key: AppConstants.keyRefreshToken,
      value: tokens.refreshToken,
    );
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

  // [EXAMEN-2] Estado seguro del modo offline (CU17).
  Future<void> saveDatabaseKey(String value) async {
    await _secureStorage.write(key: _keyDatabaseKey, value: value);
  }

  Future<String?> readDatabaseKey() async {
    return _secureStorage.read(key: _keyDatabaseKey);
  }

  Future<void> savePinHash(String value) async {
    await _secureStorage.write(key: _keyPinHash, value: value);
  }

  Future<String?> readPinHash() async {
    return _secureStorage.read(key: _keyPinHash);
  }

  Future<void> savePinSalt(String value) async {
    await _secureStorage.write(key: _keyPinSalt, value: value);
  }

  Future<String?> readPinSalt() async {
    return _secureStorage.read(key: _keyPinSalt);
  }

  Future<void> saveOfflineToken(String value) async {
    await _secureStorage.write(key: _keyOfflineToken, value: value);
  }

  Future<String?> readOfflineToken() async {
    return _secureStorage.read(key: _keyOfflineToken);
  }

  // [EXAMEN-2] Vigencia e intentos de la sesión offline (CU17).
  Future<void> saveOfflineSessionExpiry(DateTime value) async {
    await _secureStorage.write(
      key: _keyOfflineExpiry,
      value: value.toUtc().toIso8601String(),
    );
  }

  Future<DateTime?> readOfflineSessionExpiry() async {
    final raw = await _secureStorage.read(key: _keyOfflineExpiry);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> saveOfflineAttempts(int value) async {
    await _secureStorage.write(
      key: _keyOfflineAttempts,
      value: value.toString(),
    );
  }

  Future<int> readOfflineAttempts() async {
    final raw = await _secureStorage.read(key: _keyOfflineAttempts);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> saveDeviceId(String value) async {
    await _secureStorage.write(key: _keyDeviceId, value: value);
  }

  Future<String?> readDeviceId() async {
    return _secureStorage.read(key: _keyDeviceId);
  }

  Future<void> saveLastTenant(int value) async {
    await _prefs.setInt(_keyLastTenant, value);
  }

  int? readLastTenant() => _prefs.getInt(_keyLastTenant);

  Future<void> saveDownloadStamp(DateTime value) async {
    await _prefs.setString(_keyDownloadStamp, value.toIso8601String());
  }

  DateTime? readDownloadStamp() {
    final raw = _prefs.getString(_keyDownloadStamp);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  // [EXAMEN-2] Limpia secretos y estado local sin tocar tokens online.
  Future<void> clearOfflineMode() async {
    await _secureStorage.delete(key: _keyDatabaseKey);
    await _secureStorage.delete(key: _keyPinHash);
    await _secureStorage.delete(key: _keyPinSalt);
    await _secureStorage.delete(key: _keyOfflineToken);
    await _secureStorage.delete(key: _keyOfflineExpiry);
    await _secureStorage.delete(key: _keyOfflineAttempts);
    await _secureStorage.delete(key: _keyDeviceId);
    await _prefs.remove(_keyLastTenant);
    await _prefs.remove(_keyDownloadStamp);
  }

  static const String _keyDatabaseKey = 'fs_offline_database_key';
  static const String _keyPinHash = 'fs_offline_pin_hash';
  static const String _keyPinSalt = 'fs_offline_pin_salt';
  static const String _keyOfflineToken = 'fs_offline_token';
  static const String _keyOfflineExpiry = 'fs_offline_session_expiry';
  static const String _keyOfflineAttempts = 'fs_offline_attempts';
  static const String _keyDeviceId = 'fs_offline_device_id';
  static const String _keyLastTenant = 'fs_offline_last_tenant';
  static const String _keyDownloadStamp = 'fs_offline_download_stamp';
}
