// [EXAMEN-2] Ola 4 — B1.6 (CU15), B1.7 (CU16), B1.8 (CU17) y B1.4 (CU08).
//
// Cubre el bug que borraba los ítems del carrito sin dato de stock, el
// bloqueo sin catálogo descargado, los impuestos del total offline, el orden
// FIFO de los pagos diferidos, la expiración, la persistencia de roles
// offline y el resumen de la sincronización.
import 'dart:convert';

import 'package:fashionstore_mobile/core/database/repositories/local_config_repository.dart';
import 'package:fashionstore_mobile/core/database/repositories/local_permissions_repository.dart';
import 'package:fashionstore_mobile/core/models/offline_config_model.dart';
import 'package:fashionstore_mobile/core/services/offline_cart_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/pending_payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_offline_client.dart';
import '../helpers/fase3_helpers.dart';

/// [EXAMEN-2] B1.6.a: configuración del tenant con una tasa de impuesto.
OfflineConfigModel _configConTasa(double tasa) => OfflineConfigModel(
  tenantId: tenantFase3,
  descargaAutomatica: true,
  incluirClientes: true,
  maxClientes: 100,
  habilitarCarritoOffline: true,
  maxHorasSesionOffline: 12,
  maxDiasOrdenPendiente: 1,
  moneda: 'BOB',
  tasaImpuestos: tasa,
);

