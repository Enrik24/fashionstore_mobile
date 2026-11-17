// [EXAMEN-2] Ola 3 — B1.5 (CU09), B1.9 (CU19) y B1.10 (CU18).
//
// Cubre la clasificación de conflictos con el contrato real del backend
// (`TipoConflicto` / `EstrategiaResolucion` / `SYNC_CONFLICTO_UMBRAL_PRECIO`),
// el reintento de compensación y el falso éxito, y las alternativas de talla
// en el catálogo local.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/compensation_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/return_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';
import 'package:fashionstore_mobile/core/utils/conflict_classifier.dart';
import 'package:fashionstore_mobile/core/utils/sync_messages.dart';

import '../helpers/fase3_helpers.dart';

/// Adaptador falso: responde con un cuerpo fijo y registra las rutas.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.body);

  final String body;
  final int statusCode = 200;
  final List<String> paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
/// Storage sin plugins nativos (mismo patrón que `cu18_reposicion_offline_test`).
class _FakeStorageService extends StorageService {
  _FakeStorageService(SharedPreferences prefs)
    : super(secureStorage: const FlutterSecureStorage(), prefs: prefs);

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;

  /// [EXAMEN-2] Ola 3: el interceptor de `ApiService` lee el token offline
  /// en las rutas `/offline/*`; sin este override el plugin de
  /// `flutter_secure_storage` no existe en el test y revienta la petición.
  @override
  Future<String?> readOfflineToken() async => null;

  @override
  Future<void> saveOfflineToken(String token) async {}
}

Future<ApiService> _apiConAdaptador(_FakeHttpAdapter adapter) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = ApiService(storageService: _FakeStorageService(prefs));
  api.dio.httpClientAdapter = adapter;
  return api;
}

