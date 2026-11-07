import 'dart:async';
import 'dart:math' as math;

import '../../config/config.dart';
import '../../config/constants.dart';
import 'connectivity_service.dart';
import 'device_service.dart';
import 'local_audit_service.dart';
import '../models/phase2_models.dart';
import 'offline_queue_service.dart';

/// [EXAMEN-2] Único punto de envío de operaciones a `/offline/sync` (CU08).
///
/// Contrato (plan §9.5 / backend 11.7): cada operación viaja con
/// `uuid_operacion`, `dispositivo_id`, `secuencia_local`, `tipo_operacion`,
/// `sucursal_id`, `fecha_registro_local` y `payload`. En SQLite se persiste
/// como `payload_json`; al enviar se traduce a `payload` (validado contra el
/// router real del backend). La idempotencia es por `uuid_operacion`
/// (y `uuid_pago` en pagos diferidos, RN-015).
class SyncEngineService {
  SyncEngineService({
    required OfflineQueueService queue,
    required OfflineApiClient client,
    required ConnectivityService connectivity,
    required LocalAuditService audit,
    required int tenantId,
    String? dispositivoId,
    int batchSize = AppConfig.offlineLoteMaximo,
  }) : _queue = queue,
       _client = client,
       _connectivity = connectivity,
       _audit = audit,
       _tenantId = tenantId,
       _dispositivoId = dispositivoId,
       _batchSize = batchSize;

  final OfflineQueueService _queue;
  final OfflineApiClient _client;
  final ConnectivityService _connectivity;
  final LocalAuditService _audit;
  final int _tenantId;
  final String? _dispositivoId;
  final int _batchSize;

  bool _sincronizando = false;
  Timer? _timer;
  StreamSubscription<bool>? _connectivitySubscription;
  final StreamController<SyncProgress> _progreso =
      StreamController<SyncProgress>.broadcast();

  bool get estaSincronizando => _sincronizando;
  Stream<SyncProgress> get progreso => _progreso.stream;

  Future<bool> sincronizacionPendiente() async =>
      (await _queue.pendientes(limite: 1)).isNotEmpty;

  /// Resumen local sin red; se usa para badges y el centro de sincronización.
  Future<SyncSummaryModel> resumen() => _queue.resumen();

  Future<SyncSummaryModel> sincronizarAhora() async {
    if (_sincronizando) return _queue.resumen();
    if (!await _connectivity.verificarServidor()) {
      return _queue.resumen();
    }
    _sincronizando = true;
    String? ultimoError;
    try {
      var pendientes = await _queue.pendientes(limite: _batchSize);
      while (pendientes.isNotEmpty) {
        _progreso.add(SyncProgress(total: pendientes.length, enviados: 0));
        final resultados = await enviarLote(pendientes);
        ultimoError = await procesarResultados(resultados);
        if (resultados.isEmpty) break;
        pendientes = await _queue.pendientes(limite: _batchSize);
      }
      final resumen = await _queue.resumen();
      await _audit.registrar(
        tenantId: _tenantId,
        tipo: 'SINCRONIZACION_COMPLETADA',
        mensaje: 'Sincronización completada.',
        datos: {
          'confirmadas': resumen.confirmadas,
          'rechazadas': resumen.rechazadas,
        },
      );
      return resumen;
    } catch (error) {
      ultimoError = error.toString();
      await _audit.registrar(
        tenantId: _tenantId,
        tipo: 'SINCRONIZACION_ERROR',
        mensaje: 'Falló la sincronización.',
        datos: {'error': ultimoError},
      );
      return SyncSummaryModel(ultimoError: ultimoError);
    } finally {
      _sincronizando = false;
    }
  }

