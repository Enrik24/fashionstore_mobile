import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/pending_payment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_offline_client.dart';

void main() {
  sqfliteFfiInit();

  test('el pago diferido registra, cuenta y confirma el pago', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    final service = PendingPaymentService(
      database: db,
      tenantId: 13,
      client: client,
    );
    await service.registrarPago(
      uuidPago: 'payment-unit',
      uuidOrden: 'order-unit',
      monto: 50,
    );

    expect(await service.contadorPendientes(), 1);
    await service.confirmarPago('payment-unit');
    expect(client.headers.last['Idempotency-Key'], 'payment-unit');
    expect(await service.contadorPendientes(), 0);
    await db.cerrar();
  });
}
