import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/pending_payment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_offline_client.dart';

void main() {
  sqfliteFfiInit();
  test('CU16 confirma el pago con Idempotency-Key igual a uuid_pago', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    final service = PendingPaymentService(
      database: db,
      tenantId: 7,
      client: client,
    );
    await service.registrarPago(
      uuidPago: 'pago-uuid-1',
      uuidOrden: 'orden-1',
      monto: 100,
    );

    await service.confirmarPago('pago-uuid-1');

    expect(client.headers.last['Idempotency-Key'], 'pago-uuid-1');
    expect((await service.estadoPago('pago-uuid-1'))?.estado, 'CONFIRMADO');
    await db.cerrar();
  });

  // [EXAMEN-2] C2.5 P1: doble confirmar mismo uuid no duplica (RN-015).
  test('CU16 doble confirmar mismo uuid no duplica el pago', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    final service = PendingPaymentService(
      database: db,
      tenantId: 7,
      client: client,
    );
    await service.registrarPago(
      uuidPago: 'pago-uuid-2',
      uuidOrden: 'orden-2',
      monto: 100,
      intentarRemoto: false,
    );

    await service.confirmarPago('pago-uuid-2');
    await service.confirmarPago('pago-uuid-2');

    // Mismo Idempotency-Key en ambos POST, una sola fila y estado terminal.
    final claves = client.headers
        .map((h) => h['Idempotency-Key'])
        .where((k) => k == 'pago-uuid-2')
        .toList();
    expect(claves.length, 2);
    expect((await service.estadoPago('pago-uuid-2'))?.estado, 'CONFIRMADO');
    expect(await service.pendientes(), isEmpty);
    expect(await service.contadorPendientes(), 0);
    final filas = await db.database!.query(
      'pagos',
      where: 'uuid_pago = ? AND tenant_id = ?',
      whereArgs: <Object?>['pago-uuid-2', 7],
    );
    expect(filas, hasLength(1));
    expect(filas.single['idempotency_key'], 'pago-uuid-2');
    await db.cerrar();
  });

  // [EXAMEN-2] C2.5 P1: expiración cancela el pago (procesarExpirados).
  test('CU16 expiración marca EXPIRADO y libera el pendiente', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    final service = PendingPaymentService(
      database: db,
      tenantId: 7,
      client: client,
    );
    final vencido = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await service.registrarPago(
      uuidPago: 'pago-expirado',
      uuidOrden: 'orden-expirada',
      monto: 80,
      expiraEn: vencido,
      intentarRemoto: false,
    );
    await service.registrarPago(
      uuidPago: 'pago-vigente',
      uuidOrden: 'orden-vigente',
      monto: 80,
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 2)),
      intentarRemoto: false,
    );

    final procesados = await service.procesarExpirados();

    expect(procesados, 1);
    expect((await service.estadoPago('pago-expirado'))?.estado, 'EXPIRADO');
    // El pago vigente no se toca.
    expect((await service.estadoPago('pago-vigente'))?.estado, 'PENDIENTE');
    expect(
      (await service.pendientes()).map((p) => p.uuidPago),
      contains('pago-vigente'),
    );
    expect(
      (await service.pendientes()).map((p) => p.uuidPago),
      isNot(contains('pago-expirado')),
    );
    await db.cerrar();
  });
}
