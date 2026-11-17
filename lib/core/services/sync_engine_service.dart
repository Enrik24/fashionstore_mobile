import 'dart:async';
import 'dart:math' as math;

import '../../config/config.dart';
import '../../config/constants.dart';
import 'connectivity_service.dart';
import 'device_service.dart';
import 'local_audit_service.dart';
import '../models/phase2_models.dart';
import '../utils/conflict_classifier.dart';
import 'offline_queue_service.dart';
import 'storage_quota_service.dart';

/// [EXAMEN-2] Único punto de envío de operaciones a `/offline/sync` (CU08).
///
/// Contrato (plan §9.5 / backend 11.7): cada operación viaja con
/// `uuid_operacion`, `dispositivo_id`, `secuencia_local`, `tipo_operacion`,
/// `sucursal_id`, `fecha_registro_local` y `payload`. En SQLite se persiste
/// como `payload_json`; al enviar se traduce a `payload` (validado contra el
/// router real del backend). La idempotencia es por `uuid_operacion`
/// (y `uuid_pago` en pagos diferidos, RN-015).
/// [EXAMEN-2] B2.11: **CONTRATO DE SINCRONIZACIÓN** (CU08 / RN-005 / RN-010).
///
/// — **Endpoint**: `POST /offline/sync` (`AppConstants.epOfflineSync`).
/// — **Cabecera**: `Idempotency-Key` = concatenación de los `uuid_operacion`
///   del lote (estable ante reintentos: el servidor deduplica por UUID).
/// — **Cuerpo**:
/// ```json
/// {
///   "dispositivo_id": "uuid-del-dispositivo",
///   "secuencia_local": 12,
///   "operaciones": [
///     {
///       "uuid_operacion": "uuid-v4-unico",
///       "dispositivo_id": "uuid-del-dispositivo",
///       "usuario_id": 42,
///       "secuencia_local": 12,
///       "tipo_operacion": "RESERVA|VENTA_CONTADO|DEVOLUCION|REPOSICION|ORDEN_PAGO_DIFERIDO",
///       "sucursal_id": 1,
///       "fecha_registro_local": "2026-01-01T00:00:00Z",
///       "payload": { }
///     }
///   ]
/// }
/// ```
/// — **Respuesta** (`SincronizacionService.construir_resultado`, backend):
/// ```json
/// {
///   "uuid_operacion": "...",
///   "estado": "CONFIRMADA|RECHAZADA|CONFLICTO|DUPLICADA|ERROR_CRITICO",
///   "motivo": "texto legible",
///   "datos_resultado": { "tipo_conflicto": "...", "estrategia_resolucion": "..." },
///   "reintentar": false,
///   "codigo_http_sugerido": 200
/// }
/// ```
/// — **Idempotencia (RN-005)**: el servidor deduplica por `uuid_operacion`
///   (tabla `ClaveIdempotencia`); reenviar la misma operación devuelve
///   `DUPLICADA` sin crear registros nuevos.
/// — **Orden (RN-010)**: las operaciones se envían en orden de
///   `secuencia_local` ASC (secuencia monotónica del dispositivo, no del
///   reloj).
/// — **Estados locales**: `PENDIENTE`, `ENVIADA`, `CONFIRMADA`, `RECHAZADA`,
///   `CONFLICTO`, `CONFLICTO_MANUAL`, `ERROR_DATOS`, `DUPLICADA`,
///   `ERROR_CRITICO`.
/// — **Conflicto**: el detalle llega en **`datos_resultado`** (no en
///   `detalle`); de ahí se obtiene `tipo_conflicto` y `estrategia_resolucion`
///   (ver `core/utils/conflict_classifier.dart`).
/// — **Persistencia local**: la operación vive en la tabla `operaciones` con
///   `payload_json`; al enviar se traduce a `payload`.
class SyncEngineService {
  SyncEngineService({
    required OfflineQueueService queue,
    required OfflineApiClient client,
    required ConnectivityService connectivity,
    required LocalAuditService audit,
    required int tenantId,
    String? dispositivoId,
    int batchSize = AppConfig.offlineLoteMaximo,
    // [EXAMEN-2] B1.5.i: limpieza de datos sincronizados y obsoletos (RNF-14).
    StorageQuotaService? quotaService,
  }) : _queue = queue,
       _client = client,
       _connectivity = connectivity,
       _audit = audit,
       _tenantId = tenantId,
       _dispositivoId = dispositivoId,
       _batchSize = batchSize,
       _quotaService = quotaService;

  final OfflineQueueService _queue;
  final OfflineApiClient _client;
  final ConnectivityService _connectivity;
  final LocalAuditService _audit;
  final int _tenantId;
  final String? _dispositivoId;
  final int _batchSize;
  // [EXAMEN-2] B1.5.i.
  final StorageQuotaService? _quotaService;