  Future<List<Map<String, Object?>>> enviarLote(
    List<OfflineOperationModel> operaciones,
  ) async {
    if (operaciones.isEmpty) return const [];
    // [EXAMEN-2] C2.2: idempotencia por lote con hash de UUIDs (estable ante reintento);
    // el servidor además deduplica por `uuid_operacion` (DUPLICADA).
    final idempotencyKey = operaciones
        .map((o) => o.uuidOperacion)
        .join(',');
    for (final operacion in operaciones) {
      await _queue.marcarEnviada(operacion.uuidOperacion);
    }
    try {
      final data = await _client.post(
        AppConstants.epOfflineSync,
        data: <String, Object?>{
          'dispositivo_id': _dispositivoId ?? operaciones.first.dispositivoId,
          'secuencia_local': operaciones.first.secuenciaLocal,
          'operaciones': operaciones
              .map(
                (o) => <String, Object?>{
                  'uuid_operacion': o.uuidOperacion,
                  'dispositivo_id': o.dispositivoId,
                  'secuencia_local': o.secuenciaLocal,
                  'tipo_operacion': o.tipoOperacion,
                  'sucursal_id': o.sucursalId,
                  'fecha_registro_local': o.fechaRegistroLocal
                      ?.toUtc()
                      .toIso8601String(),
                  'payload': o.payload,
                },
              )
              .toList(),
        },
        headers: <String, dynamic>{'Idempotency-Key': idempotencyKey},
      );
      if (data is Map && data['resultados'] is List) {
        return (data['resultados'] as List)
            .whereType<Map>()
            .map((e) => Map<String, Object?>.from(e))
            .toList(growable: false);
      }
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, Object?>.from(e))
            .toList(growable: false);
      }
      return const [];
    } catch (_) {
      for (final operacion in operaciones) {
        await _queue.reintentar(
          operacion.uuidOperacion,
          motivo: 'Error de red',
        );
      }
      rethrow;
    }
  }

  Future<String?> procesarResultados(
    List<Map<String, Object?>> resultados,
  ) async {
    String? ultimoError;
    for (final resultado in resultados) {
      final uuid = resultado['uuid_operacion']?.toString();
      if (uuid == null || uuid.isEmpty) continue;
      final estado =
          (resultado['estado']?.toString() ??
                  resultado['estado_sincronizacion']?.toString() ??
                  'PENDIENTE')
              .toUpperCase();
      final motivo =
          resultado['motivo']?.toString() ??
          resultado['error_detalle']?.toString();
      if (motivo != null) ultimoError = motivo;
      final detalle = resultado['detalle'];
      await _queue.aplicarResultado(
        uuidOperacion: uuid,
        estado: estado,
        motivo: motivo,
        detalle: detalle is Map ? Map<String, Object?>.from(detalle) : null,
        tipoConflicto: resultado['tipo_conflicto']?.toString(),
      );
      // [EXAMEN-2] C2.2: ERROR_CRITICO (RN-017) detiene ese tipo y se audita.
      if (estado == 'ERROR_CRITICO') {
        await _audit.registrar(
          tenantId: _tenantId,
          tipo: 'SINCRONIZACION_ERROR_CRITICO',
          mensaje: motivo ?? 'Error crítico de sincronización.',
          datos: <String, dynamic>{'uuid_operacion': uuid, 'motivo': motivo},
        );
        ultimoError = motivo ?? 'Error crítico de sincronización.';
      }
    }
    return ultimoError;
  }

  // [EXAMEN-2] C2.2: retroceso exponencial con jitter (base configurable).
  void programarReintento({
    Duration base = const Duration(seconds: AppConfig.offlineBackoffBaseSegundos),
  }) {
    _timer?.cancel();
    final jitter = Duration(
      milliseconds: math.Random().nextInt(1000),
    );
    final delay = base + jitter;
    const techo = Duration(seconds: AppConfig.offlineBackoffMaximoSegundos);
    _timer = Timer(delay > techo ? techo : delay, () async {
      await sincronizarAhora();
    });
  }

  Future<void> registrarDisparadores() async {
    await _connectivity.observarCambios();
    _connectivitySubscription ??= _connectivity.cambios.listen((online) {
      if (online) sincronizarAhora();
    });
  }

  // [EXAMEN-2] C2.6 CU09: reintento por ítem (POST /offline/operaciones/{uuid}/reintentar).
  Future<void> reintentar(String uuidOperacion) async {
    await _client.post(
      '${AppConstants.epOfflineOperaciones}/$uuidOperacion/reintentar',
      headers: <String, dynamic>{'Idempotency-Key': uuidOperacion},
    );
    await _queue.reintentar(uuidOperacion);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _connectivitySubscription?.cancel();
    await _progreso.close();
  }
}

class SyncProgress {
  const SyncProgress({required this.total, required this.enviados});
  final int total;
  final int enviados;
}
