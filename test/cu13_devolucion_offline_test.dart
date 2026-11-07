// [EXAMEN-2] CU13: devolución offline (plazo, reembolso/saldo a favor,
// encolado DEVOLUCION y ERROR_VENTA_INVALIDA).
import 'package:fashionstore_mobile/core/services/return_service.dart';
import 'package:fashionstore_mobile/core/utils/sync_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fase3_helpers.dart';

void main() {
  test('CU13 plazo válido permite crear la devolución offline', () async {
    final servicios = await crearServicios();
    final solicitud = await servicios.returns.crearDevolucionOffline(
      numeroComprobanteOrigen: 'FAC-0001',
      sucursalId: 1,
      items: const [
        LineaDevolucion(
          varianteProductoId: 101,
          productoId: 10,
          cantidad: 1,
          precioUnitario: 100,
        ),
      ],
      fechaCambioLimite: DateTime.now().add(const Duration(days: 5)),
    );

    expect(solicitud.tipo, 'DEVOLUCION');
    expect(solicitud.esOffline, isTrue);
    expect(solicitud.uuidOffline, isNotNull);
    expect(solicitud.estado, 'PENDIENTE_SINCRONIZACION');
    expect(solicitud.montoReembolso, 100);
    expect(solicitud.tipoDiferencia, 'SIN_DIFERENCIA');
    await servicios.db.cerrar();
  });

  test('CU13 plazo vencido bloquea la devolución (RN-012)', () async {
    final servicios = await crearServicios();
    expect(
      () => servicios.returns.crearDevolucionOffline(
        numeroComprobanteOrigen: 'FAC-0001',
        sucursalId: 1,
        items: const [
          LineaDevolucion(
            varianteProductoId: 101,
            precioUnitario: 100,
          ),
        ],
        fechaCambioLimite: DateTime.now().subtract(const Duration(days: 1)),
      ),
      throwsA(isA<FormatException>()),
    );
    // PosService valida lo mismo; el provider no debería habilitar el botón.
    expect(
      servicios.pos.validarPlazoCambio(
        fechaLimite: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      isFalse,
    );
    await servicios.db.cerrar();
  });

  test('CU13 reembolso vs saldo a favor sin prenda nueva ni salida', () async {
    final servicios = await crearServicios();

    final reembolso = await servicios.returns.crearDevolucionOffline(
      numeroComprobanteOrigen: 'FAC-0002',
      sucursalId: 1,
      items: const [
        LineaDevolucion(varianteProductoId: 101, precioUnitario: 100),
      ],
    );
    expect(reembolso.montoReembolso, 100);
    expect(reembolso.tipoDiferencia, 'SIN_DIFERENCIA');

    final saldo = await servicios.returns.crearDevolucionOffline(
      numeroComprobanteOrigen: 'FAC-0003',
      sucursalId: 1,
      saldoFavor: true,
      items: const [
        LineaDevolucion(varianteProductoId: 101, precioUnitario: 100),
      ],
    );
    expect(saldo.montoReembolso, 0);
    expect(saldo.tipoDiferencia, 'SALDO_FAVOR');
    expect(saldo.saldoFavor, 100);

    // Solo entrada de la prenda devuelta; la variante nueva no cambia.
    expect(await stockDe(servicios.db, 101), 12);
    expect(await stockDe(servicios.db, 102), 10);
    expect(
      reembolso.items.single.varianteCambioId,
      isNull,
      reason: 'Devolución pura no tiene prenda nueva',
    );
    await servicios.db.cerrar();
  });

  test('CU13 encola DEVOLUCION con uuid y estado pendiente', () async {
    final servicios = await crearServicios();
    final solicitud = await servicios.returns.crearDevolucionOffline(
      numeroComprobanteOrigen: 'FAC-0004',
      sucursalId: 1,
      items: const [
        LineaDevolucion(varianteProductoId: 101, precioUnitario: 100),
      ],
    );
    final pendientes = await servicios.queue.pendientes();
    expect(pendientes.any((op) => op.tipoOperacion == 'DEVOLUCION'), isTrue);
    expect(
      pendientes
          .where((op) => op.tipoOperacion == 'DEVOLUCION')
          .single
          .uuidOperacion,
      solicitud.uuidOffline,
    );
    final local = await servicios.returns.getSolicitudDesdeLocal(
      solicitud.uuidOffline!,
    );
    expect(local, isNotNull);
    expect(local!.items, hasLength(1));
    expect(local.items.single.varianteProductoId, 101);
    await servicios.db.cerrar();
  });

  test(
    'CU13 ERROR_VENTA_INVALIDA queda registrado y se traduce',
    () async {
      final servicios = await crearServicios();
      final solicitud = await servicios.returns.crearDevolucionOffline(
        numeroComprobanteOrigen: 'FAC-0005',
        sucursalId: 1,
        items: const [
          LineaDevolucion(varianteProductoId: 101, precioUnitario: 100),
        ],
      );
      await servicios.returns.aplicarResultadoSync(
        uuidOffline: solicitud.uuidOffline!,
        estado: 'ERROR_VENTA_INVALIDA',
      );
      final trasSync = await servicios.returns.getSolicitudDesdeLocal(
        solicitud.uuidOffline!,
      );
      expect(trasSync?.estado, 'ERROR_VENTA_INVALIDA');
      expect(
        SyncMessages.traducirEstado('ERROR_VENTA_INVALIDA'),
        'Venta original inválida',
      );
      expect(
        SyncMessages.traducirMotivo('ERROR_VENTA_INVALIDA'),
        contains('ya no es válida'),
      );
      await servicios.db.cerrar();
    },
  );

  test('CU13 PENDIENTE_REEMBOLSO se expone en el detalle local', () async {
    final servicios = await crearServicios();
    final solicitud = await servicios.returns.crearDevolucionOffline(
      numeroComprobanteOrigen: 'FAC-0006',
      sucursalId: 1,
      items: const [
        LineaDevolucion(varianteProductoId: 101, precioUnitario: 100),
      ],
    );
    await servicios.returns.aplicarResultadoSync(
      uuidOffline: solicitud.uuidOffline!,
      estado: 'PENDIENTE_REEMBOLSO',
    );
    final trasSync = await servicios.returns.getSolicitudDesdeLocal(
      solicitud.uuidOffline!,
    );
    expect(trasSync?.estado, 'PENDIENTE_REEMBOLSO');
    expect(
      SyncMessages.traducirEstado('PENDIENTE_REEMBOLSO'),
      'Pendiente de reembolso',
    );
    await servicios.db.cerrar();
  });
}
