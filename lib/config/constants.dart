class AppConstants {
  // Storage keys
  static const String keyAccessToken = 'fs_access_token';
  static const String keyRefreshToken = 'fs_refresh_token';
  static const String keyUserData = 'fs_user_data';
  static const String keyClientData = 'fs_client_data';
  static const String keyThemeMode = 'fs_theme_mode';
  static const String keyRememberEmail = 'fs_remember_email';

  // API Endpoints
  static const String epLogin = '/auth/login';
  static const String epRegister = '/auth/register';
  static const String epLogout = '/auth/logout';
  static const String epRefresh = '/auth/refresh';
  static const String epMe = '/auth/me';
  static const String epChangePassword = '/auth/change-password';
  static const String epClientProfile = '/cliente/perfil';

  // Assets paths
  static const String imageLogo = 'assets/images/logo.png';
  static const String imagePlaceholder = 'assets/images/placeholder.png';
}
