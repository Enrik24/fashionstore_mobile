// [EXAMEN-2] CU19: compensación de ventas offline rechazadas (modo cajero).
// La app SOLO consulta y confirma el reembolso en efectivo en caja; el
// reembolso por pasarela, la nota de crédito y el reintento son del backend
// o de la PWA (D-MOV-20). Nunca ejecuta pagos por pasarela.
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
  }) : _database = database,
       _tenantId = tenantId,
       _apiService = apiService,
       _audit = audit;

  final LocalDatabaseService _database;
  final int _tenantId;
  final ApiService? _apiService;
  final LocalAuditService? _audit;

  LocalCompensacionRepository get _repo {
    final db = _database.database;
    if (db == null) throw StateError('La base local no está abierta.');
    return LocalCompensacionRepository(db, tenantId: _tenantId);
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
      } on ApiException catch (e) {
        if (!_es404(e)) rethrow;
        // 404/501 N3: degradación, se aplica en local sin romper el flujo.
      } catch (_) {
        // Error de red inesperado: degradación local también aplica.
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
