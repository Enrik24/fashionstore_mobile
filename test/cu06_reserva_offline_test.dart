import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('CU06 registra una reserva local con UUID y estado pendiente', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final queue = OfflineQueueService(
      database: db,
      tenantId: 9,
      dispositivoId: 'device-test',
    );

    await queue.encolar(
      uuidOperacion: 'reserva-uuid-1',
      tipoOperacion: 'RESERVA',
      payload: <String, Object?>{'variante_producto_id': 3},
    );
    final operaciones = await queue.pendientes();

    expect(operaciones.single.uuidOperacion, 'reserva-uuid-1');
    expect(operaciones.single.estadoSincronizacion, 'PENDIENTE');
    expect(operaciones.single.payload['variante_producto_id'], 3);
    await db.cerrar();
  });
}
