// [EXAMEN-2] Ola 5 / B2: libro de movimientos `movimientos_inventario`
// (v5, RN-021/RNF-21): trazabilidad offline de inventario en CU13/CU18.
import 'package:fashionstore_mobile/core/database/repositories/local_return_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fase3_helpers.dart';

Future<List<Map<String, Object?>>> movimientosDe(
  LocalReturnRepository repo,
  String uuid,
) async {
  final db = repo.db;
  return db.query(
    'movimientos_inventario',
    where: 'uuid_offline = ?',
    whereArgs: <Object?>[uuid],
    orderBy: 'id ASC',
  );
}

void main() {
  test(
    'CU13: la devolución registra un movimiento DEVOLUCION con usuario y motivo',
    () async {
      final servicios = await crearServicios();
      final repo = LocalReturnRepository(
        servicios.db.database!,
        tenantId: tenantFase3,
        usuarioId: 77,
      );
      await repo.registrar(
        uuid: 'uuid-mov-dev',
        cabecera: <String, Object?>{
          'tipo': 'DEVOLUCION',
          'estado': 'PENDIENTE_SINCRONIZACION',
          'es_offline': 1,
          'motivo': 'TALLA_INCORRECTA',
        },
        items: <Map<String, Object?>>[
          <String, Object?>{
            'variante_producto_id': 101,
            'cantidad': 1,
            'precio_unitario': 100,
            'estado_item': 'DEVUELTA',
          },
        ],
        movimientosStock: const <({
          int varianteId,
          int delta,
          int deltaReserva,
          String tipo,
        })>[
          (varianteId: 101, delta: 1, deltaReserva: 0, tipo: 'DEVOLUCION'),
        ],
        sucursalId: 1,
      );

      final filas = await movimientosDe(repo, 'uuid-mov-dev');
      expect(filas, hasLength(1));
      expect(filas.single['tipo'], 'DEVOLUCION');
      expect(filas.single['variante_producto_id'], 101);
      expect(filas.single['cantidad'], 1);
      expect(filas.single['usuario_id'], 77);
      expect(filas.single['sucursal_id'], 1);
      expect(filas.single['tenant_id'], tenantFase3);
      expect(filas.single['motivo'], 'TALLA_INCORRECTA');
      await servicios.db.cerrar();
    },
  );

  test(
    'CU18/RN-025: la reposición registra ENTRADA y SALIDA en la misma operación',
    () async {
      final servicios = await crearServicios();
      final repo = LocalReturnRepository(
        servicios.db.database!,
        tenantId: tenantFase3,
      );
      await repo.registrar(
        uuid: 'uuid-mov-rep',
        cabecera: <String, Object?>{
          'tipo': 'REPOSICION',
          'numero_reposicion': 'REP-LOCAL-MOV000001',
          'estado': 'PENDIENTE_SINCRONIZACION',
          'es_offline': 1,
        },
        items: <Map<String, Object?>>[
          <String, Object?>{
            'variante_producto_id': 101,
            'variante_cambio_id': 102,
            'cantidad': 1,
            'precio_unitario': 100,
            'precio_variante_nueva': 120,
            'diferencia': 20,
            'subtotal_diferencia': 20,
            'estado_item': 'NUEVA',
          },
        ],
        movimientosStock: const <({
          int varianteId,
          int delta,
          int deltaReserva,
          String tipo,
        })>[
          (varianteId: 101, delta: 2, deltaReserva: -2, tipo: 'REPOSICION_ENTRADA'),
          (varianteId: 102, delta: -1, deltaReserva: 1, tipo: 'REPOSICION_SALIDA'),
        ],
        sucursalId: 1,
      );

      final filas = await movimientosDe(repo, 'uuid-mov-rep');
      expect(filas, hasLength(2));
      expect(filas[0]['tipo'], 'REPOSICION_ENTRADA');
      expect(filas[0]['variante_producto_id'], 101);
      // La cantidad del libro es siempre positiva (delta.abs()).
      expect(filas[0]['cantidad'], 2);
      expect(filas[1]['tipo'], 'REPOSICION_SALIDA');
      expect(filas[1]['variante_producto_id'], 102);
      expect(filas[1]['cantidad'], 1);
      await servicios.db.cerrar();
    },
  );

  test(
    'B1.10.i: el cobro de la diferencia queda en el libro como COBRO_DIFERENCIA',
    () async {
      final servicios = await crearServicios();
      final repo = LocalReturnRepository(
        servicios.db.database!,
        tenantId: tenantFase3,
      );
      await repo.registrar(
        uuid: 'uuid-mov-pago',
        cabecera: <String, Object?>{
          'tipo': 'REPOSICION',
          'numero_reposicion': 'REP-LOCAL-MOV000002',
          'estado': 'PENDIENTE_SINCRONIZACION',
          'es_offline': 1,
        },
        items: const <Map<String, Object?>>[],
        movimientosPago: const <({int varianteId, double monto, String medioPago})>[
          (varianteId: 102, monto: 20.0, medioPago: 'EFECTIVO'),
        ],
        sucursalId: 1,
      );

      final filas = await movimientosDe(repo, 'uuid-mov-pago');
      expect(filas, hasLength(1));
      expect(filas.single['tipo'], 'COBRO_DIFERENCIA');
      expect(filas.single['variante_producto_id'], 102);
      // El pago no mueve unidades: cantidad = 0 y el motivo describe el medio.
      expect(filas.single['cantidad'], 0);
      expect(filas.single['motivo'], 'Diferencia de precio · EFECTIVO');
      await servicios.db.cerrar();
    },
  );

  test('el libro separa operaciones distintas por uuid_offline', () async {
    final servicios = await crearServicios();
    final repo = LocalReturnRepository(
      servicios.db.database!,
      tenantId: tenantFase3,
    );
    for (final (i, uuid) in const ['uuid-mov-a', 'uuid-mov-b'].indexed) {
      await repo.registrar(
        uuid: uuid,
        cabecera: <String, Object?>{
          'tipo': 'DEVOLUCION',
          'estado': 'PENDIENTE_SINCRONIZACION',
          'es_offline': 1,
        },
        items: const <Map<String, Object?>>[],
        movimientosStock: <({
          int varianteId,
          int delta,
          int deltaReserva,
          String tipo,
        })>[
          (varianteId: 101, delta: i + 1, deltaReserva: 0, tipo: 'DEVOLUCION'),
        ],
        sucursalId: 1,
      );
    }
    expect(await movimientosDe(repo, 'uuid-mov-a'), hasLength(1));
    expect(await movimientosDe(repo, 'uuid-mov-b'), hasLength(1));
    final todos = await servicios.db.database!.query('movimientos_inventario');
    expect(todos, hasLength(2));
    await servicios.db.cerrar();
  });
}
