import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('la cola conserva el orden FIFO y aplica el estado DUPLICADA', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final queue = OfflineQueueService(
      database: db,
      tenantId: 10,
      dispositivoId: 'device-queue',
    );

    await queue.encolar(
      uuidOperacion: 'op-1',
      tipoOperacion: 'RESERVA',
      payload: const <String, Object?>{'n': 1},
    );
    await queue.encolar(
      uuidOperacion: 'op-2',
      tipoOperacion: 'VENTA',
      payload: const <String, Object?>{'n': 2},
    );
    final pendientes = await queue.pendientes();

    expect(pendientes.map((op) => op.uuidOperacion), <String>['op-1', 'op-2']);
    await queue.aplicarResultado(uuidOperacion: 'op-1', estado: 'DUPLICADA');
    expect((await queue.obtener('op-1'))?.estadoSincronizacion, 'DUPLICADA');
    await db.cerrar();
  });
}
