import 'package:dio/dio.dart';
import '../../config/config.dart';
import '../../config/constants.dart';
import '../models/api_response.dart';
import '../models/user_model.dart';
import 'storage_service.dart';

class ApiService {
  late final Dio dio;
  final StorageService storageService;
  bool _isRefreshing = false;

  ApiService({required this.storageService}) {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: AppConfig.connectTimeoutSeconds),
        receiveTimeout: const Duration(seconds: AppConfig.receiveTimeoutSeconds),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _setupInterceptors();
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await storageService.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // If 401 Unauthorized, try refresh token once
          if (error.response?.statusCode == 401 && !_isRefreshing) {
            final requestPath = error.requestOptions.path;
            // Avoid loop if refresh itself fails or login/register fails
            if (!requestPath.contains(AppConstants.epRefresh) &&
                !requestPath.contains(AppConstants.epLogin) &&
                !requestPath.contains(AppConstants.epRegister)) {
              _isRefreshing = true;
              try {
                final refreshToken = await storageService.getRefreshToken();
                if (refreshToken != null && refreshToken.isNotEmpty) {
                  final refreshResponse = await dio.post(
                    AppConstants.epRefresh,
                    data: {'refresh_token': refreshToken},
                    options: Options(headers: {'Authorization': null}),
                  );

                  if (refreshResponse.statusCode == 200) {
                    final tokens = TokenResponse.fromJson(refreshResponse.data);
                    await storageService.saveTokens(tokens);

                    // Retry original request with new access token
                    final retryOptions = error.requestOptions;
                    retryOptions.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
                    
                    _isRefreshing = false;
                    final response = await dio.fetch(retryOptions);
                    return handler.resolve(response);
                  }
                }
              } catch (_) {
                // Refresh failed, clear session
                await storageService.clearAllSession();
              } finally {
                _isRefreshing = false;
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  ApiException handleError(dynamic error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final data = error.response?.data;
      String message = 'Error de conexión con el servidor.';

      if (data is Map<String, dynamic>) {
        if (data.containsKey('detail')) {
          final detail = data['detail'];
          if (detail is String) {
            message = detail;
          } else if (detail is List && detail.isNotEmpty) {
            // FastAPI validation errors
            final firstError = detail.first;
            if (firstError is Map && firstError.containsKey('msg')) {
              message = firstError['msg'].toString();
            } else {
              message = detail.toString();
            }
          }
        } else if (data.containsKey('message')) {
          message = data['message'].toString();
        }
      } else if (error.type == DioExceptionType.connectionTimeout ||
                 error.type == DioExceptionType.sendTimeout ||
                 error.type == DioExceptionType.receiveTimeout) {
        message = 'Tiempo de espera agotado. Verifica tu conexión a internet.';
      } else if (error.type == DioExceptionType.connectionError) {
        message = 'No se pudo conectar al servidor FashionStore (${AppConfig.apiBaseUrl}).';
      }

      return ApiException(
        message: message,
        statusCode: statusCode,
        data: data,
      );
    } else if (error is ApiException) {
      return error;
    }
    return ApiException(message: error.toString());
  }
}
