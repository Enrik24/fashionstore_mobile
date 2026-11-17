// [EXAMEN-2] Ola 2 — CU05: la pantalla de descarga offline.
//
// Verifica los mensajes que exige el spec:
//   - "Datos descargados. Última actualización: [hora]" (B1.1.f)
//   - "Incompleto - requiere reconexión" (B1.1.g)
//
// Lección de la Ola 1 (§0.3): los tests de servicio no detectan los huecos
// de UI, por eso esta pantalla necesita su propio test de widget. Y la base
// FFI **no** puede tocarse desde la zona fake-async: se abre, se consulta y
// se cierra dentro de `tester.runAsync()`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/providers/offline_catalog_provider.dart';
import 'package:fashionstore_mobile/core/services/offline_catalog_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';
import 'package:fashionstore_mobile/features/offline/offline_download_page.dart';

import 'helpers/fake_offline_client.dart';

class _FakeStorageService extends StorageService {
  _FakeStorageService(SharedPreferences prefs)
    : super(secureStorage: const FlutterSecureStorage(), prefs: prefs);

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;

  /// [EXAMEN-2] Ola 2: `flutter_secure_storage` no tiene plugin registrado en
  /// un test, por lo que la llamada **se queda colgada**. Se sobreescribe
  /// para que el test no dependa del plugin nativo.
  @override
  Future<void> saveDownloadStamp(DateTime value) async {}

  @override
  DateTime? readDownloadStamp() => _sello;

  DateTime? _sello;
}

/// [EXAMEN-2] Ola 1 §0.3: la base FFI se abre dentro de `runAsync`.
Future<LocalDatabaseService> _abrirBase() async {
  sqfliteFfiInit();
  final dir = Directory.systemTemp.createTempSync('cu05-widget');
  final ruta = '${dir.path}${Platform.pathSeparator}cu05.db';
  final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
  await db.abrir(ruta: ruta);
  return db;
}

Map<String, dynamic> _paquete() => <String, dynamic>{
  'version': 'v1',
  'cursor': 'v1',
  'catalogo': <dynamic>[
    <String, dynamic>{
      'id': 10,
      'nombre': 'Blusa',
      'sku': 'BL-01',
      'precio': 100,
      'variantes': <dynamic>[
        <String, dynamic>{
          'id': 101,
          'producto_id': 10,
          'sku_variante': 'BL-M',
          'precio': 100,
        },
      ],
    },
  ],
  'stock': <dynamic>[
    <String, dynamic>{
      'variante_producto_id': 101,
      'sucursal_id': 1,
      'cantidad_disponible': 4,
    },
  ],
};

void main() {
  testWidgets('CU05: la descarga confirma la hora de actualización', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = _FakeStorageService(prefs);
    late LocalDatabaseService db;
    late OfflineCatalogProvider provider;

    await tester.runAsync(() async {
      db = await _abrirBase();
      final cliente = FakeOfflineClient(
        responder: (path, data) => path.contains('paquete')
            ? _paquete()
            : <String, dynamic>{},
      );
      provider = OfflineCatalogProvider(
        service: OfflineCatalogService(
          database: db,
          tenantId: 4,
          client: cliente,
        ),
        storageService: storage,
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OfflineCatalogProvider>.value(value: provider),
          Provider<StorageService>.value(value: storage),
        ],
        child: const MaterialApp(home: OfflineDownloadPage()),
      ),
    );
    await tester.pump();

    // Descargar: la confirmación es el mensaje del spec.
    //
    // [EXAMEN-2] Ola 2: `runAsync` tiene un presupuesto de **1 segundo** por
    // defecto; la descarga (escrituras FFI + 3 llamadas HTTP) lo excede y el
    // `runAsync` devolvía `null` mientras el trabajo seguía en segundo plano.
    // Por eso se amplía `additionalTime`.
    await tester.runAsync(() async {
      await provider.descargarPaquete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }, additionalTime: const Duration(seconds: 30));
    await tester.pump();
    final confirmacion = provider.mensajeConfirmacion;
    expect(confirmacion, isNotNull);
    expect(
      confirmacion,
      startsWith('Datos descargados. Última actualización:'),
    );
    expect(confirmacion, isNot(contains('null')));

    await tester.runAsync(() => db.cerrar());
  });

  testWidgets(
    'CU05: una descarga fallida marca "Incompleto - requiere reconexión"',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = _FakeStorageService(prefs);
      late LocalDatabaseService db;
      late OfflineCatalogProvider provider;

      await tester.runAsync(() async {
        db = await _abrirBase();
        // El servidor no responde: la descarga falla.
        final cliente = FakeOfflineClient(online: false);
        provider = OfflineCatalogProvider(
          service: OfflineCatalogService(
            database: db,
            tenantId: 4,
            client: cliente,
          ),
          storageService: storage,
        );
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<OfflineCatalogProvider>.value(
              value: provider,
            ),
            Provider<StorageService>.value(value: storage),
          ],
          child: const MaterialApp(home: OfflineDownloadPage()),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await provider.descargarPaquete();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }, additionalTime: const Duration(seconds: 30));
      await tester.pump();

      expect(provider.status.incompleto, isTrue);
      expect(provider.errorMessage, isNotNull);
      // El texto literal del spec aparece en la tarjeta.
      expect(
        find.textContaining('Incompleto - requiere reconexión'),
        findsOneWidget,
      );

      await tester.runAsync(() => db.cerrar());
    },
  );
}
