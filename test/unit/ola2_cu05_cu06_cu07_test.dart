// [EXAMEN-2] Ola 2 — B1.1 (CU05), B1.2 (CU06) y B1.3 (CU07).
//
// Cubre lo que el backend **ya enviaba** en el paquete offline y que el móvil
// ignoraba, el comprobante temporal de la reserva, la bitácora local de la
// venta y el contrato HTTP del catálogo incremental.
import 'dart:convert';
import 'dart:io' show File, SocketException;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/database/repositories/local_config_repository.dart';
import 'package:fashionstore_mobile/core/database/repositories/local_permissions_repository.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/offline_catalog_service.dart';
import 'package:fashionstore_mobile/core/services/offline_document_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/pos_service.dart';
import 'package:fashionstore_mobile/core/services/reservation_service.dart';
import 'package:fashionstore_mobile/core/services/storage_quota_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';

import '../helpers/fake_offline_client.dart';
import '../helpers/fase3_helpers.dart';

/// Adaptador que simula **falta de conexión** (el servidor no responde).
///
/// [EXAMEN-2] B1.2.k: con este error la reserva **degrada a local**; un 4xx
/// (el servidor respondió) debe propagarse.
class _SinConexionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: 'sin conexión',
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
}

Future<ApiService> _apiSinConexion() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = ApiService(storageService: _FakeStorageService(prefs));
  api.dio.httpClientAdapter = _SinConexionAdapter();
  return api;
}

/// [EXAMEN-2] B1.2: servicio de reservas **sin conexión**, con documentos
/// inyectados (el comprobante temporal es requisito del CU06).
Future<ReservationService> _servicioReservaOffline(
  LocalDatabaseService db,
  OfflineQueueService queue,
  Object? documents,
) async {
  final api = await _apiSinConexion();
  return ReservationService(
    apiService: api,
    database: db,
    tenantId: tenantFase3,
    queue: queue,
    documents: documents,
    usuarioId: 42,
  );
}

/// Paquete offline tal como lo arma el backend (`PaqueteOfflineService`).
Map<String, dynamic> _paquete({
  double tasaTotal = 0.13,
  String moneda = 'BOB',
  int maxClientes = 100,
  int maxHorasSesion = 4,
}) => <String, dynamic>{
  'tenant_id': tenantFase3,
  'version': 'v-hash-1',
  'cursor': 'v-hash-1',
  'configuracion_offline': <String, dynamic>{
    'descarga_automatica': true,
    'hora_descarga': '03:00:00',
    'incluir_clientes': true,
    'max_clientes': maxClientes,
    'habilitar_carrito_offline': true,
    'max_horas_sesion_offline': maxHorasSesion,
    'max_dias_orden_pendiente': 3,
  },
  'impuestos': <String, dynamic>{
    'moneda': moneda,
    'impuestos': <dynamic>[],
    'tasa_total': tasaTotal,
  },
  'stripe': <String, dynamic>{
    'stripe_publishable_key': 'pk_test_1234567890',
    'moneda': moneda,
    'modo_simulado': true,
  },
  'permisos': <String, dynamic>{
    'usuario_id': 42,
    'roles': <String>['cajero'],
    'permisos': <String>['ventas', 'devoluciones'],
  },
  'catalogo': <dynamic>[
    for (var i = 0; i < 4; i++)
      <String, dynamic>{
        'id': 10 + i,
        'nombre': 'Prenda $i',
        'sku': 'PR-0$i',
        'precio': 100 + i,
        'variantes': <dynamic>[
          <String, dynamic>{
            'id': 101 + i,
            'producto_id': 10 + i,
            'sku_variante': 'PR-M$i',
            'precio': 100 + i,
          },
        ],
      },
  ],
  'variantes': <dynamic>[],
  'stock': <dynamic>[
    <String, dynamic>{
      'variante_producto_id': 101,
      'sucursal_id': 1,
      'cantidad_disponible': 7,
    },
  ],
  'datos_maestros': <String, dynamic>{
    'categorias': <dynamic>[],
    'tallas': <dynamic>[],
    'colores': <dynamic>[],
  },
  'clientes_frecuentes': <dynamic>[
    <String, dynamic>{'id': 1, 'nit_ci': '1111111', 'telefono': '70000000'},
  ],
};

