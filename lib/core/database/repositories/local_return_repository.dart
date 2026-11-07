import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../models/return_request_model.dart';
import 'local_operation_repository.dart';

/// [EXAMEN-2] Repositorio de devoluciones y reposiciones locales (CU13/CU18).
///
/// La devolución pura solo reingresa inventario (entrada de la prenda devuelta,
/// sin salida); la reposición mueve inventario en dos sentidos en una sola
/// transacción SQLite (RN-025: `REPOSICION_ENTRADA` + `REPOSICION_SALIDA`).
class LocalReturnRepository extends LocalOperationRepository {
  LocalReturnRepository(super.db, {required super.tenantId})
    : super(
        tablaCabecera: 'devoluciones_locales',
        columnaUuid: 'uuid_offline',
        tablaItems: 'items_devolucion_local',
      );

  /// Registra una devolución o reposición offline con su detalle.
  ///
  /// [movimientosStock] se aplica dentro de la misma transacción:
  /// `+cantidad` para entrada (prenda devuelta) y `-cantidad` para salida
  /// (prenda nueva). La reserva provisional (`cantidad_reservada`) también se
  /// libera en la misma transacción.
  Future<void> registrar({
    required String uuid,
    required Map<String, Object?> cabecera,
    required List<Map<String, Object?>> items,
    List<({int varianteId, int delta, int deltaReserva})> movimientosStock =
        const [],
    required int sucursalId,
  }) async {
    Future<void> ejecutar(DatabaseExecutor executor) async {
      await executor.insert('devoluciones_locales', <String, Object?>{
        ...cabecera,
        'uuid_offline': uuid,
        'tenant_id': tenantId,
        'sucursal_id': sucursalId,
        'fecha_registro_local':
            cabecera['fecha_registro_local'] ??
            DateTime.now().toUtc().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      });
      for (final item in items) {
        await executor.insert('items_devolucion_local', <String, Object?>{
          ...item,
          'uuid_offline': uuid,
          'tenant_id': tenantId,
          'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
        });
      }
      for (final movimiento in movimientosStock) {
        final filas = await executor.query(
          'stock',
          where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
          whereArgs: <Object?>[movimiento.varianteId, sucursalId, tenantId],
          limit: 1,
        );
        if (filas.isEmpty) {
          if (movimiento.delta > 0) {
            await executor.insert('stock', <String, Object?>{
              'variante_id': movimiento.varianteId,
              'sucursal_id': sucursalId,
              'tenant_id': tenantId,
              'cantidad': movimiento.delta,
              'cantidad_reservada': 0,
              'stock_minimo': 0,
              'fecha_actualizacion':
                  DateTime.now().toUtc().toIso8601String(),
            });
          }
          continue;
        }
        final actual = (filas.first['cantidad'] as num?)?.toInt() ?? 0;
        final reservada =
            (filas.first['cantidad_reservada'] as num?)?.toInt() ?? 0;
        await executor.update(
          'stock',
          <String, Object?>{
            'cantidad': (actual + movimiento.delta).clamp(0, 1 << 30),
            'cantidad_reservada': (reservada + movimiento.deltaReserva)
                .clamp(0, 1 << 30),
            'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'variante_id = ? AND sucursal_id = ? AND tenant_id = ?',
          whereArgs: <Object?>[movimiento.varianteId, sucursalId, tenantId],
        );
      }
    }

    final database = db;
    if (database is Database) {
      await database.transaction<void>((txn) async {
        await ejecutar(txn);
      });
      return;
    }
    await ejecutar(database);
  }

  /// Detalle completo: cabecera + prenda devuelta y prenda nueva por línea.
  Future<ReturnRequestModel?> detalle(String uuid) async {
    final fila = await obtenerPorUuid(uuid);
    if (fila == null) return null;
    final itemsFilas = await listarItems(uuid);
    final items = itemsFilas
        .map((item) => ReturnItemModel.fromJson({
          'id': item['id'],
          'solicitud_id': 0,
          'detalle_orden_id': item['detalle_orden_id'],
          'variante_producto_id': item['variante_producto_id'],
          'cantidad': item['cantidad'],
          'variante_cambio_id': item['variante_cambio_id'],
          'precio_unitario': item['precio_unitario'],
          'precio_variante_nueva': item['precio_variante_nueva'],
          'diferencia': item['diferencia'],
          'subtotal_diferencia': item['subtotal_diferencia'],
          'estado_item': item['estado_item'],
        }))
        .toList(growable: false);
    return ReturnRequestModel.fromLocal(fila, items);
  }

  Future<List<ReturnRequestModel>> listar({String? tipo}) async {
    final filas = await consultar(
      'devoluciones_locales',
      where: tipo == null
          ? 'tenant_id = ?'
          : "tenant_id = ? AND tipo = ?",
      whereArgs: tipo == null
          ? <Object?>[tenantId]
          : <Object?>[tenantId, tipo.toUpperCase()],
      orderBy: 'fecha_actualizacion DESC',
    );
    final resultado = <ReturnRequestModel>[];
    for (final fila in filas) {
      resultado.add(
        ReturnRequestModel.fromLocal(
          fila,
          await _items(fila['uuid_offline']?.toString() ?? ''),
        ),
      );
    }
    return resultado;
  }

  Future<List<ReturnRequestModel>> pendientesDeSync() async {
    final filas = await consultar(
      'devoluciones_locales',
      where:
          "tenant_id = ? AND estado IN ('PENDIENTE_SINCRONIZACION', 'PENDIENTE')",
      whereArgs: <Object?>[tenantId],
      orderBy: 'fecha_actualizacion DESC',
    );
    final resultado = <ReturnRequestModel>[];
    for (final fila in filas) {
      resultado.add(
        ReturnRequestModel.fromLocal(
          fila,
          await _items(fila['uuid_offline']?.toString() ?? ''),
        ),
      );
    }
    return resultado;
  }

  Future<List<ReturnItemModel>> _items(String uuid) async {
    final filas = await listarItems(uuid);
    return filas
        .map((item) => ReturnItemModel.fromJson({
          'id': item['id'],
          'solicitud_id': 0,
          'detalle_orden_id': item['detalle_orden_id'],
          'variante_producto_id': item['variante_producto_id'],
          'cantidad': item['cantidad'],
          'variante_cambio_id': item['variante_cambio_id'],
          'precio_unitario': item['precio_unitario'],
          'precio_variante_nueva': item['precio_variante_nueva'],
          'diferencia': item['diferencia'],
          'subtotal_diferencia': item['subtotal_diferencia'],
          'estado_item': item['estado_item'],
        }))
        .toList(growable: false);
  }

  /// Aplica el resultado de la sincronización a la fila local.
  Future<int> aplicarResultado(
    String uuid, {
    required String estado,
    String? estadoSincronizacion,
    String? numeroReposicion,
  }) async {
    final datos = <String, Object?>{
      'estado': estado,
      'estado_sincronizacion': estadoSincronizacion ?? estado,
    };
    if (numeroReposicion != null) {
      datos['numero_reposicion'] = numeroReposicion;
    }
    return actualizarPorClaves(
      'devoluciones_locales',
      datos,
      <String, Object?>{'uuid_offline': uuid},
    );
  }

  /// Resumen para el centro de sincronización y la cuota (nunca borra
  /// pendientes: ver `StorageQuotaService`).
  Future<int> contarPendientes() {
    return contarPorClaves(
      'devoluciones_locales',
      <String, Object?>{'estado': 'PENDIENTE_SINCRONIZACION'},
    );
  }

  /// Serializa el payload de la operación de cola (contrato §9.5).
  static Map<String, Object?> payloadCola(ReturnRequestModel solicitud) =>
      <String, Object?>{
        'uuid_offline': solicitud.uuidOffline,
        'tipo': solicitud.tipo.toUpperCase(),
        'orden_origen_id': solicitud.ordenId == 0 ? null : solicitud.ordenId,
        'motivo': solicitud.motivo,
        'sucursal_id': solicitud.sucursalId,
        'items': [
          for (final item in solicitud.items)
            {
              'detalle_orden_id': item.detalleOrdenId,
              'variante_producto_id': item.varianteProductoId,
              'variante_cambio_id': item.varianteCambioId,
              'cantidad': item.cantidad,
              'precio_unitario': item.precioUnitario,
            },
        ],
        'payload_json': jsonEncode({'uuid': solicitud.uuidOffline}),
      };
}
