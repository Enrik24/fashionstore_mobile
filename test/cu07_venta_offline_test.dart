import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/pos_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('CU07 calcula total y cambio y encola la venta offline', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final queue = OfflineQueueService(
      database: db,
      tenantId: 4,
      dispositivoId: 'device-pos',
    );
    final pos = PosService(database: db, tenantId: 4, queue: queue);
    pos.iniciarVenta();
    pos.agregarProducto(
      varianteProductoId: 2,
      cantidad: 2,
      precioUnitario: 50,
      nombre: 'Pantalón',
    );

    final venta = await pos.confirmarVentaOffline(
      sucursalId: 1,
      cajeroId: 8,
      montoRecibido: 120,
    );

    expect(pos.calcularTotalLocal(), 100);
    expect(venta.cambio, 20);
    expect((await queue.pendientes()).single.tipoOperacion, 'VENTA_CONTADO');
    await db.cerrar();
  });
}