void main() {
  // [EXAMEN-2] Ola 3: `shared_preferences` y `dio` necesitan el binding
  // inicializado en un `test()` normal.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B1.5 CU09 — clasificación de conflictos', () {
    test('la variación de precio ≤ 5% se resuelve automáticamente', () {
      final clasificacion = ConflictClassifier.clasificar(<String, Object?>{
        'tipo_conflicto': TiposConflicto.precioDesactualizado,
        'estrategia_resolucion': EstrategiasResolucion.automatica,
        'diferencias': <Map<String, Object?>>[
          <String, Object?>{
            'precio_local': 100.0,
            'precio_central': 103.0,
            'diferencia': -3.0,
            'diferencia_porcentaje': 0.03,
            'resoluble_automaticamente': true,
          },
        ],
      });
      expect(clasificacion.resolubleAutomaticamente, isTrue);
      expect(clasificacion.diferenciaPorcentaje, 0.03);
      expect(clasificacion.estado, EstadosConflicto.conflicto);
    });

    test('la variación de precio > 5% exige decisión humana', () {
      final clasificacion = ConflictClassifier.clasificar(<String, Object?>{
        'tipo_conflicto': TiposConflicto.precioDesactualizado,
        'estrategia_resolucion': EstrategiasResolucion.manual,
        'diferencias': <Map<String, Object?>>[
          <String, Object?>{
            'precio_local': 100.0,
            'precio_central': 110.0,
            'diferencia': -10.0,
            'diferencia_porcentaje': 0.10,
            'resoluble_automaticamente': false,
          },
        ],
      });
      expect(clasificacion.resolubleAutomaticamente, isFalse);
      // B1.5.b: estado `CONFLICTO_MANUAL`.
      expect(clasificacion.estado, EstadosConflicto.conflictoManual);
    });

    test('el umbral del 5% se recalcula si el backend no lo envía', () {
      final clasificacion = ConflictClassifier.clasificar(<String, Object?>{
        'tipo_conflicto': TiposConflicto.precioDesactualizado,
        'total_local': 100.0,
        'total_central': 108.0,
      });
      // El backend calcula bs(diferencia) / precio_central = 8/108.
      expect(clasificacion.diferenciaPorcentaje, closeTo(0.0741, 0.0001));
      expect(clasificacion.resolubleAutomaticamente, isFalse);
      expect(clasificacion.estado, EstadosConflicto.conflictoManual);
    });

    test('B1.5.c: producto inactivo o variante inexistente ⇒ ERROR_DATOS', () {
      for (final tipo in <String>[
        TiposConflicto.productoInactivo,
        TiposConflicto.varianteInexistente,
        TiposConflicto.sucursalInvalida,
      ]) {
        final clasificacion = ConflictClassifier.clasificar(
          <String, Object?>{'tipo_conflicto': tipo},
        );
        expect(clasificacion.estado, EstadosConflicto.errorDatos);
      }
    });

    test('B1.5.d/e: pago capturado y duplicado requieren al servidor', () {
      expect(
        ConflictClassifier.requiereIntervencionServidor(
          TiposConflicto.pagoYaCapturado,
        ),
        isTrue,
      );
      expect(
        ConflictClassifier.requiereIntervencionServidor(
          TiposConflicto.pagoDuplicado,
        ),
        isTrue,
      );
      expect(
        ConflictClassifier.requiereIntervencionServidor(
          TiposConflicto.stockInsuficiente,
        ),
        isFalse,
      );
    });

    test('los tipos de conflicto del backend tienen mensaje propio', () {
      expect(
        SyncMessages.traducirTipoConflicto(
          TiposConflicto.stockInsuficiente,
        ),
        contains('Stock insuficiente'),
      );
      expect(
        SyncMessages.traducirMotivo(TiposConflicto.pagoYaCapturado),
        contains('reembolso'),
      );
      expect(
        SyncMessages.traducirEstado(EstadosConflicto.conflictoManual),
        contains('decisión del administrador'),
      );
      expect(
        SyncMessages.traducirEstado(EstadosConflicto.errorDatos),
        contains('datos maestros'),
      );
    });

    test(
      'el conflicto se guarda con su tipo y estado (contrato datos_resultado)',
      () async {
        final db = await abrirBaseFase3();
        final queue = OfflineQueueService(
          database: db,
          tenantId: tenantFase3,
          dispositivoId: 'device-conflicto',
        );
        await queue.aplicarResultado(
          uuidOperacion: 'uuid-conflicto-1',
          estado: 'CONFLICTO',
          motivo: 'El precio cambió',
          tipoConflicto: TiposConflicto.precioDesactualizado,
          detalle: <String, Object?>{
            'tipo_conflicto': TiposConflicto.precioDesactualizado,
            'estrategia_resolucion': EstrategiasResolucion.manual,
            'diferencias': <Map<String, Object?>>[
              <String, Object?>{
                'precio_local': 100.0,
                'precio_central': 130.0,
                'diferencia_porcentaje': 0.30,
                'resoluble_automaticamente': false,
              },
            ],
          },
        );

        final filas = await db.database!.query(
          'conflictos',
          where: 'uuid_operacion = ?',
          whereArgs: <Object?>['uuid-conflicto-1'],
        );
        expect(filas, hasLength(1));
        expect(filas.single['tipo'], TiposConflicto.precioDesactualizado);
        // B1.5.b: requiere decisión humana.
        expect(filas.single['estado'], EstadosConflicto.conflictoManual);
        await db.cerrar();
      },
    );
  });

  group('B1.10 CU18 — alternativas de talla en el catálogo local', () {
    test('encuentra una talla mayor con stock en otra sucursal', () async {
      final db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      final returns = ReturnService(
        database: db,
        tenantId: tenantFase3,
      );

      // La variante 101 (B-M) tiene 10 unidades en la sucursal 1; se añade
      // stock de la variante 102 (B-L) en la sucursal 2.
      await db.database!.insert('stock', <String, Object?>{
        'variante_id': 102,
        'sucursal_id': 2,
        'tenant_id': tenantFase3,
        'cantidad': 4,
        'cantidad_reservada': 0,
        'stock_minimo': 0,
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      });

      final alternativas = await returns.buscarAlternativaLocal(
        varianteId: 101,
        sucursalId: 1,
        direccion: 'MAYOR',
      );
      expect(alternativas, isNotEmpty);
      expect(alternativas.first['variante_id'], 102);
      expect(alternativas.first['sucursal_id'], 2);
      expect(alternativas.first['stock'], 4);
      // B1.10.f: se puede ofrecer traspaso a esa sucursal.
      expect(alternativas.first['traspaso_disponible'], isTrue);
      await db.cerrar();
    });

    test('sin alternativa devuelve lista vacía', () async {
      final db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      final returns = ReturnService(
        database: db,
        tenantId: tenantFase3,
      );
      // La variante 201 (P-30) es la única de su producto: no hay alternativa.
      final alternativas = await returns.buscarAlternativaLocal(
        varianteId: 201,
        sucursalId: 1,
        direccion: 'MAYOR',
      );
      expect(alternativas, isEmpty);
      await db.cerrar();
    });

    test('B1.10.h: sin conexión la diferencia sólo se cobra en efectivo', () async {
      final db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      final returns = ReturnService(
        database: db,
        tenantId: tenantFase3,
      );
      // [EXAMEN-2] Ola 3: `expect(() => future, throwsA(...))` NO espera la
      // promesa: la prueba avanzaba y cerraba la base mientras la operación
      // seguía en vuelo (y la aserción "pasaba" sin comprobar nada).
      // Con `await expectLater` la espera sí.
      await expectLater(
        returns.crearReposicionOffline(
          numeroComprobanteOrigen: 'FAC-9001',
          sucursalId: 1,
          offline: true,
          metodoPagoDiferencia: 'TARJETA',
          items: const [
            LineaDevolucion(
              varianteProductoId: 101,
              productoId: 10,
              cantidad: 1,
              precioUnitario: 100,
              varianteCambioId: 102,
              precioVarianteNueva: 130,
            ),
          ],
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'mensaje',
            contains('efectivo'),
          ),
        ),
      );
      await db.cerrar();
    });

    test('B1.10.i: el cobro de la diferencia queda en el libro de movimientos', () async {
      final db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      final returns = ReturnService(
        database: db,
        tenantId: tenantFase3,
      );
      await returns.crearReposicionOffline(
        numeroComprobanteOrigen: 'FAC-9002',
        sucursalId: 1,
        metodoPagoDiferencia: 'EFECTIVO',
        items: const [
          LineaDevolucion(
            varianteProductoId: 101,
            productoId: 10,
            cantidad: 1,
            precioUnitario: 100,
            varianteCambioId: 102,
            precioVarianteNueva: 130,
          ),
        ],
      );
      final movimientos = await db.database!.query(
        'movimientos_inventario',
        where: 'tipo = ?',
        whereArgs: <Object?>['COBRO_DIFERENCIA'],
      );
      expect(movimientos, hasLength(1));
      await db.cerrar();
    });
  });

  group('B1.9 CU19 — compensación', () {
    test('B1.9.c: una respuesta no reconocida NO marca COMPLETADA', () async {
      final db = await abrirBaseFase3();
      // El backend responde 200 pero con un cuerpo que **no** es la
      // compensación: antes la app caía al camino local y marcaba
      // COMPLETADA sin confirmación del servidor (falso éxito).
      final api = await _apiConAdaptador(
        _FakeHttpAdapter('respuesta-no-reconocible'),
      );
      final service = CompensationService(
        database: db,
        tenantId: tenantFase3,
        apiService: api,
      );
      // Se siembra una compensación en efectivo pendiente.
      await db.database!.insert('compensaciones', <String, Object?>{
        'id': 1,
        'tenant_id': tenantFase3,
        'uuid_operacion': 'uuid-op-comp-1',
        'monto': 100.0,
        'moneda': 'BOB',
        'tipo': 'REEMBOLSO_EFECTIVO',
        'estado': 'PENDIENTE',
        'notificado_cliente': 0,
        'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      });

      // [EXAMEN-2] Ola 3: hay que **esperar** la promesa (ver nota del
      // test de la diferencia de precio).
      await expectLater(
        service.confirmarEfectivo(1, esCajero: true, cajeroId: 9),
        throwsA(isA<StateError>()),
      );

      final filas = await db.database!.query(
        'compensaciones',
        where: 'id = ?',
        whereArgs: <Object?>[1],
      );
      // No debe quedar COMPLETADA: el efectivo no se dio por entregado.
      expect(filas.single['estado'], isNot('COMPLETADA'));
      expect(filas.single['estado'], 'FALLIDA');
      await db.cerrar();
    });

    test('B1.9.a: el reintento pide al backend y no ejecuta el reembolso', () async {
      final db = await abrirBaseFase3();
      final adaptador = _FakeHttpAdapter(
        jsonEncode(<String, Object?>{
          'id': 1,
          'uuid_operacion': 'uuid-op-comp-2',
          'monto': 100.0,
          'moneda': 'BOB',
          'tipo': 'REEMBOLSO_TARJETA',
          'estado': 'EN_PROCESO',
        }),
      );
      final api = await _apiConAdaptador(adaptador);
      final service = CompensationService(
        database: db,
        tenantId: tenantFase3,
        apiService: api,
      );
      await db.database!.insert('compensaciones', <String, Object?>{
        'id': 1,
        'tenant_id': tenantFase3,
        'uuid_operacion': 'uuid-op-comp-2',
        'monto': 100.0,
        'moneda': 'BOB',
        'tipo': 'REEMBOLSO_TARJETA',
        'estado': 'FALLIDA',
        'notificado_cliente': 0,
        'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      });

      final modelo = await service.reintentar(1);
      expect(modelo.estado, 'EN_PROCESO');
      // La app **solicita** el reintento; no cobra.
      expect(adaptador.paths, contains('/offline/compensaciones/1/reintentar'));
      await db.cerrar();
    });
  });
}
