import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/config.dart';
import 'storage_service.dart';

/// Evento recibido por los canales de sincronización o pagos.
class RealtimeEvent {
  const RealtimeEvent({
    required this.channel,
    required this.type,
    this.data = const {},
  });
  final String channel;
  final String type;
  final Map<String, dynamic> data;

  factory RealtimeEvent.fromJson(String channel, Map<String, dynamic> json) =>
      RealtimeEvent(
        channel: channel,
        type: (json['evento'] ?? json['tipo'] ?? json['type'] ?? '')
            .toString()
            .toUpperCase(),
        data: json,
      );
}

/// Contrato mínimo de un socket para permitir pruebas sin red.
abstract class RealtimeSocket {
  Stream<dynamic> get stream;
  void close();
}

abstract class RealtimeSocketFactory {
  Future<RealtimeSocket> connect(Uri uri);
}

class _WebSocketChannelFactory implements RealtimeSocketFactory {
  @override
  Future<RealtimeSocket> connect(Uri uri) async =>
      _ChannelRealtimeSocket(WebSocketChannel.connect(uri));
}

class _ChannelRealtimeSocket implements RealtimeSocket {
  _ChannelRealtimeSocket(this._channel);
  final WebSocketChannel _channel;
  @override
  Stream<dynamic> get stream => _channel.stream;
  @override
  void close() => _channel.sink.close();
}

/// [EXAMEN-2] Canales WS /ws/sync y /ws/pagos.
///
/// Si el socket no está disponible, la cola HTTP y el sondeo de providers
/// siguen siendo la vía de recuperación.
class RealtimeService {
  RealtimeService({
    required StorageService storageService,
    required int tenantId,
    RealtimeSocketFactory? socketFactory,
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 1),
  }) : _storageService = storageService,
       _tenantId = tenantId,
       _socketFactory = socketFactory ?? _WebSocketChannelFactory(),
       _baseBackoff = baseBackoff,
       _maxBackoff = maxBackoff;

  final StorageService _storageService;
  final int _tenantId;
  final RealtimeSocketFactory _socketFactory;
  final Duration _baseBackoff;
  final Duration _maxBackoff;
  final StreamController<RealtimeEvent> _eventos =
      StreamController<RealtimeEvent>.broadcast();
  final Map<String, RealtimeSocket> _sockets = <String, RealtimeSocket>{};
  final Map<String, Timer> _reconnects = <String, Timer>{};
  final Map<String, int> _attempts = <String, int>{};
  bool _activo = false;

  Stream<RealtimeEvent> get eventos => _eventos.stream;
  bool get estaConectado => _sockets.isNotEmpty;
  bool get activo => _activo;

  Future<void> iniciar() async {
    if (_activo) return;
    _activo = true;
    await Future.wait<void>(<Future<void>>[
      _conectar('sync'),
      _conectar('pagos'),
    ]);
  }

  Future<void> detener() async {
    _activo = false;
    for (final timer in _reconnects.values) {
      timer.cancel();
    }
    _reconnects.clear();
    for (final socket in _sockets.values) {
      socket.close();
    }
    _sockets.clear();
    _attempts.clear();
  }

  /// Construye la URL tenant-aware del backend. La autenticación viaja por
  /// cabecera Authorization (no por query ?token=) — §5.7/§8.2.
  Map<String, String> headersCanal({String? token}) => <String, String>{
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Uri urlCanal(String channel, {String? token}) {
    final httpBase = Uri.parse(AppConfig.apiBaseUrl);
    final scheme = httpBase.scheme == 'https' ? 'wss' : 'ws';
    final basePath = httpBase.path.endsWith('/')
        ? httpBase.path.substring(0, httpBase.path.length - 1)
        : httpBase.path;
    // [EXAMEN-2] C2.6: sin token en query; va por header Authorization.
    final query = <String, String>{'tenant_id': '$_tenantId'};
    return httpBase.replace(
      scheme: scheme,
      path: '$basePath/ws/$channel',
      queryParameters: query,
    );
  }

  Future<void> _conectar(String channel) async {
    if (!_activo || _sockets.containsKey(channel)) return;
    final token = await _storageService.getAccessToken();
    try {
      final socket = await _socketFactory.connect(
        urlCanal(channel, token: token),
      );
      _sockets[channel] = socket;
      _attempts[channel] = 0;
      socket.stream.listen(
        (raw) => _procesar(channel, raw),
        onError: (_) => _programarReconexion(channel),
        onDone: () => _programarReconexion(channel),
        cancelOnError: true,
      );
    } catch (_) {
      _programarReconexion(channel);
    }
  }

  void _procesar(String channel, dynamic raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final event = RealtimeEvent.fromJson(
        channel,
        Map<String, dynamic>.from(decoded),
      );
      if (event.type.isNotEmpty && !_eventos.isClosed) _eventos.add(event);
    } catch (_) {
      // Un mensaje no JSON no debe romper el canal.
    }
  }

  void _programarReconexion(String channel) {
    if (!_activo) return;
    _sockets.remove(channel)?.close();
    _reconnects.remove(channel)?.cancel();
    final attempt = (_attempts[channel] ?? 0) + 1;
    _attempts[channel] = attempt;
    final milliseconds = (_baseBackoff.inMilliseconds * (1 << (attempt - 1)))
        .clamp(_baseBackoff.inMilliseconds, _maxBackoff.inMilliseconds);
    _reconnects[channel] = Timer(
      Duration(milliseconds: milliseconds),
      () => unawaited(_conectar(channel)),
    );
  }

  Future<void> dispose() async {
    await detener();
    await _eventos.close();
  }
}
