import 'package:fashionstore_mobile/core/services/device_service.dart';

/// Cliente HTTP falso para pruebas de Fase 2.
class FakeOfflineClient implements OfflineApiClient {
  FakeOfflineClient({this.online = true});

  bool online;
  final List<String> paths = <String>[];
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> headers = <Map<String, dynamic>>[];
  dynamic Function(String path, dynamic data)? responder;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    paths.add(path);
    if (!online) throw StateError('offline');
    return responder?.call(path, null) ?? const <String, dynamic>{};
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    paths.add(path);
    requests.add(Map<String, dynamic>.from(data as Map? ?? const {}));
    this.headers.add(Map<String, dynamic>.from(headers ?? const {}));
    if (!online) throw StateError('offline');
    return responder?.call(path, data) ?? const <String, dynamic>{};
  }

  @override
  Future<dynamic> delete(String path, {Object? data}) async {
    paths.add(path);
    if (!online) throw StateError('offline');
    return responder?.call(path, data) ?? const <String, dynamic>{};
  }
}
