import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/conflict_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('el conflicto se persiste, se cuenta y se resuelve', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final queue = OfflineQueueService(
      database: db,
      tenantId: 12,
      dispositivoId: 'device-conflict-unit',
    );
    await queue.encolar(
      uuidOperacion: 'op-conflict',
      tipoOperacion: 'VENTA',
      payload: const <String, Object?>{},
    );
    await queue.aplicarResultado(
      uuidOperacion: 'op-conflict',
      estado: 'CONFLICTO',
      motivo: 'STOCK_INSUFICIENTE',
    );
    final service = ConflictService(database: db, tenantId: 12);

    expect(await service.contadorPendientes(), 1);
    final conflicto = (await service.pendientes()).single;
    await service.resolver(conflicto.id, accion: 'ACEPTAR_CENTRAL');
    expect(await service.contadorPendientes(), 0);
    await db.cerrar();
  });
}
