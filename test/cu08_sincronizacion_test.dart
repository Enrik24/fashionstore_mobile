import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/connectivity_service.dart';
import 'package:fashionstore_mobile/core/services/local_audit_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/sync_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_offline_client.dart';

void main() {
  sqfliteFfiInit();
  test('CU08 envía la cola FIFO y traduce payload_json a payload', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    client.responder = (_, __) => <String, dynamic>{
      'resultados': <Map<String, dynamic>>[
        <String, dynamic>{'uuid_operacion': 'op-1', 'estado': 'CONFIRMADA'},
      ],
    };
    final queue = OfflineQueueService(
      database: db,
      tenantId: 2,
      dispositivoId: 'device-sync',
    );
    await queue.encolar(
      uuidOperacion: 'op-1',
      tipoOperacion: 'VENTA_CONTADO',
      payload: <String, Object?>{'total': 10},
    );
    final engine = SyncEngineService(
      queue: queue,
      client: client,
      connectivity: ConnectivityService(client: client),
      audit: LocalAuditService(db),
      tenantId: 2,
      dispositivoId: 'device-sync',
    );

    final resumen = await engine.sincronizarAhora();
    final enviados = client.requests.single['operaciones'] as List;

    expect(resumen.confirmadas, 1);
    expect(enviados.single['payload'], <String, Object?>{'total': 10});
    expect(client.headers.single['Idempotency-Key'], 'op-1');
    await db.cerrar();
  });
}