  // [FIX-SYNC] Reenvío de pagos diferidos locales al terminar cada pasada de
  // sincronización (incluida la que dispara la reconexión). Se inyecta desde
  // main.dart con PendingPaymentService.reenviarPendientesLocales.
  Future<int> Function()? _reenviarPagosLocales;
  set reenviarPagosLocales(Future<int> Function()? callback) =>
      _reenviarPagosLocales = callback;

  bool _sincronizando = false;
  Timer? _timer;
  // [BUG-SYNC] Máximo de rondas de reintento dentro de una misma
  // sincronización manual (evita martillar el servidor si sigue fallando).
  static const int _maxRondas = 3;
  StreamSubscription<bool>? _connectivitySubscription;
  final StreamController<SyncProgress> _progreso =
      StreamController<SyncProgress>.broadcast();

  bool get estaSincronizando => _sincronizando;
  Stream<SyncProgress> get progreso => _progreso.stream;

  Future<bool> sincronizacionPendiente() async =>
      (await _queue.pendientes(limite: 1)).isNotEmpty;

  /// Resumen local sin red; se usa para badges y el centro de sincronización.
  Future<SyncSummaryModel> resumen() => _queue.resumen();

  /// [EXAMEN-2] B2.1: operaciones pendientes en cola (para la tarjeta de
  /// reintento por ítem del centro de sincronización).
  Future<List<OfflineOperationModel>> pendientes() => _queue.pendientes();

  /// [EXAMEN-2] B1.8.c: fecha de la última sincronización efectiva.
  Future<DateTime?> ultimaSincronizacion() => _queue.ultimaSincronizacion();

