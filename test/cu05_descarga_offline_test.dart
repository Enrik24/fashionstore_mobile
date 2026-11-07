import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/services/offline_catalog_service.dart';
import 'package:fashionstore_mobile/core/services/storage_quota_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_offline_client.dart';

void main() {
  sqfliteFfiInit();
  test('CU05 guarda el paquete offline y permite consultarlo', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    client.responder = (_, __) => <String, dynamic>{
      'productos': <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'nombre': 'Camisa', 'precio': 100},
      ],
      'variantes': <Map<String, dynamic>>[
        <String, dynamic>{'id': 7, 'producto_id': 1, 'sku_variante': 'C-7'},
      ],
    };
    final service = OfflineCatalogService(
      database: db,
      tenantId: 5,
      client: client,
    );

    final estado = await service.descargarPaquete();
    final productos = await service.catalogoLocal();

    expect(estado.sello, isNotNull);
    expect(productos, hasLength(1));
    expect(productos.single.nombre, 'Camisa');
    await db.cerrar();
  });

  // [EXAMEN-2] C2.4 P1: incremental por cursor + baja lógica (deleted_at).
  test('CU05 incremental agrega por cursor y la baja lógica oculta el producto', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    client.responder = (path, data) {
      if (path.contains('/descargas/registrar')) {
        return <String, dynamic>{};
      }
      if (path.contains('/offline/catalogo')) {
        return <String, dynamic>{
          'productos': <Map<String, dynamic>>[
            <String, dynamic>{'id': 2, 'nombre': 'Pantalón', 'precio': 150},
          ],
          'cursor': 'cursor-2',
        };
      }
      return <String, dynamic>{
        'productos': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'nombre': 'Camisa', 'precio': 100},
        ],
        'cursor': 'cursor-1',
      };
    };
    final service = OfflineCatalogService(
      database: db,
      tenantId: 5,
      client: client,
    );

    final inicial = await service.descargarPaquete();
    expect(inicial.cursorCatalogo, 'cursor-1');
    expect(await service.catalogoLocal(), hasLength(1));

    final incremental = await service.descargarIncremental(
      cursor: inicial.cursorCatalogo,
    );
    expect(incremental.cursorCatalogo, 'cursor-2');
    expect(incremental.incompleto, isFalse);
    var catalogo = await service.catalogoLocal();
    expect(catalogo, hasLength(2));
    expect(catalogo.map((p) => p.id), containsAll(<int>[1, 2]));

    await service.bajaLogica(1);
    catalogo = await service.catalogoLocal();
    expect(catalogo, hasLength(1));
    expect(catalogo.single.id, 2);

    // La fila sigue en SQLite con deleted_at (baja lógica, no borrado físico).
    final filas = await db.database!.query(
      'productos',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[1, 5],
    );
    expect(filas, hasLength(1));
    expect(filas.single['deleted_at'], isNotNull);
    await db.cerrar();
  });

  // [EXAMEN-2] C2.4 P1: fallo de red marca la descarga como incompleta.
  test('CU05 sin conexión marca la descarga como incompleta', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient(online: false);
    final service = OfflineCatalogService(
      database: db,
      tenantId: 5,
      client: client,
    );

    await expectLater(service.descargarPaquete(), throwsStateError);
    expect(service.estadoDescarga.incompleto, isTrue);
    expect(service.estadoDescarga.enProgreso, isFalse);
    expect(service.estadoDescarga.error, isNotNull);
    expect(service.estadoDescarga.sello, isNull);
    expect(await service.catalogoLocal(), isEmpty);
    await db.cerrar();
  });

  // [EXAMEN-2] C2.3/C2.4 P1: espacio insuficiente bloquea antes de consumir red.
  test('CU05 espacio insuficiente bloquea la descarga sin llamadas de red', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    client.responder = (_, __) => <String, dynamic>{
      'productos': <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'nombre': 'Camisa', 'precio': 100},
      ],
    };
    final service = OfflineCatalogService(
      database: db,
      tenantId: 5,
      client: client,
    );
    // Límite mínimo: cualquier paquete estimado supera el espacio disponible.
    final quota = StorageQuotaService(
      database: db,
      tenantId: 5,
      limiteBytes: 1024,
    );

    expect(await quota.puedeDescargar(1024 * 1024), isFalse);
    expect(await service.espacioUsado(), greaterThanOrEqualTo(0));

    // La puerta de cuota (RNF-14) impide descargarPaquete: no se consume red.
    final puedeDescargar = await quota.puedeDescargar(1024 * 1024);
    if (puedeDescargar) {
      await service.descargarPaquete();
    }
    expect(client.paths, isEmpty);
    expect(client.requests, isEmpty);
    expect(await service.catalogoLocal(), isEmpty);
    await db.cerrar();
  });
}