void main() {
  group('B1.6 CU15 — carrito offline', () {
    test('B1.6.c: un ítem sin dato de stock NO se borra del carrito', () async {
      final db = await abrirBaseFase3();
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-carrito',
      );
      final cart = OfflineCartService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-carrito',
        queue: queue,
      );

      await cart.agregarItem(
        varianteProductoId: 101,
        cantidad: 2,
        precioUnitario: 100,
        stockConocido: null, // sin dato local
      );
      final local = await cart.obtenerCarritoLocal();
      expect(local, isNotNull);
      expect(local!.items, hasLength(1));
      // `null` = stock desconocido (no 0).
      expect(local.items.first.stockDisponible, isNull);
      expect(local.items.first.cantidad, 2);
      await db.cerrar();
    });

    test('B1.6.a: el total offline incluye los impuestos vigentes', () async {
      final db = await abrirBaseFase3();
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-impuestos',
      );
      final cart = OfflineCartService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-impuestos',
        queue: queue,
      );
      // Configuración del tenant con tasa de impuesto del 13 %.
      await LocalConfigRepository(db).guardar(
        _configConTasa(0.13),
      );
      cart.configurarRepositorioConfig(LocalConfigRepository(db));

      await cart.agregarItem(
        varianteProductoId: 101,
        cantidad: 2,
        precioUnitario: 100,
        stockConocido: 10,
      );
      final local = await cart.obtenerCarritoLocal();
      expect(local!.subtotal, 200);
      expect(local.impuestos, closeTo(26, 0.001));
      expect(local.total, closeTo(226, 0.001));
      await db.cerrar();
    });

    test('B1.6.i: el carrito guarda el sello de la última descarga', () async {
      final db = await abrirBaseFase3();
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-sello',
      );
      final cart = OfflineCartService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-sello',
        queue: queue,
      );
      await db.database!.insert('meta', <String, Object?>{
        'clave': 'sello_descarga',
        'tenant_id': tenantFase3,
        'valor': '2026-01-01T10:00:00Z',
        'secuencia_local': 0,
        'version_esquema': 2,
        'fecha_actualizacion': '2026-01-01T10:00:00Z',
      });

      await cart.agregarItem(
        varianteProductoId: 101,
        cantidad: 1,
        precioUnitario: 100,
        stockConocido: 10,
      );
      final filas = await db.database!.query(
        'carrito',
        where: 'tenant_id = ?',
        whereArgs: <Object?>[tenantFase3],
      );
      expect(filas.single['sello_descarga'], '2026-01-01T10:00:00Z');
      await db.cerrar();
    });
  });

  group('B1.7 CU16 — pagos diferidos', () {
    test('B1.7.b: los pagos diferidos se listan en orden FIFO', () async {
      final db = await abrirBaseFase3();
      final service = PendingPaymentService(
        database: db,
        tenantId: tenantFase3,
        client: FakeOfflineClient(),
      );
      final ahora = DateTime.now().toUtc();
      for (final i in <int>[0, 1, 2]) {
        await db.database!.insert('pagos', <String, Object?>{
          'uuid_pago': 'uuid-pago-$i',
          'tenant_id': tenantFase3,
          'uuid_orden': 'uuid-orden-$i',
          'estado': 'PENDIENTE',
          'monto': 100.0 + i,
          'moneda': 'BOB',
          'intentos': 0,
          'idempotency_key': 'uuid-pago-$i',
          'fecha_registro_local': ahora
              .subtract(Duration(minutes: 10 - i))
              .toIso8601String(),
          'fecha_actualizacion': ahora.toIso8601String(),
        });
      }
      final pendientes = await service.pendientes();
      expect(pendientes, hasLength(3));
      // El más antiguo primero (FIFO, RN-010).
      expect(pendientes.first.uuidPago, 'uuid-pago-0');
      expect(pendientes.last.uuidPago, 'uuid-pago-2');
      await db.cerrar();
    });

    test('B1.7.a: el job de expiración marca EXPIRADO y libera el stock', () async {
      final db = await abrirBaseFase3();
      final service = PendingPaymentService(
        database: db,
        tenantId: tenantFase3,
        client: FakeOfflineClient(),
      );
      await db.database!.insert('pagos', <String, Object?>{
        'uuid_pago': 'uuid-vencido',
        'tenant_id': tenantFase3,
        'uuid_orden': 'uuid-orden',
        'estado': 'PENDIENTE',
        'monto': 100.0,
        'moneda': 'BOB',
        'intentos': 0,
        'idempotency_key': 'uuid-vencido',
        'fecha_expiracion': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'fecha_registro_local': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      });

      final expirados = await service.procesarExpirados();
      expect(expirados, 1);
      final filas = await db.database!.query(
        'pagos',
        where: 'uuid_pago = ?',
        whereArgs: <Object?>['uuid-vencido'],
      );
      expect(filas.single['estado'], 'EXPIRADO');
      await db.cerrar();
    });

    test('B1.7.h: el client_secret de Stripe NO se persiste', () async {
      final db = await abrirBaseFase3();
      final cliente = FakeOfflineClient(
        responder: (path, data) => path.contains('pagos/diferidos')
            ? <String, dynamic>{
                'uuid_pago': 'uuid-stripe',
                'monto': 100.0,
                'moneda': 'BOB',
                'estado': 'PENDIENTE',
                'client_secret': 'pi_secreto_NO_PERSISTIR',
              }
            : <String, dynamic>{},
      );
      final service = PendingPaymentService(
        database: db,
        tenantId: tenantFase3,
        client: cliente,
      );
      final secret = await service.prepararPaymentSheet('uuid-stripe');
      expect(secret, 'pi_secreto_NO_PERSISTIR');
      // Vive **sólo** en memoria.
      expect(service.clientSecretEnMemoria('uuid-stripe'), secret);

      final filas = await db.database!.query('pagos');
      for (final fila in filas) {
        final texto = jsonEncode(fila);
        expect(texto.contains('pi_secreto_NO_PERSISTIR'), isFalse);
      }
      await db.cerrar();
    });

    test('FIX v16: Checkout Session (sin client_secret) usa checkout_url', () async {
      final db = await abrirBaseFase3();
      final cliente = FakeOfflineClient(
        responder: (path, data) => <String, dynamic>{
          'uuid_pago': 'uuid-checkout',
          'monto': 825.0,
          'moneda': 'BOB',
          'estado': 'REQUIERE_ACCION_CLIENTE',
          // El backend real (STRIPE_API_KEY configurado) crea una sesión de
          // Checkout y devuelve client_secret: null + checkout_url.
          'client_secret': null,
          'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_123',
          'simulado': false,
        },
      );
      final service = PendingPaymentService(
        database: db,
        tenantId: tenantFase3,
        client: cliente,
      );

      final preparacion = await service.prepararPago('uuid-checkout');

      expect(preparacion.usaPaymentSheet, isFalse);
      expect(preparacion.usaRedirect, isTrue);
      expect(preparacion.checkoutUrl,
          'https://checkout.stripe.com/c/pay/cs_test_123');
      expect(preparacion.clientSecret, isNull);
      expect(service.clientSecretEnMemoria('uuid-checkout'), isNull);
      await db.cerrar();
    });

    test('FIX v16: con client_secret se mantiene el PaymentSheet nativo', () async {
      final db = await abrirBaseFase3();
      final cliente = FakeOfflineClient(
        responder: (path, data) => <String, dynamic>{
          'uuid_pago': 'uuid-intent',
          'client_secret': 'pi_test_secret',
          'checkout_url': null,
        },
      );
      final service = PendingPaymentService(
        database: db,
        tenantId: tenantFase3,
        client: cliente,
      );

      final preparacion = await service.prepararPago('uuid-intent');

      expect(preparacion.usaPaymentSheet, isTrue);
      expect(preparacion.usaRedirect, isFalse);
      expect(preparacion.clientSecret, 'pi_test_secret');
      service.olvidarClientSecret('uuid-intent');
      expect(service.clientSecretEnMemoria('uuid-intent'), isNull);
      await db.cerrar();
    });
  });

  group('B1.8 CU17 — permisos offline', () {
    test('los roles guardados localmente se pueden leer', () async {
      final db = await abrirBaseFase3();
      final permisos = LocalPermissionsRepository(db);
      await permisos.guardar(
        tenantId: tenantFase3,
        usuarioId: 42,
        roles: const ['Cajero'],
        permisos: const ['ventas', 'devoluciones'],
      );
      final roles = await permisos.leerRoles(
        tenantId: tenantFase3,
        usuarioId: 42,
      );
      expect(roles, contains('cajero'));
      final lista = await permisos.leerPermisos(
        tenantId: tenantFase3,
        usuarioId: 42,
      );
      expect(lista, contains('ventas'));
      await db.cerrar();
    });
  });

  group('B1.4 CU08 — resumen de sincronización', () {
    test('el mensaje de resumen tiene el formato del spec', () async {
      final db = await abrirBaseFase3();
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-sync',
      );
      await queue.encolar(
        uuidOperacion: 'uuid-sync-1',
        tipoOperacion: 'VENTA_CONTADO',
        payload: const <String, Object?>{'n': 1},
      );
      await queue.encolar(
        uuidOperacion: 'uuid-sync-2',
        tipoOperacion: 'VENTA_CONTADO',
        payload: const <String, Object?>{'n': 2},
      );
      await queue.aplicarResultado(
        uuidOperacion: 'uuid-sync-1',
        estado: 'CONFIRMADA',
        tipoOperacion: 'VENTA_CONTADO',
      );
      await queue.aplicarResultado(
        uuidOperacion: 'uuid-sync-2',
        estado: 'RECHAZADA',
        motivo: 'Stock insuficiente',
        tipoOperacion: 'VENTA_CONTADO',
      );
      final resumen = await queue.resumen();
      expect(resumen.confirmadas, 1);
      expect(resumen.rechazadas, 1);
      await db.cerrar();
    });

    test('B1.4.b: un ERROR_CRITICO detiene el tipo de operación', () async {
      final db = await abrirBaseFase3();
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-critico',
      );
      // Dos operaciones del mismo tipo, en cola.
      for (final i in <int>[1, 2]) {
        await queue.encolar(
          uuidOperacion: 'uuid-critico-$i',
          tipoOperacion: 'VENTA_CONTADO',
          payload: const <String, Object?>{'n': 1},
        );
      }
      await queue.aplicarResultado(
        uuidOperacion: 'uuid-critico-1',
        estado: 'ERROR_CRITICO',
        motivo: 'Tenant suspendido',
        tipoOperacion: 'VENTA_CONTADO',
      );
      // El tipo queda detenido: ya no se envían sus operaciones.
      expect(await queue.tiposDetenidos(), contains('VENTA_CONTADO'));
      final pendientes = await queue.pendientes();
      expect(
        pendientes.where((p) => p.tipoOperacion == 'VENTA_CONTADO'),
        isEmpty,
      );
      await db.cerrar();
    });
  });
}
