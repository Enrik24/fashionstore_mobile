import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/connectivity_service.dart';
import 'package:fashionstore_mobile/core/services/local_audit_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/sync_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_offline_client.dart';

void main() {
  sqfliteFfiInit();

  test('el motor procesa resultados y conserva la clave idempotente', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    client.responder = (_, __) => <String, dynamic>{
      'resultados': <Map<String, dynamic>>[
        <String, dynamic>{'uuid_operacion': 'op-sync', 'estado': 'CONFIRMADA'},
      ],
    };
    final queue = OfflineQueueService(
      database: db,
      tenantId: 11,
      dispositivoId: 'device-engine',
    );
    await queue.encolar(
      uuidOperacion: 'op-sync',
      tipoOperacion: 'VENTA',
      payload: const <String, Object?>{'total': 25},
    );
    final engine = SyncEngineService(
      queue: queue,
      client: client,
      connectivity: ConnectivityService(client: client),
      audit: LocalAuditService(db),
      tenantId: 11,
      dispositivoId: 'device-engine',
    );

    final resumen = await engine.sincronizarAhora();

    expect(resumen.confirmadas, 1);
    expect(client.headers.single['Idempotency-Key'], 'op-sync');
    await db.cerrar();
  });
}
