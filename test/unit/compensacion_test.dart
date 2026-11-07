// [EXAMEN-2] CU19: modelo de compensación (parseo, caché y etiquetas).
import 'package:fashionstore_mobile/core/database/repositories/local_compensacion_repository.dart';
import 'package:fashionstore_mobile/core/models/compensation_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fase3_helpers.dart';

void main() {
  test('fromJson lee el serializer del backend', () {
    final modelo = CompensacionModel.fromJson({
      'id': 5,
      'tenant_id': 4,
      'operacion_offline_id': 500,
      'orden_id': 41,
      'cliente_id': 7,
      'tipo': 'REEMBOLSO_EFECTIVO',
      'monto': 100,
      'moneda': 'BOB',
      'estado': 'PENDIENTE',
      'motivo': 'Stock insuficiente',
      'referencia_externa': null,
      'notificado_cliente': true,
      'error_detalle': null,
      'fecha_creacion': '2026-11-06T10:00:00Z',
      'fecha_resolucion': null,
      'resuelto_por': null,
    });
    expect(modelo.id, 5);
    expect(modelo.operacionOfflineId, 500);
    expect(modelo.monto, 100);
    expect(modelo.esEfectivo, isTrue);
    expect(modelo.estaPendiente, isTrue);
    expect(modelo.notificadoCliente, isTrue);
    expect(modelo.fechaCreacion, isNotNull);
    expect(CompensacionTipos.labelTipo('REEMBOLSO_TARJETA'), contains('tarjeta'));
    expect(CompensacionTipos.labelEstado('COMPLETADA'), 'Completada');
  });

  test('toMap/fromMap round-trip para la caché local', () {
    final original = CompensacionModel(
      id: 9,
      operacionOfflineId: 501,
      uuidOperacion: 'uuid-op-501',
      monto: 250,
      tipo: 'NOTA_CREDITO',
      estado: 'EN_PROCESO',
      motivo: 'Precio cambió',
      fechaCreacion: DateTime.utc(2026, 11, 6, 10),
    );
    final fila = original.toMap();
    final recuperada = CompensacionModel.fromMap({
      ...fila,
      'tenant_id': tenantFase3,
    });
    expect(recuperada.id, 9);
    expect(recuperada.monto, 250);
    expect(recuperada.tipo, 'NOTA_CREDITO');
    expect(recuperada.estado, 'EN_PROCESO');
  });

  test('copyWith conserva el resto al confirmar', () {
    const original = CompensacionModel(
      id: 10,
      monto: 100,
      tipo: 'REEMBOLSO_EFECTIVO',
      estado: 'PENDIENTE',
    );
    final confirmada = original.copyWith(
      estado: 'COMPLETADA',
      fechaCompletado: DateTime.utc(2026, 11, 6, 12),
      resueltoPor: '9',
    );
    expect(confirmada.estado, 'COMPLETADA');
    expect(confirmada.monto, 100);
    expect(confirmada.estaCompletada, isTrue);
  });

  test('repositorio deduplica por operacion_offline_id en la caché', () async {
    final servicios = await crearServicios();
    final repo = LocalCompensacionRepository(
      servicios.db.database!,
      tenantId: tenantFase3,
    );
    const base = CompensacionModel(
      id: 100,
      operacionOfflineId: 777,
      uuidOperacion: 'uuid-op-777',
      monto: 100,
      tipo: 'REEMBOLSO_EFECTIVO',
      estado: 'PENDIENTE',
    );
    await repo.guardarCompensacion(base);
    // Otro id con la misma operación: actualiza en vez de duplicar.
    await repo.guardarCompensacion(
      CompensacionModel(
        id: base.id,
        operacionOfflineId: base.operacionOfflineId,
        uuidOperacion: base.uuidOperacion,
        monto: base.monto,
        tipo: base.tipo,
        estado: base.estado,
        motivo: base.motivo,
      ),
    );
    await repo.guardarCompensacion(
      const CompensacionModel(
        id: 999,
        operacionOfflineId: 777,
        uuidOperacion: 'uuid-op-777',
        monto: 100,
        tipo: 'REEMBOLSO_EFECTIVO',
        estado: 'COMPLETADA',
      ),
    );    final lista = await repo.listar();
    expect(lista, hasLength(1));
    expect(lista.single.estado, 'COMPLETADA');
    expect(await repo.pendientesCount(), 0);
    await servicios.db.cerrar();
  });
}
