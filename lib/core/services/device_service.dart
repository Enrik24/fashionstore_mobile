import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';

import '../../config/constants.dart';
import '../models/device_model.dart';
import 'api_service.dart';
import 'local_crypto_service.dart';
import 'storage_service.dart';

/// [EXAMEN-2] Adaptador mínimo sobre las APIs públicas de [ApiService].
/// Permite probar la Fase 1 sin acoplar los servicios a Dio.
abstract class OfflineApiClient {
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters});
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  });
  Future<dynamic> delete(String path, {Object? data});
}

class ApiServiceOfflineClient implements OfflineApiClient {
  const ApiServiceOfflineClient(this.apiService);

  final ApiService apiService;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await apiService.dio.get(
        path,
        queryParameters: queryParameters,
      );
      return response.data;
    } catch (e) {
      throw apiService.handleError(e);
    }
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await apiService.dio.post(
        path,
        data: data,
        options: Options(headers: headers),
      );
      return response.data;
    } catch (e) {
      throw apiService.handleError(e);
    }
  }

  @override
  Future<dynamic> delete(String path, {Object? data}) async {
    try {
      final response = await apiService.dio.delete(path, data: data);
      return response.data;
    } catch (e) {
      throw apiService.handleError(e);
    }
  }
}

/// [EXAMEN-2] Identidad, metadatos y autorización de dispositivos (CU17).
class DeviceService {
  DeviceService({
    required StorageService storageService,
    required ApiService apiService,
    OfflineApiClient? client,
    DeviceInfoPlugin? deviceInfo,
    LocalCryptoService? cryptoService,
  }) : _storageService = storageService,
       _client = client ?? ApiServiceOfflineClient(apiService),
       _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _cryptoService = cryptoService ?? LocalCryptoService();

  final StorageService _storageService;
  final OfflineApiClient _client;
  final DeviceInfoPlugin _deviceInfo;
  final LocalCryptoService _cryptoService;

  /// Identificador UUID estable; se genera una sola vez por instalación.
  Future<String> get dispositivoId async {
    final existente = await _storageService.readDeviceId();
    if (existente != null && existente.isNotEmpty) return existente;
    final nuevo = _cryptoService.generarUuid();
    await _storageService.saveDeviceId(nuevo);
    return nuevo;
  }

  Future<String> get plataforma async {
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isIOS) return 'IOS';
    return 'WEB';
  }

  Future<String> get nombre async {
    try {
      final info = await _deviceInfo.deviceInfo;
      final modelo = info.data['model']?.toString().trim() ?? '';
      final nombre = info.data['name']?.toString().trim() ?? '';
      final resultado = [nombre, modelo]
          .where(
            (valor) => valor.isNotEmpty && valor.toLowerCase() != 'unknown',
          )
          .join(' · ');
      if (resultado.isNotEmpty) {
        return resultado.length <= 100
            ? resultado
            : resultado.substring(0, 100);
      }
    } catch (_) {
      // La metadata es opcional: el UUID sigue siendo la identidad estable.
    }
    return 'Dispositivo FashionStore';
  }

  /// Registra o actualiza el dispositivo ante el backend.
  Future<DeviceModel> registrar({String? nombre}) async {
    final id = await dispositivoId;
    final data = await _client.post(
      AppConstants.epOfflineDispositivos,
      data: {
        'id': id,
        'plataforma': await plataforma,
        'nombre': nombre ?? await this.nombre,
      },
    );
    final dispositivo = DeviceModel.fromJson(data as Map<String, dynamic>);
    await _storageService.saveDeviceId(dispositivo.id);
    return dispositivo;
  }

  Future<List<DeviceModel>> listar() async {
    final data = await _client.get(AppConstants.epOfflineDispositivos);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(DeviceModel.fromJson)
        .toList(growable: false);
  }

  Future<DeviceModel> revocar(String deviceId, {String? motivo}) async {
    final data = await _client.post(
      '${AppConstants.epOfflineDispositivos}/$deviceId/revocar',
      data: <String, dynamic>{if (motivo != null) 'motivo': motivo},
    );
    return DeviceModel.fromJson(data as Map<String, dynamic>);
  }

  Future<DeviceModel> reactivar(String deviceId) async {
    final data = await _client.post(
      '${AppConstants.epOfflineDispositivos}/$deviceId/reactivar',
    );
    return DeviceModel.fromJson(data as Map<String, dynamic>);
  }
}
