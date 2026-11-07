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

  /// [EXAMEN-2] Callback para reaccionar a revocación de dispositivo (CU17).
  Future<void> Function()? onDeviceRevoked;

  ApiService({required this.storageService}) {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(
          seconds: AppConfig.connectTimeoutSeconds,
        ),
        receiveTimeout: const Duration(
          seconds: AppConfig.receiveTimeoutSeconds,
        ),
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
          // [EXAMEN-2] El token offline solo sustituye al online en rutas
          // /offline/* cuando no existe una sesión online vigente.
          final onlineToken = await storageService.getAccessToken();
          String? token = onlineToken;
          if ((token == null || token.isEmpty) &&
              options.path.contains('/offline/')) {
            token = await storageService.readOfflineToken();
          }
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // [EXAMEN-2] Un dispositivo revocado invalida la sesión local.
          final detail = error.response?.data is Map<String, dynamic>
              ? (error.response!.data['detail'] ??
                        error.response!.data['codigo'] ??
                        '')
                    .toString()
              : '';
          if (error.response?.statusCode == 403 &&
              detail.contains('DISPOSITIVO_REVOCADO')) {
            await onDeviceRevoked?.call();
          }
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
                    retryOptions.headers['Authorization'] =
                        'Bearer ${tokens.accessToken}';

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
        message =
            'No se pudo conectar al servidor FashionStore (${AppConfig.apiBaseUrl}).';
      }

      // [EXAMEN-2] C1.3: tolerar 404/501 de TODOS los endpoints N* (§8.4).
      final requestPath = error.requestOptions.path;
      final esNuevo =
          requestPath.contains('/offline/') ||
          requestPath.contains('/carrito/offline') ||
          requestPath.contains('/pagos/diferidos') ||
          requestPath.contains('/pagos/pendientes') ||
          requestPath.contains('/devoluciones/');
      if ((statusCode == 404 || statusCode == 501) && esNuevo) {
        message =
            'Esta función aún no está disponible en el servidor. Tu operación quedó guardada.';
      } else if (statusCode == 401 || statusCode == 403) {
        final detail = data is Map<String, dynamic>
            ? (data['detail'] ?? data['codigo'] ?? '').toString().toUpperCase()
            : '';
        if (detail.contains('DISPOSITIVO_REVOCADO')) {
          message =
              'Este dispositivo fue revocado. Se eliminaron los datos locales; inicia sesión de nuevo.';
        } else if (detail.contains('SESION_OFFLINE_VENCIDA')) {
          message =
              'La sesión offline venció. Puedes consultar el catálogo, pero necesitas conexión para operar.';
        } else if (detail.contains('PIN_INCORRECTO')) {
          message = 'PIN incorrecto.';
        } else if (detail.contains('PIN_BLOQUEADO')) {
          message =
              'Superaste los intentos permitidos. Debes iniciar sesión con conexión.';
        } else if (detail.contains('PIN_NO_CONFIGURADO')) {
          message = 'Configura tu PIN para poder operar sin conexión.';
        } else if (detail.contains('TENANT_SUSPENDIDO')) {
          message =
              'La suscripción de la empresa no está activa. La operación quedó pendiente de regularización.';
        } else if (detail.contains('PAGO_DIFERIDO_NO_DISPONIBLE')) {
          message =
              'El pago diferido no está disponible para esta empresa.';
        } else if (detail.contains('LIMITE_PLAN_EXCEDIDO')) {
          message = 'Se excedió el límite del plan contratado.';
        }
      } else if ((statusCode == 400 || statusCode == 403) &&
          data is Map<String, dynamic>) {
        // [EXAMEN-2] C1.3: PagoDiferidoNoDisponible / LimitePlanExcedido también llegan como 400/403.
        final detail = (data['detail'] ?? data['codigo'] ?? '')
            .toString()
            .toUpperCase();
        if (detail.contains('PAGO_DIFERIDO_NO_DISPONIBLE')) {
          message =
              'El pago diferido no está disponible para esta empresa.';
        } else if (detail.contains('LIMITE_PLAN_EXCEDIDO')) {
          message = 'Se excedió el límite del plan contratado.';
        }
      }

      return ApiException(message: message, statusCode: statusCode, data: data);
    } else if (error is ApiException) {
      return error;
    }
    return ApiException(message: error.toString());
  }
}
