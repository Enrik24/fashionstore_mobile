import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/conflict_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('CU09 registra y resuelve un conflicto con motivo traducido', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final queue = OfflineQueueService(
      database: db,
      tenantId: 3,
      dispositivoId: 'device-conflict',
    );
    await queue.encolar(
      uuidOperacion: 'conflict-1',
      tipoOperacion: 'VENTA_CONTADO',
      payload: const {},
    );
    await queue.aplicarResultado(
      uuidOperacion: 'conflict-1',
      estado: 'CONFLICTO',
      motivo: 'STOCK_INSUFICIENTE',
    );
    final service = ConflictService(database: db, tenantId: 3);
    final conflictos = await service.pendientes();

    expect(conflictos, hasLength(1));
    expect(service.traducirMotivo('STOCK_INSUFICIENTE'), contains('Stock'));
    await service.resolver(conflictos.single.id, accion: 'ACEPTAR_CENTRAL');
    expect(await service.pendientes(), isEmpty);
    await db.cerrar();
  });
}