  Future<SyncSummaryModel> sincronizarAhora() async {
    if (_sincronizando) return _queue.resumen();
    if (!await _connectivity.verificarServidor()) {
      // [EXAMEN-2] Sin servidor: antes salía en silencio y el botón
      // "Sincronizar ahora" parecía no hacer nada (sin error ni mensaje).
      final resumen = await _queue.resumen();
      return resumen.copyWith(
        ultimoError:
            'Sin conexión con el servidor. Verifica tu conexión e inténtalo de nuevo.',
      );
    }
    _sincronizando = true;
    String? ultimoError;
    try {
      var pendientes = await _queue.pendientes(limite: _batchSize);
      // [BUG-SYNC] Los resultados con `reintentar=true` quedaban en estado
      // PENDIENTE con backoff (`proximo_intento` futuro) y la re-consulta del
      // bucle no los veía: la sincronización terminaba "completa" dejando la
      // operación aún pendiente (badge "Pendientes: 1"). Ahora se limpia el
      // backoff de las operaciones recién enviadas y se reintentan de
      // inmediato dentro de esta misma pasada (acotado por `_maxRondas`).
      var rondas = 0;
      while (pendientes.isNotEmpty && rondas < _maxRondas) {
        rondas++;
        _progreso.add(SyncProgress(total: pendientes.length, enviados: 0));
        final resultados = await enviarLote(pendientes);
        final errorRonda = await procesarResultados(resultados);
        if (errorRonda != null) ultimoError = errorRonda;
        // [FIX-SYNC] Operaciones del lote sin resultado del servidor: vuelven
        // a PENDIENTE (como el frontend web); antes quedaban ENVIADA para
        // siempre y ningún reintento las volvía a tomar.
        final devueltos = resultados
            .map((r) => r['uuid_operacion']?.toString())
            .whereType<String>()
            .toSet();
        for (final operacion in pendientes) {
          if (!devueltos.contains(operacion.uuidOperacion)) {
            await _queue.reintentar(
              operacion.uuidOperacion,
              motivo: 'El servidor no devolvió resultado para esta operación.',
            );
          }
        }
        if (resultados.isEmpty) break;
        // Las operaciones de este lote que quedaron PENDIENTE/ERROR tienen
        // backoff; sin esto, `pendientes()` las oculta y el bucle sale
        // creyendo que no queda nada por enviar.
        await _queue.habilitarReintentoInmediato(
          pendientes.map((o) => o.uuidOperacion),
        );
        pendientes = await _queue.pendientes(limite: _batchSize);
      }
      // [FIX-SYNC] Los pagos diferidos cuyo POST inicial falló sin red se
      // reenvían aquí: la orden ya sincronizada los crea en el servidor y
      // POST /pagos/diferidos es idempotente por uuid_pago (RN-015), así que
      // este paso también refresca su estado local tras la confirmación.
      try {
        await _reenviarPagosLocales?.call();
      } catch (_) {
        // Best-effort: no debe romper la sincronización.
      }
      final resumen = await _queue.resumen();
      // [EXAMEN-2] B1.5.i: tras sincronizar se limpian los datos ya
      // sincronizados y los conflictos resueltos (RNF-14). Antes estos dos
      // métodos existían pero **nadie los invocaba**.
      await _limpiarLocal();
      await _audit.registrar(
        tenantId: _tenantId,
        tipo: 'SINCRONIZACION_COMPLETADA',
        mensaje: 'Sincronización completada.',
        datos: {
          'confirmadas': resumen.confirmadas,
          'rechazadas': resumen.rechazadas,
        },
      );
      // [BUG-SYNC] `resumen()` no trae `ultimoError`: el motivo que el
      // servidor devolvió por operación (p.ej. "Error transitorio",
      // "La operación ya está siendo procesada") se descartaba y el
      // proveedor mostraba "Sincronización completa: 0 confirmadas,
      // 0 rechazadas" como si todo hubiera ido bien.
      return ultimoError == null
          ? resumen
          : resumen.copyWith(ultimoError: ultimoError);
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
                  // [EXAMEN-2] B0.4.c: el usuario que originó la operación
                  // viaja en el payload para que el backend pueda auditar
                  // quién la creó (además de la fila local `operaciones`).
                  'usuario_id': o.usuarioId,
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
      final estadoBruto =
          resultado['estado']?.toString() ??
          resultado['estado_sincronizacion']?.toString();
      if (estadoBruto == null || estadoBruto.isEmpty) {
        // [BUG-SYNC] antes el estado faltante se mapeaba a PENDIENTE en
        // silencio: la operación seguía pendiente sin ningún aviso.
        ultimoError ??= 'El servidor no devolvió estado para la operación.';
      }
      final estado = (estadoBruto ?? 'PENDIENTE').toUpperCase();
      final motivo =
          resultado['motivo']?.toString() ??
          resultado['error_detalle']?.toString();
      if (motivo != null) ultimoError = motivo;
      // [EXAMEN-2] B1.5: el backend envía el detalle del conflicto en
      // `datos_resultado` (`SincronizacionService.construir_resultado`), no en
      // `detalle`. El móvil leía `detalle`, por lo que **nunca** capturaba el
      // tipo de conflicto ni la comparación local↔central que muestra la
      // pantalla de conflictos (CU09).
      final bruto = resultado['datos_resultado'] ?? resultado['detalle'];
      final detalle = bruto is Map
          ? Map<String, Object?>.from(bruto)
          : null;
      // El tipo de conflicto puede venir en la raíz o dentro del detalle.
      var tipoConflicto =
          (resultado['tipo_conflicto']?.toString() ??
                  detalle?['tipo_conflicto']?.toString() ??
                  '')
              .toUpperCase();
      // [FIX-SYNC] AceptacionRequerida no envía `tipo_conflicto` en
      // `datos_resultado`: lo delata `requiere_aceptacion`. Sin esto el
      // conflicto se guardaba como DESCONOCIDO en la pantalla de conflictos.
      if (tipoConflicto.isEmpty && detalle?['requiere_aceptacion'] == true) {
        tipoConflicto = TiposConflicto.precioDesactualizado;
      }
      await _queue.aplicarResultado(
        uuidOperacion: uuid,
        estado: estado,
        motivo: motivo,
        detalle: detalle,
        tipoConflicto: tipoConflicto.isEmpty ? null : tipoConflicto,
        // [EXAMEN-2] B1.5.d: el backend indica si la operación debe reintentarse.
        solicitarReintento: resultado['reintentar'] == true,
        // [EXAMEN-2] B1.4.b: el tipo de operación (para detenerlo si llega
        // un ERROR_CRITICO). El tipo no viene en la respuesta del backend,
        // se lee de la fila local.
        tipoOperacion: await _queue.tipoOperacionDe(uuid),
      );
      // [BUG-SYNC] EN_PROCESO: el servidor tiene la operación ENVIADA
      // (procesándola o con un bloqueo huérfano tras una respuesta perdida).
      // Reenviar el lote devolvería EN_PROCESO indefinidamente (deadlock);
      // el endpoint de reintento por ítem obliga al servidor a re-ejecutarla.
      if (estado == 'EN_PROCESO') {
        try {
          final data = await _client.post(
            '${AppConstants.epOfflineOperaciones}/$uuid/reintentar',
            headers: <String, dynamic>{'Idempotency-Key': uuid},
          );
          if (data is Map) {
            await procesarResultados(<Map<String, Object?>>[
              Map<String, Object?>.from(data),
            ]);
          }
        } catch (_) {
          // Sin recuperación automática (p.ej. el servidor aún rechaza
          // reintentar ENVIADA): queda pendiente para el reintento manual
          // de la tarjeta de la cola.
        }
      }
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

  /// [EXAMEN-2] B1.5.i: limpieza de datos locales obsoletos (RNF-14).
  ///
  /// Nunca borra operaciones pendientes, pagos sin confirmar ni
  /// devoluciones/compensaciones por confirmar.
  Future<void> _limpiarLocal() async {
    final quota = _quotaService;
    if (quota == null) return;
    try {
      await quota.limpiarSincronizados();
      await quota.limpiarObsoletos();
    } catch (_) {
      // La limpieza es best-effort: no debe tumbar la sincronización.
    }
  }

  /// [EXAMEN-2] C2.2: reintento por ítem (POST /offline/operaciones/{uuid}/reintentar).
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
