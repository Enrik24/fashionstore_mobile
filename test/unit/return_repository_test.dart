// [EXAMEN-2] CU13: repositorio de devoluciones (detalle, resultado de sync
// y conteo de pendientes).
import 'package:fashionstore_mobile/core/database/repositories/local_return_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fase3_helpers.dart';

void main() {
  test(
    'registra devolución con detalle y conserva diferencia por línea',
    () async {
      final servicios = await crearServicios();
      final repo = LocalReturnRepository(
        servicios.db.database!,
        tenantId: tenantFase3,
      );
      await repo.registrar(
        uuid: 'uuid-dev-1',
        cabecera: {
          'orden_origen_id': 41,
          'tipo': 'DEVOLUCION',
          'estado': 'PENDIENTE_SINCRONIZACION',
          'estado_sincronizacion': 'PENDIENTE_SINCRONIZACION',
          'es_offline': 1,
          'diferencia_precio': 100,
          'tipo_diferencia': 'SIN_DIFERENCIA',
          'monto_reembolso': 100,
        },
        items: [
          {
            'detalle_orden_id': 55,
            'variante_producto_id': 101,
            'cantidad': 1,
            'precio_unitario': 100,
            'estado_item': 'DEVUELTA',
          },
        ],
        movimientosStock: [(varianteId: 101, delta: 1, deltaReserva: 0)],
        sucursalId: 1,
      );

      final detalle = await repo.detalle('uuid-dev-1');
      expect(detalle, isNotNull);
      expect(detalle!.tipo, 'DEVOLUCION');
      expect(detalle.items.single.varianteProductoId, 101);
      expect(await stockDe(servicios.db, 101), 11);
      expect(await repo.contarPendientes(), 1);
      await servicios.db.cerrar();
    },
  );

  test('aplicarResultado cambia ERROR_VENTA_INVALIDA y PENDIENTE_REEMBOLSO', () async {
    final servicios = await crearServicios();
    final repo = LocalReturnRepository(
      servicios.db.database!,
      tenantId: tenantFase3,
    );
    await repo.registrar(
      uuid: 'uuid-dev-2',
      cabecera: {
        'tipo': 'DEVOLUCION',
        'estado': 'PENDIENTE_SINCRONIZACION',
        'estado_sincronizacion': 'PENDIENTE_SINCRONIZACION',
        'es_offline': 1,
      },
      items: const [],
      sucursalId: 1,
    );
    await repo.aplicarResultado(
      'uuid-dev-2',
      estado: 'ERROR_VENTA_INVALIDA',
    );
    expect((await repo.detalle('uuid-dev-2'))?.estado, 'ERROR_VENTA_INVALIDA');
    // Ya no es pendiente de sync: el conteo baixa.
    expect(await repo.contarPendientes(), 0);

    await repo.registrar(
      uuid: 'uuid-dev-3',
      cabecera: {
        'tipo': 'DEVOLUCION',
        'estado': 'PENDIENTE',
        'estado_sincronizacion': 'PENDIENTE',
        'es_offline': 1,
      },
      items: const [],
      sucursalId: 1,
    );
    await repo.aplicarResultado('uuid-dev-3', estado: 'PENDIENTE_REEMBOLSO');
    expect(
      (await repo.detalle('uuid-dev-3'))?.estado,
      'PENDIENTE_REEMBOLSO',
    );
    await servicios.db.cerrar();
  });

  test('listar filtra por tipo DEVOLUCION y REPOSICION', () async {
    final servicios = await crearServicios();
    final repo = LocalReturnRepository(
      servicios.db.database!,
      tenantId: tenantFase3,
    );
    await repo.registrar(
      uuid: 'uuid-dev-4',
      cabecera: {
        'tipo': 'DEVOLUCION',
        'estado': 'COMPLETADA',
        'es_offline': 1,
      },
      items: const [],
      sucursalId: 1,
    );
    await repo.registrar(
      uuid: 'uuid-rep-1',
      cabecera: {
        'tipo': 'REPOSICION',
        'numero_reposicion': 'REP-LOCAL-00000001',
        'estado': 'COMPLETADA',
        'es_offline': 1,
      },
      items: const [],
      sucursalId: 1,
    );
    expect(await repo.listar(tipo: 'DEVOLUCION'), hasLength(1));
    expect(await repo.listar(tipo: 'REPOSICION'), hasLength(1));
    expect(await repo.listar(), hasLength(2));
    // El prefijo REP- distingue la reposición (CU18).
    expect(
      (await repo.listar(tipo: 'REPOSICION')).single.numeroReposicion,
      startsWith('REP-'),
    );
    await servicios.db.cerrar();
  });
}
