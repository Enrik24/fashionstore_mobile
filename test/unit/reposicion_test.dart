// [EXAMEN-2] CU18: reposición a nivel repositorio (RN-025 y números REP-).
import 'package:fashionstore_mobile/core/database/repositories/local_return_repository.dart';
import 'package:fashionstore_mobile/core/models/return_request_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fase3_helpers.dart';

void main() {
  test('RN-025: entrada y salida de inventario en la misma transacción', () async {
    final servicios = await crearServicios();
    final repo = LocalReturnRepository(
      servicios.db.database!,
      tenantId: tenantFase3,
    );
    await repo.registrar(
      uuid: 'uuid-rep-rn025',
      cabecera: {
        'tipo': 'REPOSICION',
        'numero_reposicion': 'REP-LOCAL-RN025001',
        'estado': 'PENDIENTE_SINCRONIZACION',
        'estado_sincronizacion': 'PENDIENTE_SINCRONIZACION',
        'es_offline': 1,
        'diferencia_precio': 20,
        'tipo_diferencia': 'COBRO',
        'monto_pagado_diferencia': 20,
      },
      items: [
        {
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
      movimientosStock: [
        (varianteId: 101, delta: 2, deltaReserva: 0),
        (varianteId: 102, delta: -1, deltaReserva: -1),
      ],
      sucursalId: 1,
    );

    final detalle = await repo.detalle('uuid-rep-rn025');
    expect(detalle, isNotNull);
    expect(detalle!.items.single.varianteCambioId, 102);
    expect(detalle.items.single.diferencia, 20);
    expect(detalle.tipoDiferencia, 'COBRO');
    expect(await stockDe(servicios.db, 101), 12);
    expect(await stockDe(servicios.db, 102), 9);
    await servicios.db.cerrar();
  });

  test('numero_reposicion usa prefijo REP- y es único por registro', () async {
    final servicios = await crearServicios();
    final repo = LocalReturnRepository(
      servicios.db.database!,
      tenantId: tenantFase3,
    );
    for (var i = 0; i < 2; i++) {
      await repo.registrar(
        uuid: 'uuid-rep-u$i',
        cabecera: {
          'tipo': 'REPOSICION',
          'numero_reposicion': 'REP-TEST-$i',
          'estado': 'COMPLETADA',
          'es_offline': 1,
        },
        items: const [],
        sucursalId: 1,
      );
    }
    final reposiciones = await repo.listar(tipo: 'REPOSICION');
    expect(reposiciones, hasLength(2));
    expect(reposiciones.map((e) => e.numeroReposicion).toSet(), hasLength(2));
    await servicios.db.cerrar();
  });

  test('payloadCola identifica el tipo y el uuid offline', () async {
    final solicitud = ReturnRequestModel(
      id: 0,
      numeroSolicitud: 'REP-LOCAL-x',
      ordenId: 41,
      tipo: 'REPOSICION',
      motivo: 'TALLA_INCORRECTA',
      estado: 'PENDIENTE_SINCRONIZACION',
      uuidOffline: 'uuid-rep-1',
      items: [
        ReturnItemModel(
          id: 1,
          solicitudId: 0,
          detalleOrdenId: 55,
          varianteProductoId: 101,
          cantidad: 1,
          varianteCambioId: 102,
          precioUnitario: 100,
        ),
      ],
    );
    final payload = LocalReturnRepository.payloadCola(solicitud);
    expect(payload['tipo'], 'REPOSICION');
    expect(payload['uuid_offline'], 'uuid-rep-1');
  });
}
