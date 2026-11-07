import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../config/constants.dart';
import '../models/api_response.dart';
import 'device_service.dart';

/// [EXAMEN-2] Conectividad real: la red por sí sola no garantiza servidor.
class ConnectivityService {
  ConnectivityService({
    required OfflineApiClient client,
    Connectivity? connectivity,
  }) : _client = client,
       _connectivity = connectivity ?? Connectivity();

  final OfflineApiClient _client;
  final Connectivity _connectivity;

  bool _ultimoEstado = false;
  DateTime? _ultimaVerificacion;
  StreamSubscription<ConnectivityResult>? _suscripcion;
  final StreamController<bool> _cambios = StreamController<bool>.broadcast();

  bool get estaEnLinea => _ultimoEstado;
  DateTime? get ultimaVerificacion => _ultimaVerificacion;
  Stream<bool> get cambios => _cambios.stream;

  Future<ConnectivityResult> tipoConexion() async {
    return _connectivity.checkConnectivity();
  }

  /// Consulta `/offline/version`. Un 404 demuestra que el servidor respondió,
  /// aunque la fase del paquete todavía no esté desplegada.
  Future<bool> verificarServidor() async {
    try {
      await _client.get(AppConstants.epOfflineVersion);
      _ultimoEstado = true;
    } on ApiException catch (error) {
      _ultimoEstado = error.statusCode != null;
    } catch (_) {
      _ultimoEstado = false;
    }
    _ultimaVerificacion = DateTime.now();
    _cambios.add(_ultimoEstado);
    return _ultimoEstado;
  }

  /// Inicia la escucha de cambios de interfaz de red.
  Future<void> observarCambios() async {
    if (_suscripcion != null) return;
    _suscripcion = _connectivity.onConnectivityChanged.listen((
      resultados,
    ) async {
      final hayInterfaz = resultados != ConnectivityResult.none;
      if (!hayInterfaz) {
        _ultimoEstado = false;
        _ultimaVerificacion = DateTime.now();
        _cambios.add(false);
        return;
      }
      await verificarServidor();
    });
  }

  Future<void> detenerObservacion() async {
    await _suscripcion?.cancel();
    _suscripcion = null;
  }

  Future<void> dispose() async {
    await detenerObservacion();
    await _cambios.close();
  }
}
