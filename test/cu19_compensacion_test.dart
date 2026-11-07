// [EXAMEN-2] CU19: compensación de venta offline rechazada (modo cajero).
// Listar/detalle, confirmar efectivo solo cajero (PENDIENTE→COMPLETADA sin
// repetir), nunca reembolsos por pasarela y resync sin duplicados.
import 'package:fashionstore_mobile/core/models/compensation_model.dart';
import 'package:fashionstore_mobile/core/providers/compensation_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fase3_helpers.dart';

CompensacionModel _comp({
  int id = 1,
  String tipo = 'REEMBOLSO_EFECTIVO',
  String estado = 'PENDIENTE',
  int operacionId = 500,
  String? uuid = 'uuid-op-500',
}) => CompensacionModel(
  id: id,
  operacionOfflineId: operacionId,
  uuidOperacion: uuid,
  monto: 100,
  moneda: 'BOB',
  tipo: tipo,
  estado: estado,
  motivo: 'Stock insuficiente',
);

void main() {
  test('CU19 listar y detalle desde la caché local', () async {
    final servicios = await crearServicios();
    await servicios.compensation.sincronizarCacheRemotas([
      _comp(id: 1, operacionId: 500),
      _comp(id: 2, estado: 'COMPLETADA', operacionId: 501),
    ]);
    final lista = await servicios.compensation.listar();
    expect(lista, hasLength(2));
    final una = await servicios.compensation.detalle(1);
    expect(una, isNotNull);
    expect(una!.monto, 100);
    expect(una.tipo, 'REEMBOLSO_EFECTIVO');
    expect(una.estado, 'PENDIENTE');
    expect(una.uuidOperacion, 'uuid-op-500');
    await servicios.db.cerrar();
  });

  test(
    'CU19 confirmar efectivo: cajero cambia PENDIENTE→COMPLETADA sin repetir',
    () async {
      final servicios = await crearServicios();
      await servicios.compensation.sincronizarCacheRemotas([_comp(id: 7)]);

      final confirmada = await servicios.compensation.confirmarEfectivo(
        7,
        esCajero: true,
        cajeroId: 9,
      );
      expect(confirmada.estado, 'COMPLETADA');
      expect(confirmada.fechaCompletado, isNotNull);

      // Sin repetir: la segunda confirmación lanza.
      expect(
        () => servicios.compensation.confirmarEfectivo(
          7,
          esCajero: true,
          cajeroId: 9,
        ),
        throwsA(isA<StateError>()),
      );
      // Y sin rol cajero tampoco.
      expect(
        () => servicios.compensation.confirmarEfectivo(
          7,
          esCajero: false,
          cajeroId: 9,
        ),
        throwsA(isA<StateError>()),
      );
      await servicios.db.cerrar();
    },
  );

  test('CU19 no ejecuta reembolso por pasarela', () async {
    final servicios = await crearServicios();
    await servicios.compensation.sincronizarCacheRemotas([
      _comp(id: 8, tipo: 'REEMBOLSO_TARJETA'),
      _comp(id: 9, tipo: 'NOTA_CREDITO', estado: 'PENDIENTE', operacionId: 501),
    ]);
    // Tarjeta y nota de crédito: la app solo informa, no confirma.
    expect(
      () => servicios.compensation.confirmarEfectivo(
        8,
        esCajero: true,
        cajeroId: 9,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => servicios.compensation.confirmarEfectivo(
        9,
        esCajero: true,
        cajeroId: 9,
      ),
      throwsA(isA<StateError>()),
    );
    final tarjeta = await servicios.compensation.detalle(8);
    expect(tarjeta?.estado, 'PENDIENTE');
    await servicios.db.cerrar();
  });

  test('CU19 un resync no duplica la compensación', () async {
    final servicios = await crearServicios();
    await servicios.compensation.sincronizarCacheRemotas([_comp(id: 11)]);
    // Mismo payload (mismo id y misma operacion_offline_id) otra vez.
    await servicios.compensation.sincronizarCacheRemotas([_comp(id: 11)]);
    // Mismo operacion_offline_id con otro id (unique de backend): no duplica.
    await servicios.compensation.sincronizarCacheRemotas([
      _comp(id: 999, operacionId: 500),
    ]);
    final lista = await servicios.compensation.listar();
    expect(lista, hasLength(1));
    await servicios.db.cerrar();
  });

  test('CU19 pendientesCount y resumen solo cuentan sin confirmar', () async {
    final servicios = await crearServicios();
    await servicios.compensation.sincronizarCacheRemotas([
      _comp(id: 21),
      _comp(id: 22, estado: 'EN_PROCESO', operacionId: 502),
      _comp(id: 23, estado: 'COMPLETADA', operacionId: 503),
      _comp(id: 24, estado: 'FALLIDA', operacionId: 504),
    ]);
    expect(await servicios.compensation.pendientesCount(), 2);
    final resumen = await servicios.compensation.resumen();
    expect(resumen['por_estado'], containsPair('PENDIENTE', 1));
    expect(resumen['por_estado'], containsPair('COMPLETADA', 1));
    expect(resumen['por_tipo'], containsPair('REEMBOLSO_EFECTIVO', 4));
    await servicios.db.cerrar();
  });

  test(
    'CU19 provider: pendientesCount solo en modo cajero',
    () async {
      final servicios = await crearServicios();
      await servicios.compensation.sincronizarCacheRemotas([_comp(id: 31)]);

      final cliente = CompensationProvider(
        service: servicios.compensation,
        esCajero: false,
      );
      await cliente.load();
      expect(cliente.compensaciones, isEmpty);
      expect(cliente.pendientesCount, 0);

      final cajero = CompensationProvider(
        service: servicios.compensation,
        esCajero: true,
        cajeroId: 9,
      );
      await cajero.load();
      expect(cajero.compensaciones, hasLength(1));
      expect(cajero.pendientesCount, 1);
      final ok = await cajero.confirmarEfectivo(31);
      expect(ok, isTrue);
      expect(cajero.detalleSeleccionado?.estado, 'COMPLETADA');
      await servicios.db.cerrar();
    },
  );
}
