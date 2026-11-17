// [FIX-UI] Regresión de los puntos 6 y 7: cuenta regresiva legible,
// referencias cortas de pedido, tarjetas del carrito rediseñadas y flujo
// de pagos diferidos (lista -> sheet -> reintento) con un servicio en memoria.
import 'dart:async';

import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/models/cart_model.dart';
import 'package:fashionstore_mobile/core/models/phase2_models.dart';
import 'package:fashionstore_mobile/core/providers/pending_payment_provider.dart';
import 'package:fashionstore_mobile/core/services/pending_payment_service.dart';
import 'package:fashionstore_mobile/core/utils/date_format.dart';
import 'package:fashionstore_mobile/core/utils/pago_referencia.dart';
import 'package:fashionstore_mobile/features/cart/widgets/cart_item_card.dart';
import 'package:fashionstore_mobile/features/cart/widgets/cart_summary.dart';
import 'package:fashionstore_mobile/features/cart/widgets/quantity_selector.dart';
import 'package:fashionstore_mobile/features/offline/pending_payments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_offline_client.dart';

/// Servicio de pagos en memoria: la BD real (sqflite ffi) usa isolates que
/// no avanzan dentro de la zona fake-async de `testWidgets`.
class _FakePaymentService extends PendingPaymentService {
  _FakePaymentService()
    : super(
        database: LocalDatabaseService(
          factory: databaseFactoryFfi,
          cifrar: false,
        ),
        tenantId: 1,
        client: FakeOfflineClient(),
      );

  final List<PendingPaymentModel> pagos = [];
  final StreamController<PendingPaymentModel> _eventosFake =
      StreamController<PendingPaymentModel>.broadcast();

  @override
  Stream<PendingPaymentModel> get eventos => _eventosFake.stream;

  @override
  Future<List<PendingPaymentModel>> pendientes() async =>
      pagos.where((p) => p.estaPendiente).toList(growable: false);

  @override
  Future<PendingPaymentModel?> reintentarPago(String uuidPago) async {
    final index = pagos.indexWhere((p) => p.uuidPago == uuidPago);
    if (index < 0) return null;
    final previo = pagos[index];
    final actualizado = PendingPaymentModel(
      uuidPago: previo.uuidPago,
      uuidOrden: previo.uuidOrden,
      monto: previo.monto,
      moneda: previo.moneda,
      estado: 'REQUIERE_ACCION_CLIENTE',
      fechaExpiracion: previo.fechaExpiracion,
      intentos: previo.intentos + 1,
    );
    pagos[index] = actualizado;
    _eventosFake.add(actualizado);
    return actualizado;
  }

  Future<void> cerrar() => _eventosFake.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CountdownFormat (CU16)', () {
    test('23 h 59 min ya no se muestra como 1439:16', () {
      expect(
        CountdownFormat.legible(const Duration(hours: 23, minutes: 59)),
        '23 h 59 min',
      );
    });

    test('más de un día usa días y horas', () {
      expect(
        CountdownFormat.legible(const Duration(hours: 25, minutes: 10)),
        '1 d 1 h',
      );
    });

    test('menos de una hora usa MM:SS', () {
      expect(
        CountdownFormat.legible(const Duration(minutes: 5, seconds: 30)),
        '05:30',
      );
    });