void main() {
  group('B1.1 CU05 — el paquete offline se consume completo', () {
    test('persiste impuestos, clave pública de Stripe y permisos', () async {
      final db = await abrirBaseFase3();
      final cliente = FakeOfflineClient(
        responder: (path, data) => path.contains('paquete')
            ? _paquete()
            : <String, dynamic>{},
      );
      final configRepo = LocalConfigRepository(db);
      final permisosRepo = LocalPermissionsRepository(db);
      final service = OfflineCatalogService(
        database: db,
        tenantId: tenantFase3,
        client: cliente,
      );
      service.configurarRepositorios(
        config: configRepo,
        permissions: permisosRepo,
      );

      await service.descargarPaquete();

      // B1.1.a: los impuestos ya no se descartan.
      expect(await configRepo.leerTasaImpuestos(tenantFase3), 0.13);
      final config = await configRepo.leer(tenantFase3);
      expect(config, isNotNull);
      expect(config!.tasaImpuestos, 0.13);
      // B1.1.d: la configuración del tenant se aplica.
      expect(config.maxHorasSesionOffline, 4);
      expect(config.maxDiasOrdenPendiente, 3);
      expect(config.habilitarCarritoOffline, isTrue);

      // B1.1.b: la clave **pública** de Stripe (nunca la secreta).
      final clave = await configRepo.leerClavePublicaStripe(tenantFase3);
      expect(clave, 'pk_test_1234567890');
      expect(clave, isNot(contains('sk_')));

      // B1.1.c: los permisos del usuario quedan disponibles offline.
      final permisos = await permisosRepo.leerPermisos(
        tenantId: tenantFase3,
        usuarioId: 42,
      );
      expect(permisos, contains('ventas'));

      await db.cerrar();
    });

    test('el catálogo local guarda el stock del paquete', () async {
      final db = await abrirBaseFase3();
      final cliente = FakeOfflineClient(
        responder: (path, data) => path.contains('paquete')
            ? _paquete()
            : <String, dynamic>{},
      );
      final service = OfflineCatalogService(
        database: db,
        tenantId: tenantFase3,
        client: cliente,
      );
      await service.descargarPaquete();

      final stock = await service.disponibilidadLocal(sucursalId: 1);
      expect(stock[101], 7);
      await db.cerrar();
    });

    test('B1.1.l: el incremental usa el query param desde_version', () async {
      final db = await abrirBaseFase3();
      final cliente = FakeOfflineClient(
        responder: (path, data) => path.contains('catalogo')
            ? <String, dynamic>{'cursor': 'v2', 'productos': <dynamic>[]}
            : <String, dynamic>{},
      );
      final service = OfflineCatalogService(
        database: db,
        tenantId: tenantFase3,
        client: cliente,
      );
      await service.descargarIncremental(cursor: 'v1');
      expect(cliente.queries.last['desde_version'], 'v1');
      // El parámetro antiguo `cursor` no debe enviarse: el router lo ignora.
      expect(cliente.queries.last.containsKey('cursor'), isFalse);
      await db.cerrar();
    });

    test('B1.1.i: la cuota ofrece descarga selectiva en vez de fallar', () async {
      final db = await abrirBaseFase3();
      final cliente = FakeOfflineClient(
        responder: (path, data) => path.contains('paquete')
            ? _paquete()
            : <String, dynamic>{},
      );
      final service = OfflineCatalogService(
        database: db,
        tenantId: tenantFase3,
        client: cliente,
      );
      // El paquete completo no cabe, pero hay espacio para **algunas** prendas:
      // la app debe ofrecer la descarga selectiva en lugar de fallar sin más.
      final usado = await db.espacioUsado();
      final estimado = jsonEncode(_paquete()).length;
      service.configurarQuota(
        StorageQuotaService(
          database: db,
          tenantId: tenantFase3,
          limiteBytes: usado + (estimado ~/ 2),
        ),
      );

      Object? fallo;
      try {
        await service.descargarPaquete();
      } catch (e) {
        fallo = e;
      }
      expect(fallo, isA<CuotaInsuficienteException>());
      final cuota = fallo! as CuotaInsuficienteException;
      expect(cuota.maxProductos, greaterThanOrEqualTo(1));
      await db.cerrar();
    });

    test('B1.1.i: la descarga selectiva trunca y guarda sólo lo prioritario',
        () async {
      final db = await abrirBaseFase3();
      final cliente = FakeOfflineClient(
        responder: (path, data) => path.contains('paquete')
            ? _paquete()
            : <String, dynamic>{},
      );
      final service = OfflineCatalogService(
        database: db,
        tenantId: tenantFase3,
        client: cliente,
      );
      await service.descargarPaquete(limiteProductos: 1);
      final catalogo = await service.catalogoLocal();
      expect(catalogo, hasLength(1));
      await db.cerrar();
    });
  });

  group('B1.3 CU07 — bitácora local de la venta', () {
    test('deja rastro en bitacora_local con tipo VENTA_CONTADO', () async {
      final db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-bitacora',
        usuarioId: 42,
      );
      final pos = PosService(
        database: db,
        tenantId: tenantFase3,
        queue: queue,
        usuarioId: 42,
      );
      pos.iniciarVenta();
      pos.agregarProducto(
        varianteProductoId: 101,
        cantidad: 2,
        precioUnitario: 100,
        nombre: 'Blusa',
        stockConocido: 10,
      );
      final venta = await pos.confirmarVentaOffline(
        sucursalId: 1,
        cajeroId: 42,
        montoRecibido: 200,
      );

      final filas = await db.database!.query(
        'bitacora_local',
        where: 'tipo = ?',
        whereArgs: <Object?>['VENTA_CONTADO'],
      );
      expect(filas, hasLength(1));
      final datos = jsonDecode(filas.single['datos'] as String) as Map;
      expect(datos['uuid_operacion'], venta.uuidOffline);
      expect(datos['total'], 200);
      expect(datos['cambio'], 0);
      expect(datos['metodo_pago'], 'EFECTIVO');
      await db.cerrar();
    });
  });

  group('B1.2 CU06 — reserva offline', () {
    test('genera el comprobante temporal y lo registra', () async {
      mockPathProvider();
      final db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-reserva',
        usuarioId: 42,
      );
      final docs = OfflineDocumentService(
        database: db,
        tenantId: tenantFase3,
      );
      final service = await _servicioReservaOffline(db, queue, docs);

      final reserva = await service.crearReserva(
        sucursalId: 1,
        fechaReserva: DateTime.now().add(const Duration(days: 2)),
        items: const <Map<String, dynamic>>[
          <String, dynamic>{'variante_producto_id': 101, 'cantidad': 1},
        ],
      );

      expect(reserva.esOffline, isTrue);
      expect(reserva.estado, 'PENDIENTE_SINCRONIZACION');

      // B1.2.a/b: el comprobante temporal existe y está registrado.
      final comprobantes = await db.database!.query(
        'comprobantes',
        where: 'tipo_operacion = ?',
        whereArgs: <Object?>['RESERVA'],
      );
      expect(comprobantes, hasLength(1));
      expect(comprobantes.single['es_temporal'], 1);
      expect(comprobantes.single['ruta_archivo'], isNotNull);

      await db.cerrar();
    });

    test('el forzado por stock insuficiente marca requiere_revision', () async {
      mockPathProvider();
      final db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-reserva-2',
        usuarioId: 42,
      );
      final service = await _servicioReservaOffline(
        db,
        queue,
        OfflineDocumentService(database: db, tenantId: tenantFase3),
      );

      await service.crearReserva(
        sucursalId: 1,
        fechaReserva: DateTime.now().add(const Duration(days: 2)),
        // La variante 101 tiene 10 unidades; se piden 5 con stock forzado.
        forzar: true,
        items: const <Map<String, dynamic>>[
          <String, dynamic>{'variante_producto_id': 101, 'cantidad': 5},
        ],
      );

      final reserva = await db.database!.query(
        'reservas_locales',
        where: 'tenant_id = ?',
        whereArgs: <Object?>[tenantFase3],
      );
      expect(reserva.single['requiere_revision'], 1);

      final operacion = await db.database!.query(
        'operaciones',
        where: 'tenant_id = ?',
        whereArgs: <Object?>[tenantFase3],
      );
      expect(operacion.single['payload_json'], contains('requiere_revision'));
      await db.cerrar();
    });

    test('la reserva offline queda en la pestaña de pendientes', () async {
      mockPathProvider();
      final db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-reserva-3',
        usuarioId: 42,
      );
      final service = await _servicioReservaOffline(
        db,
        queue,
        OfflineDocumentService(database: db, tenantId: tenantFase3),
      );

      final reserva = await service.crearReserva(
        sucursalId: 1,
        fechaReserva: DateTime.now().add(const Duration(days: 2)),
        items: const <Map<String, dynamic>>[
          <String, dynamic>{'variante_producto_id': 101, 'cantidad': 1},
        ],
      );

      // B1.2.h: `isPending` debe incluir `PENDIENTE_SINCRONIZACION`.
      expect(reserva.isPending, isTrue);
      expect(reserva.isPendienteDeSincronizacion, isTrue);
      await db.cerrar();
    });
  });

  group('B2 — precacheo de imágenes del catálogo (exploración offline)', () {
    test('sin imágenes el precacheo no hace nada y no lanza', () async {
      final db = await abrirBaseFase3();
      final service = OfflineCatalogService(
        database: db,
        tenantId: tenantFase3,
        client: FakeOfflineClient(
          responder: (path, data) => <String, dynamic>{},
        ),
        precachearImagen: (url) async => File(url),
      );
      expect(await service.precacheImagenes(), 0);
      await db.cerrar();
    });

    test('precachea las imágenes de los productos descargados', () async {
      final db = await abrirBaseFase3();
      final ahora = DateTime.now().toUtc().toIso8601String();
      await db.database!.insert('productos', <String, Object?>{
        'id': 30,
        'tenant_id': tenantFase3,
        'nombre': 'Chamarra',
        'precio': 200,
        'imagenes': '["https://img.test/foto-a.jpg","https://img.test/foto-a2.jpg"]',
        'fecha_actualizacion': ahora,
      });
      await db.database!.insert('productos', <String, Object?>{
        'id': 31,
        'tenant_id': tenantFase3,
        'nombre': 'Falda',
        'precio': 90,
        'imagenes': '["https://img.test/foto-b.jpg"]',
        'fecha_actualizacion': ahora,
      });
      // Un producto sin imágenes: no aporta URLs.
      await db.database!.insert('productos', <String, Object?>{
        'id': 32,
        'tenant_id': tenantFase3,
        'nombre': 'Bufanda',
        'precio': 30,
        'fecha_actualizacion': ahora,
      });
      final urlsPrecacheadas = <String>[];
      final service = OfflineCatalogService(
        database: db,
        tenantId: tenantFase3,
        client: FakeOfflineClient(
          responder: (path, data) => <String, dynamic>{},
        ),
        precachearImagen: (url) async {
          urlsPrecacheadas.add(url);
          return File(url);
        },
      );
      final precacheadas = await service.precacheImagenes();
      expect(precacheadas, 3);
      expect(urlsPrecacheadas, hasLength(3));
      // El límite de seguridad se respeta (aquí 1 imagen).
      await db.database!.insert('productos', <String, Object?>{
        'id': 33,
        'tenant_id': tenantFase3,
        'nombre': 'Gabardina',
        'precio': 250,
        'imagenes': '["https://img.test/foto-c.jpg"]',
        'fecha_actualizacion': ahora,
      });
      urlsPrecacheadas.clear();
      final conLimite = await service.precacheImagenes(maxImagenes: 2);
      expect(conLimite, 2);
      expect(urlsPrecacheadas, hasLength(2));
      await db.cerrar();
    });

    test('un fallo de descarga no aborta las demás imágenes', () async {
      final db = await abrirBaseFase3();
      final ahora = DateTime.now().toUtc().toIso8601String();
      await db.database!.insert('productos', <String, Object?>{
        'id': 40,
        'tenant_id': tenantFase3,
        'nombre': 'Poncho',
        'precio': 150,
        'imagenes': '["https://img.test/x1.jpg","https://img.test/x2.jpg"]',
        'fecha_actualizacion': ahora,
      });
      final service = OfflineCatalogService(
        database: db,
        tenantId: tenantFase3,
        client: FakeOfflineClient(
          responder: (path, data) => <String, dynamic>{},
        ),
        precachearImagen: (url) async {
          if (url.endsWith('x1.jpg')) throw const SocketException('sin red');
          return File(url);
        },
      );
      final precacheadas = await service.precacheImagenes(
        timeoutPorImagen: const Duration(milliseconds: 500),
      );
      expect(precacheadas, 1);
      await db.cerrar();
    });
  });
}
