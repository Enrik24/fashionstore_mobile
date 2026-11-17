import 'dart:convert';
import 'dart:math' as math;

import '../database/local_database_service.dart';
import '../database/repositories/conflict_repository.dart';
import '../database/repositories/offline_queue_repository.dart';
import '../models/phase2_models.dart';
import '../utils/conflict_classifier.dart';
import 'local_audit_service.dart';

/// [EXAMEN-2] Cola FIFO idempotente de operaciones offline (CU08).
class OfflineQueueService {
  OfflineQueueService({
    required LocalDatabaseService database,
    required int tenantId,
    required String dispositivoId,
    int? usuarioId,
    OfflineQueueRepository? repository,
    ConflictRepository? conflictRepository,
    // [EXAMEN-2] B1.5: bitácora de conflictos resueltos automáticamente.
    LocalAuditService? audit,
  }) : _database = database,
       _tenantId = tenantId,
       _dispositivoId = dispositivoId,
       _usuarioId = usuarioId,
       _repository = repository,
       _conflictRepository = conflictRepository,
       _audit = audit;

  final LocalDatabaseService _database;
  final int _tenantId;
  final String _dispositivoId;
  final int? _usuarioId;
  // [EXAMEN-2] B1.5: bitacora de conflictos resueltos automaticamente.
  final LocalAuditService? _audit;
  OfflineQueueRepository? _repository;
  ConflictRepository? _conflictRepository;

  OfflineQueueRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _repository ??= OfflineQueueRepository(db, tenantId: _tenantId);
  }

  ConflictRepository get _conflictRepo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return _conflictRepository ??= ConflictRepository(db, tenantId: _tenantId);
  }

  Future<int> siguienteSecuencia() => _repo.obtenerSiguienteSecuencia();

  Future<String> encolar({
    required String uuidOperacion,
    required String tipoOperacion,
    required Map<String, Object?> payload,
    int? secuenciaLocal,
    int? sucursalId,
    String estado = 'PENDIENTE',
  }) {
    return _repo.encolar(
      uuidOperacion: uuidOperacion,
      tipoOperacion: tipoOperacion,
      payload: payload,
      secuenciaLocal: secuenciaLocal,
      dispositivoId: _dispositivoId,
      usuarioId: _usuarioId,
      sucursalId: sucursalId,
      estado: estado,
    );
  }

  Future<List<OfflineOperationModel>> pendientes({int limite = 50}) async {
    // [EXAMEN-2] B1.4.b: se excluyen los tipos detenidos por un error crítico.
    final detenidos = await tiposDetenidos();
    final filas = detenidos.isEmpty
        ? await _repo.listarPendientes(limite: limite)
        : await _repo.listarPendientesExcluyendo(
            detenidos,
            limite: limite,
          );
    return filas.map(OfflineOperationModel.fromMap).toList(growable: false);
  }

  /// [EXAMEN-2] B1.4.b: tipos de operación **detenidos** por un
  /// `ERROR_CRITICO` (RN-017).
  ///
  /// El backend devuelve `ERROR_CRITICO` cuando el tenant está suspendido o
  /// la operación no puede aplicarse. Antes sólo se escribía una línea de
  /// auditoría: el tipo **seguía enviándose** en el siguiente lote.
  static const String _metaTiposDetenidos = '__tipos_detenidos__';

  Future<List<String>> tiposDetenidos() async {
    final db = _database.database;
    if (db == null) return const [];
    final filas = await db.query(
      'meta',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>[_metaTiposDetenidos, _tenantId],
      limit: 1,
    );
    if (filas.isEmpty) return const [];
    final valor = filas.first['valor']?.toString() ?? '';
    if (valor.isEmpty) return const [];
    return valor
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  /// [EXAMEN-2] B1.4.b: detiene (o reanuda) un tipo de operación.
  Future<void> _detenerTipo(String tipoOperacion, bool detener) async {
    final db = _database.database;
    if (db == null) return;
    final actuales = (await tiposDetenidos()).toList();
    if (detener) {
      if (!actuales.contains(tipoOperacion)) actuales.add(tipoOperacion);
    } else {
      actuales.remove(tipoOperacion);
    }
    final valor = actuales.join(',');
    final existentes = await db.query(
      'meta',
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>[_metaTiposDetenidos, _tenantId],
      limit: 1,
    );
    final ahora = DateTime.now().toUtc().toIso8601String();
    if (existentes.isEmpty) {
      await db.insert('meta', <String, Object?>{
        'clave': _metaTiposDetenidos,
        'tenant_id': _tenantId,
        'valor': valor,
        'secuencia_local': 0,
        'version_esquema': 2,
        'fecha_actualizacion': ahora,
      });
    } else {
      await db.update(
        'meta',
        <String, Object?>{
          'valor': valor,
          'fecha_actualizacion': ahora,
        },
        where: 'clave = ? AND tenant_id = ?',
        whereArgs: <Object?>[_metaTiposDetenidos, _tenantId],
      );
    }
  }

  Future<OfflineOperationModel?> obtener(String uuid) async {
    final fila = await _repo.obtenerPorUuid(uuid);
    return fila == null ? null : OfflineOperationModel.fromMap(fila);
  }

  /// [EXAMEN-2] B1.4.b: tipo de la operación (para detener el tipo si la
  /// sincronización devuelve un ERROR_CRITICO).
  Future<String?> tipoOperacionDe(String uuid) async {
    final fila = await _repo.obtenerPorUuid(uuid);
    return fila?['tipo_operacion']?.toString();
  }

  Future<int> marcarEnviada(String uuid) =>
      _repo.actualizarEstado(uuid, 'ENVIADA');

  Future<int> reintentar(String uuid, {String? motivo}) async {
    await _repo.incrementarIntentos(uuid, ultimoError: motivo);
    final operacion = await obtener(uuid);
    final intentos = operacion?.intentos ?? 1;
    // Backoff exponencial: 2s, 4s, 8s... con un máximo seguro de 5 minutos.
    final retraso = Duration(
      seconds: math.min(300, math.pow(2, intentos.clamp(1, 8)).toInt()),
    );
    return _repo.actualizarEstado(
      uuid,
      'PENDIENTE',
      ultimoError: motivo,
      proximoIntento: DateTime.now().toUtc().add(retraso),
    );
  }

  /// [BUG-SYNC] Quita el backoff (`proximo_intento`) de las operaciones
  /// indicadas que sigan PENDIENTE/ERROR, para que la sincronización manual
  /// en curso las reintente de inmediato en lugar de dar por terminada la
  /// pasada con la operación aún oculta por el backoff.
  Future<void> habilitarReintentoInmediato(Iterable<String> uuids) async {
    final lista = uuids.toSet().toList(growable: false);
    if (lista.isEmpty) return;
    await _repo.limpiarProximoIntento(lista);
  }

  Future<SyncSummaryModel> resumen() async {
    final counts = await _repo.resumir();
    return SyncSummaryModel.fromCounts(counts);
  }

  /// [FIX-SYNC] Normaliza las órdenes diferidas heredadas (payload con
  /// `acepta_nuevo_total: false`), reactiva las rechazadas sólo por precio y
  /// limpia los conflictos duplicados que dejaron los reintentos en bucle.
  /// Se ejecuta una vez al arrancar; es idempotente.
  Future<int> normalizarOrdenesDiferidas() async {
    final reactivadas = await _repo.normalizarOrdenesDiferidas();
    for (final uuid in reactivadas) {
      await _conflictRepo.descartarPorOperacion(uuid);
    }
    await _conflictRepo.deduplicarPendientes();
    return reactivadas.length;
  }

  /// [EXAMEN-2] B1.8.c: fecha de la **última sincronización** efectiva
  /// (la confirmación más reciente de una operación).
  Future<DateTime?> ultimaSincronizacion() async {
    final db = _database.database;
    if (db == null) return null;
    final filas = await db.rawQuery(
      'SELECT MAX(fecha_confirmacion) AS ultima FROM operaciones '
      'WHERE tenant_id = ? AND fecha_confirmacion IS NOT NULL',
      <Object?>[_tenantId],
    );
    if (filas.isEmpty) return null;
    final valor = filas.first['ultima']?.toString();
    if (valor == null || valor.isEmpty) return null;
    return DateTime.tryParse(valor);
  }

  Future<int> limpiarConfirmadas({Duration? antiguedad}) async {
    final limite = DateTime.now()
        .subtract(antiguedad ?? const Duration(days: 30))
        .toUtc()
        .toIso8601String();
    final db = _database.database;
    if (db == null) return 0;
    return db.delete(
      'operaciones',
      where:
          "tenant_id = ? AND estado_sincronizacion IN "
          "('CONFIRMADA', 'DUPLICADA') AND "
          "COALESCE(fecha_confirmacion, fecha_actualizacion) < ?",
      whereArgs: <Object?>[_tenantId, limite],
    );
  }

  Future<void> aplicarResultado({
    required String uuidOperacion,
    required String estado,
    String? motivo,
    Map<String, Object?>? detalle,
    String? tipoConflicto,
    Map<String, Object?>? datosLocal,
    Map<String, Object?>? datosCentral,
    // [EXAMEN-2] B1.5.d: el backend pide reintentar la operación.
    bool solicitarReintento = false,
    // [EXAMEN-2] B1.4.b: tipo de la operación (para detener el tipo si
    // llega un ERROR_CRITICO).
    String? tipoOperacion,
  }) async {
    final normalizado = estado.toUpperCase();
    await _repo.actualizarEstado(
      uuidOperacion,
      normalizado,
      ultimoError: motivo,
      resultadoJson: detalle == null ? null : jsonEncode(detalle),
    );
    // [EXAMEN-2] B1.4.d: el resultado se aplica también a la fila local del
    // dominio (devolución/reposición): sin esto una devolución sincronizada
    // nunca transitaba a `ERROR_VENTA_INVALIDA` ni `PENDIENTE_REEMBOLSO`.
    await _aplicarEnDominio(uuidOperacion, normalizado, detalle);
    // [EXAMEN-2] B2.9: al confirmarse la operación, el comprobante **temporal**
    // pasa a definitivo (`es_temporal = 0`).
    if (normalizado == 'CONFIRMADA') {
      await _confirmarComprobante(uuidOperacion);
    }
    if (normalizado == 'CONFLICTO' ||
        normalizado == 'CONFLICTO_MANUAL' ||
        normalizado == 'RECHAZADA' ||
        normalizado == 'ERROR_DATOS') {
      // [EXAMEN-2] B1.5.a–e: se clasifica el conflicto con el contrato del
      // backend (`TipoConflicto` / `EstrategiaResolucion`) para decidir el
      // estado local, la resolubilidad automática y si requiere intervención
      // del servidor (pago ya capturado / duplicado).
      final clasificacion = ConflictClassifier.clasificar(
        detalle ?? <String, Object?>{'tipo_conflicto': tipoConflicto ?? ''},
      );
      final tipo = tipoConflicto ?? clasificacion.tipo;
      final estadoConflicto = normalizado == 'RECHAZADA'
          ? (clasificacion.estado == EstadosConflicto.errorDatos
                ? EstadosConflicto.errorDatos
                : EstadosConflicto.conflicto)
          : clasificacion.estado;
      await _conflictRepo.crear(
        tipo: tipo,
        motivo: motivo ?? 'La operación fue rechazada por el servidor.',
        uuidOperacion: uuidOperacion,
        datosLocal: datosLocal == null ? null : jsonEncode(datosLocal),
        datosCentral: datosCentral != null
            ? jsonEncode(datosCentral)
            : (detalle?['datos_central'] is Map
                ? jsonEncode(detalle!['datos_central'])
                : null),
        accion: 'REVISAR',
        estado: estadoConflicto,
      );
      // [EXAMEN-2] B1.5.d: si el pago ya estaba capturado, el reembolso es
      // del backend (RN-018): la app avisa pero no intenta cobrar ni
      // devolver dinero.
      if (ConflictClassifier.requiereIntervencionServidor(tipo)) {
        await _audit?.registrar(
          tenantId: _tenantId,
          tipo: 'CONFLICTO_REQUIERE_SERVIDOR',
          mensaje:
              'El conflicto $tipo requiere intervención del servidor '
              '(reembolso o cobro duplicado).',
          datos: <String, dynamic>{
            'uuid_operacion': uuidOperacion,
            'tipo_conflicto': tipo,
          },
        );
      }
      // [EXAMEN-2] B1.5.a: si el precio cambió menos del 5%, se resuelve
      // automáticamente y se notifica post-facto (flujo alterno 1 del CU09).
      if (tipo == TiposConflicto.precioDesactualizado &&
          clasificacion.resolubleAutomaticamente) {
        await _audit?.registrar(
          tenantId: _tenantId,
          tipo: 'CONFLICTO_RESUELTO_AUTOMATICO',
          mensaje:
              'El precio cambió '
              '${(clasificacion.diferenciaPorcentaje * 100).toStringAsFixed(1)}% '
              '(≤ 5%): se aplicó el precio central.',
          datos: <String, dynamic>{
            'uuid_operacion': uuidOperacion,
            'diferencia_porcentaje': clasificacion.diferenciaPorcentaje,
          },
        );
      }
    }
    // [FIX-SYNC] El reintento automático sólo aplica a estados no terminales
    // (como el frontend web). RECHAZADA/CONFLICTO/ERROR_DATOS/ERROR_CRITICO
    // quedan para revisión manual: antes el `reintentar=true` del servidor
    // las devolvía a PENDIENTE y el mismo payload se reenviaba en bucle.
    const estadosReintentables = {'PENDIENTE', 'ERROR', 'ENVIADA', 'EN_PROCESO'};
    if (solicitarReintento && estadosReintentables.contains(normalizado)) {
      await reintentar(uuidOperacion);
    }
    // [EXAMEN-2] B1.4.b: un `ERROR_CRITICO` **detiene** el tipo de operación
    // (RN-017): deja de enviarse hasta que se regule la suscripción o el
    // administrador lo reanude.
    if (normalizado == 'ERROR_CRITICO' && tipoOperacion != null) {
      await _detenerTipo(tipoOperacion, true);
      await _audit?.registrar(
        tenantId: _tenantId,
        tipo: 'SINCRONIZACION_TIPO_DETENIDO',
        mensaje:
            'El tipo de operación $tipoOperacion quedó detenido por un error '
            'crítico. Regúliza la suscripción para reanudarlo.',
        datos: <String, dynamic>{
          'tipo_operacion': tipoOperacion,
          'uuid_operacion': uuidOperacion,
        },
      );
    }
  }

  /// [EXAMEN-2] B2.9: el comprobante temporal pasa a **definitivo** cuando el
  /// servidor confirma la operación.
  Future<void> _confirmarComprobante(String uuidOperacion) async {
    final db = _database.database;
    if (db == null) return;
    try {
      await db.update(
        'comprobantes',
        <String, Object?>{
          'es_temporal': 0,
          'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'uuid_offline = ? AND tenant_id = ?',
        whereArgs: <Object?>[uuidOperacion, _tenantId],
      );
    } catch (_) {
      // El comprobante es informativo: su fallo no rompe la sincronización.
    }
  }

  /// [EXAMEN-2] B1.4.d: aplica el resultado de la sincronización a la fila
  /// local del dominio (devoluciones/reposiciones).
  ///
  /// Se inyecta desde `main.dart` con el `ReturnService`; si no se inyecta,
  /// la operación simplemente no tiene fila de dominio que actualizar.
  Future<void> _aplicarEnDominio(
    String uuidOperacion,
    String estado,
    Map<String, Object?>? detalle,
  ) async {
    final aplicar = _aplicarResultadoDominio;
    if (aplicar == null) return;
    try {
      await aplicar(uuidOperacion, estado, detalle);
    } catch (_) {
      // El dominio es best-effort: no debe romper la sincronización.
    }
  }

  /// [EXAMEN-2] B1.4.d: callback para aplicar el resultado al dominio.
  ///
  /// Firma: `(uuidOperacion, estado, detalle) -> Future<void>`.
  Future<void> Function(
    String uuidOperacion,
    String estado,
    Map<String, Object?>? detalle,
  )? _aplicarResultadoDominio;

  /// [EXAMEN-2] B1.4.d: registra el callback de aplicación al dominio.
  set aplicarResultadoDominio(
    Future<void> Function(
      String uuidOperacion,
      String estado,
      Map<String, Object?>? detalle,
    )?
    callback,
  ) {
    _aplicarResultadoDominio = callback;
  }
}
