// [EXAMEN-2] Ola 1 / B0.2 + B0.4: stock local referencial real y
// persistencia de `usuario_id` en las operaciones offline.
//
// El bug de B0.2 hacía que `buscarVarianteLocal` devolviera variantes sin
// `stock_total`, por lo que `VarianteProducto.fromJson` caía a 0 y el POS
// anunciaba "Stock local referencial: 0" en el 100% de los casos.
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fase3_helpers.dart';

void main() {
  test('B0.2: el stock local acompaña a cada variante (stockTotal real)', () async {
    final servicios = await crearServicios();
    final resultados = await servicios.pos.buscarVarianteLocal('B-M');
    expect(resultados, isNotEmpty);

    final producto = resultados.firstWhere((p) => p.nombre == 'Blusa');
    final variante = producto.variantes.firstWhere((v) => v.id == 101);
    // La tabla `stock` sembrada tiene 10 unidades para la variante 101.
    expect(variante.stockTotal, 10);
    expect(variante.stockPorSucursal[1], 10);

    await servicios.db.cerrar();
  });

  test('B0.2: el stock disponible descuenta lo reservado', () async {
    final servicios = await crearServicios();
    await servicios.db.database!.update(
      'stock',
      <String, Object?>{'cantidad_reservada': 4},
      where: 'variante_id = ? AND tenant_id = ?',
      whereArgs: <Object?>[101, tenantFase3],
    );
    final resultados = await servicios.pos.buscarVarianteLocal('B-M');
    final producto = resultados.firstWhere((p) => p.nombre == 'Blusa');
    final variante = producto.variantes.firstWhere((v) => v.id == 101);
    expect(variante.stockTotal, 6);
    await servicios.db.cerrar();
  });

  test('B0.2.e: una variante ausente del catálogo local se detecta', () async {
    final servicios = await crearServicios();
    expect(await servicios.pos.varianteEnCatalogoLocal(101), isTrue);
    expect(await servicios.pos.varianteEnCatalogoLocal(9999), isFalse);
    await servicios.db.cerrar();
  });

  test('B0.4: la operación encolada registra el usuario autenticado', () async {
    final db = await abrirBaseFase3();
    await sembrarCatalogo(db);
    // [EXAMEN-2] B0.4: el id del usuario viaja en el servicio de cola.
    final queue = OfflineQueueService(
      database: db,
      tenantId: tenantFase3,
      dispositivoId: 'device-usuario',
      usuarioId: 77,
    );
    await queue.encolar(
      uuidOperacion: 'uuid-con-usuario',
      tipoOperacion: 'RESERVA',
      payload: const <String, Object?>{'x': 1},
    );
    final fila = await db.database!.query(
      'operaciones',
      where: 'uuid_operacion = ?',
      whereArgs: <Object?>['uuid-con-usuario'],
    );
    expect(fila.single['usuario_id'], 77);
    expect(fila.single['tenant_id'], tenantFase3);
    await db.cerrar();
  });

  test('B0.4: la venta offline propaga el usuario a la cabecera', () async {
    final db = await abrirBaseFase3();
    await sembrarCatalogo(db);
    final queue = OfflineQueueService(
      database: db,
      tenantId: tenantFase3,
      dispositivoId: 'device-usuario',
      usuarioId: 42,
    );
    final servicios = ServiciosFase3(db: db, queue: queue);

    servicios.pos.iniciarVenta();
    servicios.pos.agregarProducto(
      varianteProductoId: 101,
      cantidad: 1,
      precioUnitario: 100,
      nombre: 'Blusa',
      stockConocido: 10,
    );
    await servicios.pos.confirmarVentaOffline(
      sucursalId: 1,
      cajeroId: 42,
      montoRecibido: 100,
    );

    final venta = await db.database!.query(
      'ventas_locales',
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantFase3],
    );
    expect(venta, hasLength(1));
    expect(venta.single['usuario_id'], 42);

    final operacion = await db.database!.query(
      'operaciones',
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantFase3],
    );
    expect(operacion, hasLength(1));
    expect(operacion.single['usuario_id'], 42);
    expect(operacion.single['tipo_operacion'], 'VENTA_CONTADO');

    await db.cerrar();
  });

  test('B0.5: la venta offline guarda un comprobante provisional buscable', () async {
    final db = await abrirBaseFase3();
    await sembrarCatalogo(db);
    final queue = OfflineQueueService(
      database: db,
      tenantId: tenantFase3,
      dispositivoId: 'device-comprobante',
      usuarioId: 42,
    );
    final servicios = ServiciosFase3(db: db, queue: queue);

    servicios.pos.iniciarVenta();
    servicios.pos.agregarProducto(
      varianteProductoId: 101,
      cantidad: 1,
      precioUnitario: 100,
      nombre: 'Blusa',
      stockConocido: 10,
    );
    final venta = await servicios.pos.confirmarVentaOffline(
      sucursalId: 1,
      cajeroId: 42,
      montoRecibido: 100,
    );

    final fila = await db.database!.query(
      'ventas_locales',
      where: 'uuid_offline = ?',
      whereArgs: <Object?>[venta.uuidOffline],
    );
    final comprobante = fila.single['numero_comprobante']?.toString() ?? '';
    expect(comprobante, isNotEmpty);
    expect(comprobante, startsWith('VTA-OFF-'));

    // B0.5: la búsqueda por comprobante (sin red) encuentra la venta.
    final encontrada = await servicios.pos.buscarVentaOriginal(
      numeroComprobante: comprobante,
      enLinea: false,
    );
    expect(encontrada, isNotNull);
    expect(encontrada!['origen'], 'local');
    expect((encontrada['items'] as List), hasLength(1));

    await db.cerrar();
  });

  test('B1.3.g: el payload envía precio_unitario_local (contrato RN-007)', () async {
    final db = await abrirBaseFase3();
    await sembrarCatalogo(db);
    final queue = OfflineQueueService(
      database: db,
      tenantId: tenantFase3,
      dispositivoId: 'device-precio',
      usuarioId: 42,
    );
    final servicios = ServiciosFase3(db: db, queue: queue);

    servicios.pos.iniciarVenta();
    servicios.pos.agregarProducto(
      varianteProductoId: 101,
      cantidad: 2,
      precioUnitario: 100,
      nombre: 'Blusa',
      stockConocido: 10,
    );
    await servicios.pos.confirmarVentaOffline(
      sucursalId: 1,
      cajeroId: 42,
      montoRecibido: 200,
    );

    final operacion = await db.database!.query(
      'operaciones',
      where: 'tenant_id = ?',
      whereArgs: <Object?>[tenantFase3],
    );
    final payload = operacion.single['payload_json'] as String;
    expect(payload, contains('precio_unitario_local'));
    expect(payload, contains('"precio_unitario_local":100'));

    await db.cerrar();
  });
}
