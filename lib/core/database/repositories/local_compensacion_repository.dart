import 'dart:convert';

import '../../models/compensation_model.dart';
import 'tenant_local_repository.dart';

/// [EXAMEN-2] Caché de solo lectura de compensaciones (CU19, modo cajero).
///
/// El repositorio no ejecuta reembolsos por pasarela: solo persiste el espejo
/// de `GET /offline/compensaciones*` para operar sin red y para evidenciar
/// que un reintento de sincronización no duplica la compensación.
class LocalCompensacionRepository extends TenantLocalRepository {
  LocalCompensacionRepository(super.db, {required super.tenantId});

  static const String tabla = 'compensaciones';

  /// Guarda una compensación deduplicando por `id` y por
  /// `operacion_offline_id` (unique de backend, RN-005).
  Future<void> guardarCompensacion(CompensacionModel compensacion) async {
    final datos = <String, Object?>{
      ...compensacion.toMap(),
      'datos_json': jsonEncode({
        'origen': 'backend-offline-compensaciones',
      }),
    };
    // Dedupe por operacion_offline_id: un resync con el mismo id actualiza
    // la fila existente en vez de insertar un duplicado.
    final porOperacion = compensacion.operacionOfflineId == null
        ? null
        : await consultar(
            tabla,
            where: 'operacion_offline_id = ? AND tenant_id = ?',
            whereArgs: <Object?>[compensacion.operacionOfflineId, tenantId],
            limit: 1,
          );
    if (porOperacion != null && porOperacion.isNotEmpty) {
      final idExistente = (porOperacion.first['id'] as num?)?.toInt()
          ?? compensacion.id;
      final actualizable = <String, Object?>{...datos, 'id': idExistente};
      await guardarPorClave(tabla, 'id', idExistente, actualizable);
      return;
    }
    await guardarPorClave(
      tabla,
      'id',
      compensacion.id == 0 ? null : compensacion.id,
      datos,
    );
  }

  /// Sincroniza la caché completa con la lista del backend.
  Future<int> guardarCache(List<CompensacionModel> lista) async {
    for (final compensacion in lista) {
      await guardarCompensacion(compensacion);
    }
    return lista.length;
  }

  Future<List<CompensacionModel>> listar({String? estado}) async {
    final filas = await consultar(
      tabla,
      where: estado == null
          ? 'tenant_id = ?'
          : 'tenant_id = ? AND estado = ?',
      whereArgs: estado == null
          ? <Object?>[tenantId]
          : <Object?>[tenantId, estado.toUpperCase()],
      orderBy: 'fecha_creacion DESC',
    );
    return filas.map(CompensacionModel.fromMap).toList(growable: false);
  }

  Future<CompensacionModel?> obtener(int id) async {
    final filas = await consultar(
      tabla,
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[id, tenantId],
      limit: 1,
    );
    return filas.isEmpty ? null : CompensacionModel.fromMap(filas.first);
  }

  /// Actualiza solo el estado (p. ej. confirmación de efectivo en caja).
  Future<int> actualizarEstado(
    int id, {
    required String estado,
    DateTime? fechaCompletado,
    String? resueltoPor,
  }) {
    return actualizarPorClaves(
      tabla,
      <String, Object?>{
        'estado': estado.toUpperCase(),
        'fecha_completado': fechaCompletado?.toUtc().toIso8601String(),
        'fecha_resolucion': fechaCompletado?.toUtc().toIso8601String(),
        'resuelto_por': resueltoPor,
      },
      <String, Object?>{'id': id},
    );
  }

  Future<int> countPendientes() {
    return contarPorClaves(
      tabla,
      <String, Object?>{'estado': CompensacionTipos.pendiente},
    );
  }

  Future<int> pendientesCount() async {
    final filas = await consultar(
      tabla,
      where:
          "tenant_id = ? AND estado IN ('PENDIENTE', 'EN_PROCESO')",
      whereArgs: <Object?>[tenantId],
    );
    return filas.length;
  }

  /// Totales por estado y por tipo calculados desde la caché local.
  Future<Map<String, Object?>> resumen() async {
    final filas = await consultar(
      tabla,
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantId],
    );
    final porEstado = <String, int>{};
    final porTipo = <String, int>{};
    for (final fila in filas) {
      final estado = fila['estado']?.toString() ?? 'DESCONOCIDO';
      final tipo = fila['tipo']?.toString() ?? 'DESCONOCIDO';
      porEstado[estado] = (porEstado[estado] ?? 0) + 1;
      porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
    }
    return <String, Object?>{'por_estado': porEstado, 'por_tipo': porTipo};
  }
}