    test('sin vencimiento y vencido', () {
      expect(CountdownFormat.legible(null), 'Sin vencimiento');
      expect(CountdownFormat.legible(Duration.zero), 'Vencido');
      expect(
        CountdownFormat.legible(const Duration(seconds: -10)),
        'Vencido',
      );
    });
  });

  group('referenciaCorta y etiquetaEstadoPago', () {
    test('referencia corta en mayúsculas sin guiones', () {
      expect(
        referenciaCorta('abcd1234-ef56-7890-abcd-ef1234567890'),
        'ABCD1234',
      );
      expect(referenciaCorta(null), '—');
      expect(referenciaCorta(''), '—');
    });

    test('estados en lenguaje natural', () {
      expect(etiquetaEstadoPago('PENDIENTE'), 'Pendiente de envío');
      expect(
        etiquetaEstadoPago('REQUIERE_ACCION_CLIENTE'),
        'Listo para pagar',
      );
      expect(etiquetaEstadoPago('CONFIRMADO'), 'Confirmado');
      expect(etiquetaEstadoPago('EXPIRADO'), 'Expirado');
    });
  });

  group('CartItemCard rediseñada', () {
    CartItemModel item({
      int cantidad = 2,
      int? stock = 5,
    }) => CartItemModel(
      id: 1,
      varianteProductoId: 10,
      cantidad: cantidad,
      precioUnitario: 100,
      subtotal: 100.0 * cantidad,
      productoNombre: 'Chaqueta Denim',
      tallaNombre: 'M',
      colorNombre: 'Azul',
      colorHex: '#1A1A2E',
      stockDisponible: stock,
    );

    testWidgets('nombre, chips, subtotal y acciones de eliminar/cantidad', (
      tester,
    ) async {
      var eliminado = false;
      int? nuevaCantidad;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CartItemCard(
                item: item(),
                onQuantityChanged: (q) => nuevaCantidad = q,
                onDelete: () => eliminado = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Chaqueta Denim'), findsOneWidget);
      expect(find.text('Talla M'), findsOneWidget);
      expect(find.text('Azul'), findsOneWidget);
      expect(find.textContaining('200'), findsWidgets);

      await tester.tap(find.byIcon(Icons.add));
      expect(nuevaCantidad, 3);

      await tester.tap(find.byTooltip('Eliminar del carrito'));
      expect(eliminado, isTrue);
    });

    testWidgets('avisa cuando la cantidad excede el stock conocido (CU11)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CartItemCard(
                item: item(cantidad: 7, stock: 5),
                onQuantityChanged: (_) {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Solo hay 5 disponibles: ajusta la cantidad.'),
        findsOneWidget,
      );
    });
  });

  group('QuantitySelector', () {
    testWidgets('stock desconocido (null) no limita la cantidad (B1.6.c)', (
      tester,
    ) async {
      int? valor;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuantitySelector(
              quantity: 99,
              maxStock: null,
              onChanged: (q) => valor = q,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      expect(valor, 100);
    });

    testWidgets('con stock conocido el más se deshabilita en el máximo', (
      tester,
    ) async {
      int? valor;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuantitySelector(
              quantity: 5,
              maxStock: 5,
              onChanged: (q) => valor = q,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      expect(valor, isNull);
    });
  });

  group('CartSummaryWidget rediseñado', () {
    testWidgets('desglose con descuento, impuestos y nota referencial offline', (
      tester,
    ) async {
      var checkout = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CartSummaryWidget(
              subtotal: 200,
              discount: 20,
              couponCode: 'BIENVENIDA10',
              taxes: 26,
              total: 206,
              esOffline: true,
              onCheckout: () => checkout = true,
            ),
          ),
        ),
      );

      expect(find.text('Descuento'), findsOneWidget);
      expect(find.text('BIENVENIDA10'), findsOneWidget);
      expect(find.text('Impuestos estimados'), findsOneWidget);
      expect(find.textContaining('Total referencial'), findsOneWidget);

      await tester.tap(find.text('Continuar con la compra'));
      expect(checkout, isTrue);
    });

    testWidgets('en línea no muestra nota offline ni impuestos en cero', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CartSummaryWidget(
              subtotal: 200,
              total: 200,
              onCheckout: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Total referencial'), findsNothing);
      expect(find.text('Impuestos'), findsNothing);
      expect(find.text('Calculado al finalizar'), findsOneWidget);
    });
  });

  group('PendingPaymentsPage + DeferredPaymentSheet (CU16)', () {
    late _FakePaymentService service;
    late PendingPaymentProvider provider;

    setUp(() {
      service = _FakePaymentService();
      provider = PendingPaymentProvider(service: service);
    });

    tearDown(() async {
      provider.dispose();
      await service.cerrar();
    });

    Future<void> sembrarPago() async {
      service.pagos.add(
        PendingPaymentModel(
          uuidPago: 'pago-uuid-1234',
          uuidOrden: 'abcd1234-ef56-7890-abcd-ef1234567890',
          monto: 350.5,
          estado: 'PENDIENTE',
          fechaExpiracion: DateTime.now().add(const Duration(hours: 24)),
        ),
      );
      await provider.load();
    }

    // El ticker de 15 s de la página programa frames periódicos: se usan
    // pumps explícitos en lugar de pumpAndSettle.
    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<PendingPaymentProvider>.value(
          value: provider,
          child: const MaterialApp(home: PendingPaymentsPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('estado vacío con mensaje orientativo', (tester) async {
      await provider.load();
      await pumpPage(tester);
      expect(find.text('Sin pagos diferidos'), findsOneWidget);
    });

    testWidgets('lista con referencia corta, monto y contador legible', (
      tester,
    ) async {
      await sembrarPago();
      await pumpPage(tester);

      expect(find.text('Pedido #ABCD1234'), findsOneWidget);
      expect(find.text('Pendiente de envío'), findsOneWidget);
      expect(find.textContaining('350.50 BOB por cobrar'), findsOneWidget);
      expect(find.text('Vence en 23 h 59 min'), findsOneWidget);
      expect(find.textContaining('pago-uuid-1234'), findsNothing);
    });

    testWidgets('al tocar la tarjeta abre el sheet con el pago y se cancela', (
      tester,
    ) async {
      await sembrarPago();
      await pumpPage(tester);

      await tester.tap(find.text('Pedido #ABCD1234'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Pago diferido'), findsOneWidget);
      // El monto aparece en la tarjeta de la lista y en el sheet superpuesto.
      expect(find.text('350.50 BOB'), findsNWidgets(2));
      expect(find.text('Pagar ahora'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Pagar ahora'), findsNothing);
    });

    testWidgets('reintento con conexión marca el pago listo para pagar', (
      tester,
    ) async {
      await sembrarPago();
      await pumpPage(tester);

      await tester.tap(find.byTooltip('Reintentar el pago'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Se solicitó el reintento del pago'), findsOneWidget);
      expect(find.text('Listo para pagar'), findsOneWidget);
    });
  });
}