import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/models/api_response.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/cart_service.dart';
import 'package:fashionstore_mobile/core/services/offline_cart_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/pending_payment_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';
import 'package:fashionstore_mobile/core/widgets/carrito_offline_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_offline_client.dart';

void main() {
  sqfliteFfiInit();
  test('CU15 conserva el carrito entre consultas locales', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final cart = OfflineCartService(
      database: db,
      tenantId: 6,
      dispositivoId: 'device-cart',
    );

    await cart.agregarItem(
      varianteProductoId: 4,
      cantidad: 2,
      precioUnitario: 25,
    );
    final recuperado = await cart.obtenerCarritoLocal();

    expect(recuperado, isNotNull);
    expect(recuperado!.items, hasLength(1));
    expect(recuperado.total, 50);
    expect(recuperado.uuidCarrito, isNotEmpty);
    await db.cerrar();
  });
  test(
    'CU15 convierte el carrito local en orden y pago diferido idempotentes',
    () async {
      final db = LocalDatabaseService(
        factory: databaseFactoryFfi,
        cifrar: false,
      );
      await db.abrir(ruta: inMemoryDatabasePath);
      final client = FakeOfflineClient();
      final queue = OfflineQueueService(
        database: db,
        tenantId: 6,
        dispositivoId: 'device-cart',
      );
      final pending = PendingPaymentService(
        database: db,
        tenantId: 6,
        client: client,
      );
      final cart = OfflineCartService(
        database: db,
        tenantId: 6,
        dispositivoId: 'device-cart',
        queue: queue,
        pendingPayments: pending,
      );
      await cart.agregarItem(
        varianteProductoId: 4,
        cantidad: 2,
        precioUnitario: 25,
      );

      final conversion = await cart.convertirEnPagoDiferido(
        sucursalId: 1,
        direccionEnvio: 'Direcci?n local',
        clienteId: null,
      );

      expect(conversion.uuidOrden, isNotEmpty);
      expect(conversion.uuidPago, isNotEmpty);
      expect(conversion.total, 50);
      expect(await cart.obtenerCarritoLocal(), isNull);
      expect(
        (await queue.pendientes()).single.tipoOperacion,
        'ORDEN_PAGO_DIFERIDO',
      );
      expect((await pending.pendientes()).single.uuidPago, conversion.uuidPago);
      await db.cerrar();
    },
  );

  // [EXAMEN-2] C2.5 P1: habilitarCarritoOffline=false bloquea agregar y convertir.
  test('CU15 habilitarCarritoOffline=false bloquea el carrito offline', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(
      secureStorage: const FlutterSecureStorage(),
      prefs: prefs,
    );
    final api = ApiService(storageService: storage);
    final cart = CartService(apiService: api, habilitarCarritoOffline: false);

    expect(carritoOfflineGuard(cart), isFalse);
    String? mensaje;
    expect(
      carritoOfflineGuard(cart, onBloqueo: (m) => mensaje = m),
      isFalse,
    );
    expect(mensaje, CartService.mensajeCarritoOfflineDeshabilitado);

    await expectLater(
      cart.addItem(varianteProductoId: 4, cantidad: 1),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          CartService.mensajeCarritoOfflineDeshabilitado,
        ),
      ),
    );
    await expectLater(
      cart.convertirEnPagoDiferido(
        sucursalId: 1,
        direccionEnvio: 'Calle local',
        clienteId: null,
      ),
      throwsA(isA<ApiException>()),
    );
  });

  // [EXAMEN-2] C2.5 P1: validar recusado -> aceptar nuevo total -> convertir.
  test('CU15 validar recusado propone nuevo total y convertir lo consume', () async {
    final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
    await db.abrir(ruta: inMemoryDatabasePath);
    final client = FakeOfflineClient();
    client.responder = (path, data) {
      if (path.contains('/validar')) {
        return <String, dynamic>{
          'estado': 'RECHAZADO',
          'nuevo_total': 45.0,
          'motivo': 'PRECIO_ACTUALIZADO',
        };
      }
      if (path.contains('/convertir')) {
        return <String, dynamic>{'uuid_orden': 'orden-9', 'total': 45.0};
      }
      return <String, dynamic>{};
    };
    final cart = OfflineCartService(
      database: db,
      tenantId: 6,
      dispositivoId: 'device-cart',
      client: client,
    );
    await cart.agregarItem(
      varianteProductoId: 4,
      cantidad: 2,
      precioUnitario: 25,
    );
    final local = await cart.obtenerCarritoLocal();
    expect(local, isNotNull);
    expect(local!.total, 50);
    final uuid = local.uuidCarrito;

    // El servidor recalcula: total local 50 -> nuevo total 45.
    final validacion = await cart.validarContraServidor(uuid);
    expect(validacion['estado'], 'RECHAZADO');
    expect(validacion['nuevo_total'], 45.0);

    // El usuario acepta el nuevo total del servidor (RN-014).
    final aceptado = await cart.aceptarNuevoTotal(uuid, 45.0);
    expect(aceptado, isNotNull);
    expect(aceptado!.total, 45.0);

    final orden = await cart.convertirAOrden(uuid);
    expect(orden['uuid_orden'], 'orden-9');
    expect(
      client.paths.any((p) => p.endsWith('/validar')),
      isTrue,
    );
    expect(
      client.paths.any((p) => p.endsWith('/convertir')),
      isTrue,
    );
    await db.cerrar();
  });
}
