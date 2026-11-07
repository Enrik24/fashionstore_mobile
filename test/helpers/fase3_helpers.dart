// [EXAMEN-2] Utilidades compartidas de Fase 3: siembra de catálogo/stock y
// construcción de servicios con FFI para tests CU13/CU18/CU19.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/local_audit_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/return_service.dart';
import 'package:fashionstore_mobile/core/services/compensation_service.dart';
import 'package:fashionstore_mobile/core/services/pos_service.dart';

const int tenantFase3 = 4;

Future<LocalDatabaseService> abrirBaseFase3() async {
  sqfliteFfiInit();
  // Un archivo único por test: inMemoryDatabasePath se comparte en la suite
  // y los datos entre tests generarían UNIQUE constraint failed.
  final dir = Directory.systemTemp.createTempSync('fase3-db');
  final ruta = '${dir.path}${Platform.pathSeparator}fase3-test.db';
  final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
  await db.abrir(ruta: ruta);
  return db;
}

Future<void> sembrarCatalogo(
  LocalDatabaseService servicio, {
  int tenantId = tenantFase3,
}) async {
  final db = servicio.database!;
  final ahora = DateTime.now().toUtc().toIso8601String();
  await db.insert('productos', <String, Object?>{
    'id': 10,
    'tenant_id': tenantId,
    'nombre': 'Blusa',
    'precio': 100,
    'fecha_actualizacion': ahora,
  });
  await db.insert('productos', <String, Object?>{
    'id': 20,
    'tenant_id': tenantId,
    'nombre': 'Pantalón',
    'precio': 150,
    'fecha_actualizacion': ahora,
  });
  await db.insert('variantes', <String, Object?>{
    'id': 101,
    'tenant_id': tenantId,
    'producto_id': 10,
    'sku_variante': 'B-M',
    'precio': 100,
    'fecha_actualizacion': ahora,
  });
  await db.insert('variantes', <String, Object?>{
    'id': 102,
    'tenant_id': tenantId,
    'producto_id': 10,
    'sku_variante': 'B-L',
    'precio': 120,
    'fecha_actualizacion': ahora,
  });
  await db.insert('variantes', <String, Object?>{
    'id': 201,
    'tenant_id': tenantId,
    'producto_id': 20,
    'sku_variante': 'P-30',
    'precio': 150,
    'fecha_actualizacion': ahora,
  });
  await db.insert('stock', <String, Object?>{
    'variante_id': 101,
    'sucursal_id': 1,
    'tenant_id': tenantId,
    'cantidad': 10,
    'cantidad_reservada': 0,
    'stock_minimo': 0,
    'fecha_actualizacion': ahora,
  });
  await db.insert('stock', <String, Object?>{
    'variante_id': 102,
    'sucursal_id': 1,
    'tenant_id': tenantId,
    'cantidad': 10,
    'cantidad_reservada': 0,
    'stock_minimo': 0,
    'fecha_actualizacion': ahora,
  });
  await db.insert('stock', <String, Object?>{
    'variante_id': 201,
    'sucursal_id': 1,
    'tenant_id': tenantId,
    'cantidad': 10,
    'cantidad_reservada': 0,
    'stock_minimo': 0,
    'fecha_actualizacion': ahora,
  });
}

Future<int> stockDe(
  LocalDatabaseService servicio,
  int varianteId, {
  int tenantId = tenantFase3,
}) async {
  final filas = await servicio.database!.query(
    'stock',
    where: 'variante_id = ? AND tenant_id = ?',
    whereArgs: <Object?>[varianteId, tenantId],
    limit: 1,
  );
  return (filas.single['cantidad'] as num?)?.toInt() ?? 0;
}

class ServiciosFase3 {
  ServiciosFase3({required this.db, required this.queue})
    : audit = LocalAuditService(db),
      pos = PosService(
        database: db,
        tenantId: tenantFase3,
        queue: queue,
      ),
      returns = ReturnService(
        database: db,
        tenantId: tenantFase3,
        queue: queue,
        audit: LocalAuditService(db),
      ),
      compensation = CompensationService(
        database: db,
        tenantId: tenantFase3,
      );

  final LocalDatabaseService db;
  final OfflineQueueService queue;
  final LocalAuditService audit;
  final PosService pos;
  final ReturnService returns;
  final CompensationService compensation;
}

Future<ServiciosFase3> crearServicios() async {
  final db = await abrirBaseFase3();
  await sembrarCatalogo(db);
  final queue = OfflineQueueService(
    database: db,
    tenantId: tenantFase3,
    dispositivoId: 'device-fase3',
  );
  return ServiciosFase3(db: db, queue: queue);
}

/// Mock de path_provider para generar PDFs temporales en tests.
void mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final temporal = Directory.systemTemp.createTempSync('fase3-pdfs');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async {
          switch (call.method) {
            case 'getTemporaryDirectory':
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
              return temporal.path;
            case 'getExternalStorageDirectory':
            case 'getExternalStorageDirectories':
              return null;
          }
          return null;
        },
      );
}
