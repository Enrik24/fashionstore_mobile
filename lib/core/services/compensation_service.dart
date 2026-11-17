// [EXAMEN-2] CU19: compensación de ventas offline rechazadas (modo cajero).
// La app SOLO consulta y confirma el reembolso en efectivo en caja; el
// reembolso por pasarela, la nota de crédito y el reintento son del backend
// o de la PWA (D-MOV-20). Nunca ejecuta pagos por pasarela.
import 'package:dio/dio.dart';

import '../../config/constants.dart';
import '../database/local_database_service.dart';
import '../database/repositories/local_compensacion_repository.dart';
import '../models/api_response.dart';
import '../models/compensation_model.dart';
import 'api_service.dart';
import 'local_audit_service.dart';

class CompensationService {
  CompensationService({
    required LocalDatabaseService database,
    required int tenantId,
    ApiService? apiService,
    LocalAuditService? audit,
    // [EXAMEN-2] B0.4: id del usuario para estampar `usuario_id`.
    int? usuarioId,
  }) : _database = database,
       _tenantId = tenantId,
       _apiService = apiService,
       _audit = audit,
       _usuarioId = usuarioId;

  final LocalDatabaseService _database;
  final int _tenantId;
  final ApiService? _apiService;
  final LocalAuditService? _audit;
  // [EXAMEN-2] B0.4.
  final int? _usuarioId;

  LocalCompensacionRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return LocalCompensacionRepository(
      db,
      tenantId: _tenantId,
      usuarioId: _usuarioId,
    );
  }

  bool _es404(ApiException e) =>
      e.statusCode == 404 || e.statusCode == 501;

  /// `GET /offline/compensaciones` con degradación a la caché local.
  Future<List<CompensacionModel>> listar({String? estado}) async {
    final api = _apiService;
    if (api != null) {
      try {
        final response = await api.dio.get(
          AppConstants.epOfflineCompensaciones,
          queryParameters: {if (estado != null) 'estado': estado},
        );
        final datos = response.data;
        List<CompensacionModel> remotas = const [];
        if (datos is Map<String, dynamic>) {
          final lista = datos['compensaciones'];
          if (lista is List) {
            remotas = lista
                .map(
                  (e) => CompensacionModel.fromJson(e as Map<String, dynamic>),
                )
                .toList(growable: false);
          }
        } else if (datos is List) {
          remotas = datos
              .map(
                (e) => CompensacionModel.fromJson(e as Map<String, dynamic>),
              )
              .toList(growable: false);
        }
        await sincronizarCacheRemotas(remotas);
        return remotas;
      } on ApiException catch (e) {
        if (_es404(e)) return _repo.listar(estado: estado);
        rethrow;
      } catch (_) {
        return _repo.listar(estado: estado);
      }
    }
    return _repo.listar(estado: estado);
  }

  /// `GET /offline/compensaciones/{id}` con degradación a la caché local.
  Future<CompensacionModel?> detalle(int id) async {
    final api = _apiService;
    if (api != null) {
      try {
        final response = await api.dio.get(
          '${AppConstants.epOfflineCompensaciones}/$id',
        );
        if (response.data is Map<String, dynamic>) {
          final modelo = CompensacionModel.fromJson(
            response.data as Map<String, dynamic>,
          );
          await _repo.guardarCompensacion(modelo);
          return modelo;
        }
      } catch (_) {
        // 404/501 o sin red: leer la caché.
      }
    }
    return _repo.obtener(id);
  }

  /// Confirma la entrega del reembolso en efectivo (D-MOV-20).
  ///
  /// - Solo el rol cajero/encargado (`esCajero`); si no, lanza.
  /// - Idempotente: una compensación `COMPLETADA` no se vuelve a confirmar.
  /// - Nunca ejecuta reembolsos por pasarela: si el tipo no es efectivo,
  ///   lanza sin tocar el estado.
  Future<CompensacionModel> confirmarEfectivo(
    int id, {
    required bool esCajero,
    required int cajeroId,
  }) async {
    if (!esCajero) {
      throw StateError('Solo el modo cajero puede confirmar el efectivo');
    }
    final actual = await _repo.obtener(id);
    if (actual == null) {
      throw StateError('Compensación #$id no encontrada en la caché local');
    }
    if (actual.estaCompletada) {
      throw StateError('La compensación ya fue completada');
    }
    if (!actual.esEfectivo) {
      throw StateError(
        'Solo el reembolso en efectivo se confirma en caja; '
        'los demás tipos los procesa el sistema',
      );
    }
    final api = _apiService;
    if (api != null) {
      try {
        final response = await api.dio.post(
          '${AppConstants.epOfflineCompensaciones}/$id/confirmar-efectivo',
        );
        if (response.data is Map<String, dynamic>) {
          final modelo = CompensacionModel.fromJson(
            response.data as Map<String, dynamic>,
          );
          await _repo.guardarCompensacion(modelo);
          final completada = modelo.copyWith(
            fechaCompletado: modelo.fechaCompletado ?? DateTime.now(),
            resueltoPor: cajeroId.toString(),
          );
          await _repo.guardarCompensacion(completada);
          await _auditar('confirmada', id);
          return completada;
        }
        // [EXAMEN-2] B1.9.c: la respuesta **no** es un mapa. Antes se caía al
        // camino local de abajo y marcaba la compensación como COMPLETADA
        // **sin confirmación del servidor** (falso éxito: el cajero creía
        // haber entregado el efectivo y el backend no lo registró).
        await _repo.actualizarEstado(
          id,
          estado: 'FALLIDA',
          errorDetalle: 'Respuesta inesperada del servidor al confirmar.',
        );
        throw StateError(
          'El servidor no confirmó la entrega del efectivo. '
          'La compensación quedó pendiente y no se cobró de nuevo.',
        );
      } on ApiException catch (e) {
        if (!_es404(e)) {
          // [EXAMEN-2] B1.9.d: error de red o 5xx ⇒ FALLIDA, no "completada".
          await _repo.actualizarEstado(
            id,
            estado: 'FALLIDA',
            errorDetalle: e.message,
          );
          rethrow;
        }
        // 404/501 N3: degradación, se aplica en local sin romper el flujo.
      } on StateError {
        rethrow;
      } on DioException catch (e) {
        // [EXAMEN-2] B1.9.c/d: respuesta malformada o error de red ⇒ la
        // compensación **no** se da por entregada.
        await _repo.actualizarEstado(
          id,
          estado: 'FALLIDA',
          errorDetalle: e.message,
        );
        throw StateError(
          'No se pudo confirmar la entrega del efectivo: ${e.message}',
        );
      } catch (e) {
        if (e is StateError) rethrow;
        // [EXAMEN-2] B1.9.d: error de red inesperado ⇒ FALLIDA.
        await _repo.actualizarEstado(
          id,
          estado: 'FALLIDA',
          errorDetalle: e.toString(),
        );
        rethrow;
      }
    }
    final completada = actual.copyWith(
      estado: 'COMPLETADA',
      fechaCompletado: DateTime.now(),
      resueltoPor: cajeroId.toString(),
    );
    await _repo.actualizarEstado(
      id,
      estado: 'COMPLETADA',
      fechaCompletado: completada.fechaCompletado,
      resueltoPor: cajeroId.toString(),
    );
    await _repo.guardarCompensacion(completada);
    await _auditar('confirmada-efectivo-local', id);
    return (await _repo.obtener(id)) ?? completada;
  }

  /// [EXAMEN-2] B1.9.f: listado **sólo** de la caché local (modo lectura
  /// sin conexión, per CU19).
  Future<List<CompensacionModel>> listarLocal({String? estado}) =>
      _repo.listar(estado: estado);

  /// [EXAMEN-2] B1.9.f: resumen **sólo** de la caché local.
  Future<Map<String, Object?>> resumenLocal() => _repo.resumen();

  /// [EXAMEN-2] B1.9.a: reintento del reembolso por pasarela.
  ///
  /// El backend expone `POST /offline/compensaciones/{id}/reintentar`. La app
  /// **no ejecuta** el reembolso (RN-008: sin conexión no hay pasarela): lo
  /// solicita al backend, que sí lo ejecuta.
  ///
  /// Sólo tiene sentido con conexión; sin ella la compensación queda `FALLIDA`
  /// y se reintenta más tarde (B1.9.d).
  Future<CompensacionModel> reintentar(int id) async {
    final api = _apiService;
    if (api == null) {
      throw StateError('No hay conexión para reintentar el reembolso');
    }
    try {
      final response = await api.dio.post(
        '${AppConstants.epOfflineCompensaciones}/$id/reintentar',
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final modelo = CompensacionModel.fromJson(data);
        await _repo.guardarCompensacion(modelo);
        await _auditar('reintentada', id);
        return modelo;
      }
      throw StateError('El servidor no devolvió la compensación reintentada');
    } on ApiException catch (e) {
      if (_es404(e)) {
        // El backend todavía no soporta el reintento: se marca como fallida
        // para que el cajero lo intente más tarde.
        await _repo.actualizarEstado(id, estado: 'FALLIDA');
        rethrow;
      }
      // Error de red o 5xx: se marca FALLIDA con el detalle del error.
      await _repo.actualizarEstado(
        id,
        estado: 'FALLIDA',
        errorDetalle: e.message,
      );
      rethrow;
    } catch (e) {
      await _repo.actualizarEstado(
        id,
        estado: 'FALLIDA',
        errorDetalle: e.toString(),
      );
      rethrow;
    }
  }

  /// `GET /offline/compensaciones/resumen` con respaldo local.
  Future<Map<String, Object?>> resumen() async {
    final api = _apiService;
    if (api != null) {
      try {
        final response = await api.dio.get(
          AppConstants.epOfflineCompensacionesResumen,
        );
        if (response.data is Map<String, dynamic>) {
          return response.data as Map<String, Object?>;
        }
      } on ApiException catch (e) {
        if (_es404(e)) return _repo.resumen();
        rethrow;
      } catch (_) {
        return _repo.resumen();
      }
    }
    return _repo.resumen();
  }

  /// Compensaciones pendientes (solo significativo en modo cajero).
  Future<int> pendientesCount() => _repo.pendientesCount();

  /// Actualiza la caché con la lista remota (sin duplicar, RN-005).
  Future<int> sincronizarCache() async {
    final api = _apiService;
    if (api == null) return _repo.pendientesCount();
    try {
      final response = await api.dio.get(
        AppConstants.epOfflineCompensaciones,
      );
      final datos = response.data;
      final lista = <CompensacionModel>[];
      if (datos is Map<String, dynamic>) {
        final cruda = datos['compensaciones'];
        if (cruda is List) {
          lista.addAll(
            cruda
                .map(
                  (e) => CompensacionModel.fromJson(e as Map<String, dynamic>),
                )
                .toList(),
          );
        }
      } else if (datos is List) {
        lista.addAll(
          datos
              .map(
                (e) => CompensacionModel.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
        );
      }
      return sincronizarCacheRemotas(lista);
    } on ApiException catch (e) {
      if (_es404(e)) return _repo.pendientesCount();
      rethrow;
    } catch (_) {
      return _repo.pendientesCount();
    }
  }

  Future<int> sincronizarCacheRemotas(List<CompensacionModel> lista) =>
      _repo.guardarCache(lista);

  Future<void> _auditar(String accion, int id) async {
    await _audit?.registrar(
      tenantId: _tenantId,
      tipo: 'COMPENSACION',
      mensaje: 'Compensación #$id $accion',
    );
  }
}
