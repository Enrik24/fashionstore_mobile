// [FIX-SYNC] Regresión del bloque de sincronización y pagos diferidos:
// cola con estados terminales (como el frontend web), conflictos
// deduplicados, normalización de órdenes heredadas con
// `acepta_nuevo_total: false`, operaciones sin resultado del servidor y
// clasificador 404 que lee `detail` (NotFoundException plano del backend).
import 'package:dio/dio.dart';
import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/database/repositories/conflict_repository.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/connectivity_service.dart';
import 'package:fashionstore_mobile/core/services/local_audit_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';
import 'package:fashionstore_mobile/core/services/sync_engine_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_offline_client.dart';

/// Storage sin plugins nativos (mismo patrón que `ola3_conflictos_test`).
class _FakeStorageService extends StorageService {
  _FakeStorageService(SharedPreferences prefs)
    : super(secureStorage: const FlutterSecureStorage(), prefs: prefs);

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<String?> readOfflineToken() async => null;
}

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalDatabaseService> abrirDb() async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    return db;
  }

  OfflineQueueService cola(LocalDatabaseService db) => OfflineQueueService(
    database: db,
    tenantId: 1,
    dispositivoId: 'dev-fix',
  );

  group('cola con estados terminales', () {
    test('RECHAZADA con reintentar=true no vuelve a PENDIENTE ni se reenvía', () async {
      final db = await abrirDb();
      final queue = cola(db);
      await queue.encolar(
        uuidOperacion: 'op-r',
        tipoOperacion: 'ORDEN_PAGO_DIFERIDO',
        payload: const <String, Object?>{'acepta_nuevo_total': true},
      );

      await queue.aplicarResultado(
        uuidOperacion: 'op-r',
        estado: 'RECHAZADA',
        motivo: 'El precio central cambió; se requiere aceptar el nuevo total',
        detalle: const <String, Object?>{'requiere_aceptacion': true},
        solicitarReintento: true,
      );

      expect((await queue.obtener('op-r'))?.estadoSincronizacion, 'RECHAZADA');
      expect(await queue.pendientes(), isEmpty);
      await db.cerrar();
    });

    test('CONFLICTO tampoco se reintenta automáticamente', () async {
      final db = await abrirDb();
      final queue = cola(db);
      await queue.encolar(
        uuidOperacion: 'op-c',
        tipoOperacion: 'VENTA_CONTADO',
        payload: const <String, Object?>{},
      );

      await queue.aplicarResultado(
        uuidOperacion: 'op-c',
        estado: 'CONFLICTO',
        motivo: 'Stock insuficiente',
        detalle: const <String, Object?>{'tipo_conflicto': 'STOCK_INSUFICIENTE'},
        solicitarReintento: true,
      );

      expect((await queue.obtener('op-c'))?.estadoSincronizacion, 'CONFLICTO');
      expect(await queue.pendientes(), isEmpty);
      await db.cerrar();
    });

    test('ERROR con reintentar=true sí vuelve a PENDIENTE (transitorio)', () async {
      final db = await abrirDb();
      final queue = cola(db);
      await queue.encolar(
        uuidOperacion: 'op-e',
        tipoOperacion: 'RESERVA',
        payload: const <String, Object?>{},
      );

      await queue.aplicarResultado(
        uuidOperacion: 'op-e',
        estado: 'ERROR',
        motivo: 'Error transitorio',
        solicitarReintento: true,
      );

      expect((await queue.obtener('op-e'))?.estadoSincronizacion, 'PENDIENTE');
      await db.cerrar();
    });
  });

  group('conflictos deduplicados', () {
    test('dos resultados RECHAZADA de la misma operación ⇒ un solo conflicto', () async {
      final db = await abrirDb();
      final queue = cola(db);
      await queue.encolar(
        uuidOperacion: 'op-dup',
        tipoOperacion: 'VENTA_CONTADO',
        payload: const <String, Object?>{},
      );

      for (var i = 0; i < 2; i++) {
        await queue.aplicarResultado(
          uuidOperacion: 'op-dup',
          estado: 'RECHAZADA',
          motivo: 'Stock insuficiente',
          detalle: const <String, Object?>{'tipo_conflicto': 'STOCK_INSUFICIENTE'},
        );
      }

      final repo = ConflictRepository(db.database!, tenantId: 1);
      expect(await repo.listarPendientes(), hasLength(1));
      await db.cerrar();
    });
  });

  group('normalización de órdenes heredadas', () {
    test('payload false→true, rechazo por precio reactivado y conflictos limpiados', () async {
      final db = await abrirDb();
      final queue = cola(db);
      await queue.encolar(
        uuidOperacion: 'orden-1',
        tipoOperacion: 'ORDEN_PAGO_DIFERIDO',
        payload: const <String, Object?>{
          'uuid_pago': 'pago-1',
          'acepta_nuevo_total': false,
        },
      );
      // Rechazo heredado por precio: crea el conflicto de la operación.
      await queue.aplicarResultado(
        uuidOperacion: 'orden-1',
        estado: 'RECHAZADA',
        motivo: 'El precio central cambió; se requiere aceptar el nuevo total',
        detalle: const <String, Object?>{
          'requiere_aceptacion': true,
          'total_anterior': 70,
          'total_nuevo': 75,
        },
        solicitarReintento: true,
      );
      final conflictRepo = ConflictRepository(db.database!, tenantId: 1);
      // Duplicados heredados (el `crear` antiguo insertaba una fila por reintento).
      final ahora = DateTime.now().toUtc().toIso8601String();
      for (final uuid in <String>['orden-1', 'orden-2', 'orden-2']) {
        await db.database!.insert('conflictos', <String, Object?>{
          'tenant_id': 1,
          'uuid_operacion': uuid,
          'tipo': 'DESCONOCIDO',
          'motivo': 'duplicado heredado',
          'estado': 'CONFLICTO_MANUAL',
          'resuelto': 0,
          'fecha_registro_local': ahora,
          'fecha_actualizacion': ahora,
        });
      }

      final reactivadas = await queue.normalizarOrdenesDiferidas();

      expect(reactivadas, 1);
      final op = await queue.obtener('orden-1');
      expect(op?.estadoSincronizacion, 'PENDIENTE');
      expect(op?.payload['acepta_nuevo_total'], true);
      expect(
        (await queue.pendientes()).map((o) => o.uuidOperacion),
        contains('orden-1'),
      );
      final restantes = await conflictRepo.listarPendientes();
      expect(
        restantes.where((c) => c['uuid_operacion'] == 'orden-1'),
        isEmpty,
      );
      expect(
        restantes.where((c) => c['uuid_operacion'] == 'orden-2'),
        hasLength(1),
      );
      await db.cerrar();
    });

    test('una orden ya confirmada no se toca', () async {
      final db = await abrirDb();
      final queue = cola(db);
      await queue.encolar(
        uuidOperacion: 'orden-ok',
        tipoOperacion: 'ORDEN_PAGO_DIFERIDO',
        payload: const <String, Object?>{'acepta_nuevo_total': false},
      );
      await queue.aplicarResultado(uuidOperacion: 'orden-ok', estado: 'CONFIRMADA');

      expect(await queue.normalizarOrdenesDiferidas(), 0);
      expect((await queue.obtener('orden-ok'))?.estadoSincronizacion, 'CONFIRMADA');
      await db.cerrar();
    });
  });

  group('motor de sincronización', () {
    test('operación sin resultado vuelve a PENDIENTE y se reenvían los pagos locales', () async {
      final db = await abrirDb();
      final client = FakeOfflineClient();
      client.responder = (path, _) => path.contains('/offline/sync')
          ? <String, dynamic>{'resultados': <Map<String, dynamic>>[]}
          : <String, dynamic>{};
      final queue = cola(db);
      await queue.encolar(
        uuidOperacion: 'op-sin',
        tipoOperacion: 'VENTA_CONTADO',
        payload: const <String, Object?>{'total': 10},
      );
      final engine = SyncEngineService(
        queue: queue,
        client: client,
        connectivity: ConnectivityService(client: client),
        audit: LocalAuditService(db),
        tenantId: 1,
        dispositivoId: 'dev-fix',
      );
      var reenvios = 0;
      engine.reenviarPagosLocales = () async {
        reenvios++;
        return 0;
      };

      await engine.sincronizarAhora();

      expect((await queue.obtener('op-sin'))?.estadoSincronizacion, 'PENDIENTE');
      expect(reenvios, 1);
      await db.cerrar();
    });

    test('una orden diferida confirmada deja de estar pendiente', () async {
      final db = await abrirDb();
      final client = FakeOfflineClient();
      client.responder = (path, _) => path.contains('/offline/sync')
          ? <String, dynamic>{
              'resultados': <Map<String, dynamic>>[
                <String, dynamic>{
                  'uuid_operacion': 'orden-sync',
                  'estado': 'CONFIRMADA',
                  'datos_resultado': <String, dynamic>{'uuid_pago': 'pago-sync'},
                },
              ],
            }
          : <String, dynamic>{};
      final queue = cola(db);
      await queue.encolar(
        uuidOperacion: 'orden-sync',
        tipoOperacion: 'ORDEN_PAGO_DIFERIDO',
        payload: const <String, Object?>{
          'uuid_pago': 'pago-sync',
          'acepta_nuevo_total': true,
        },
      );
      final engine = SyncEngineService(
        queue: queue,
        client: client,
        connectivity: ConnectivityService(client: client),
        audit: LocalAuditService(db),
        tenantId: 1,
        dispositivoId: 'dev-fix',
      );

      final resumen = await engine.sincronizarAhora();

      expect(resumen.confirmadas, 1);
      expect(resumen.pendientes, 0);
      expect(await queue.pendientes(), isEmpty);
      await db.cerrar();
    });
  });

  group('clasificador 404 de pagos diferidos', () {
    test('404 con detail plano ⇒ mensaje de sincronizar, no "función no disponible"', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = ApiService(storageService: _FakeStorageService(prefs));
      final options = RequestOptions(path: '/api/v1/pagos/diferidos/uuid-x');
      final error = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 404,
          data: <String, dynamic>{'detail': 'Pago diferido no encontrado'},
        ),
      );

      final apiError = api.handleError(error);

      expect(apiError.message, contains('Sincroniza'));
      expect(apiError.message, isNot(contains('no está disponible en el servidor')));
    });

    test('404 de negocio con codigo RECURSO_NO_ENCONTRADO sigue funcionando', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = ApiService(storageService: _FakeStorageService(prefs));
      final options = RequestOptions(path: '/api/v1/pagos/diferidos/uuid-y');
      final error = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 404,
          data: <String, dynamic>{
            'codigo': 'RECURSO_NO_ENCONTRADO',
            'mensaje': 'Pago diferido no encontrado',
          },
        ),
      );

      expect(api.handleError(error).message, contains('Sincroniza'));
    });
  });
}