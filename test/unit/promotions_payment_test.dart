import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fashionstore_mobile/core/models/payment_transaction_model.dart';
import 'package:fashionstore_mobile/core/models/promotion_model.dart';
import 'package:fashionstore_mobile/core/providers/promotions_provider.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/promotion_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';

class FakePromotionService extends PromotionService {
  FakePromotionService({required super.apiService});

  List<PromotionModel> stub = [];
  bool fail = false;

  @override
  Future<List<PromotionModel>> getPromocionesActivas() async {
    if (fail) throw Exception('Sin conexión');
    return stub;
  }
}

Future<ApiService> _buildApiService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(
    secureStorage: const FlutterSecureStorage(),
    prefs: prefs,
  );
  return ApiService(storageService: storage);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PromotionModel (endpoint /public/promociones/activas)', () {
    test('fromJson con aplicabilidad por producto y categoría', () {
      final json = {
        'id': 1,
        'nombre': 'Promo Verano',
        'tipo': 'PORCENTAJE',
        'valor': '20.00',
        'fecha_fin': '2026-12-31T23:59:59Z',
        'producto_ids': [10, 20],
        'categoria_ids': [5],
      };

      final promo = PromotionModel.fromJson(json);
      expect(promo.isPorcentaje, isTrue);
      expect(promo.is2x1, isFalse);
      expect(promo.valor, 20.0);
      expect(promo.productoIds, [10, 20]);
      expect(promo.categoriaIds, [5]);
    });

    test('detecta DOS_POR_UNO sin valor', () {
      final json = {
        'id': 2,
        'tipo': 'DOS_POR_UNO',
        'valor': null,
        'producto_ids': [7],
        'categoria_ids': [],
      };

      final promo = PromotionModel.fromJson(json);
      expect(promo.is2x1, isTrue);
      expect(promo.isPorcentaje, isFalse);
    });
  });

  group('PromotionsProvider (badges espejo de la web)', () {
    late FakePromotionService fake;
    late PromotionsProvider provider;

    setUp(() async {
      final api = await _buildApiService();
      fake = FakePromotionService(apiService: api);
      provider = PromotionsProvider(promotionService: fake);
    });

    test('mayor porcentaje aplicable gana (producto y categoría)', () async {
      fake.stub = [
        PromotionModel(
            tipo: 'PORCENTAJE',
            valor: 10,
            productoIds: [1],
            categoriaIds: []),
        PromotionModel(
            tipo: 'PORCENTAJE',
            valor: 25,
            productoIds: [],
            categoriaIds: [5]),
        PromotionModel(
            tipo: 'MONTO_FIJO', valor: 50, productoIds: [1]),
      ];
      await provider.load();

      // Producto 1 por categoría 5: 25% > 10%.
      expect(provider.getDiscountForProduct(1, 5), 25.0);
      // Producto 1 sin categoría: solo 10% directo.
      expect(provider.getDiscountForProduct(1, 9), 10.0);
      // Producto 2 sin relación: sin descuento.
      expect(provider.getDiscountForProduct(2, 9), isNull);
      expect(provider.precioConDescuento(1, 5, 200.0), 150.0);
    });

    test('has2x1 por producto o categoría', () async {
      fake.stub = [
        PromotionModel(
            tipo: 'DOS_POR_UNO', productoIds: [3], categoriaIds: [8]),
      ];
      await provider.load();

      expect(provider.has2x1(3, null), isTrue);
      expect(provider.has2x1(99, 8), isTrue);
      expect(provider.has2x1(99, 7), isFalse);
    });

    test('si falla la carga queda vacío sin romper', () async {
      fake.fail = true;
      await provider.load();

      expect(provider.isLoaded, isTrue);
      expect(provider.hasPromotions, isFalse);
      expect(provider.getDiscountForProduct(1, 1), isNull);
    });

    test('load una sola vez', () async {
      fake.stub = [
        PromotionModel(tipo: 'PORCENTAJE', valor: 5, productoIds: [1])
      ];
      await provider.load();
      fake.stub = [];
      await provider.load();

      expect(provider.getDiscountForProduct(1, null), 5.0);
    });
  });

  group('PaymentTransactionModel (CU18)', () {
    test('fromJson con TransaccionPagoResponse', () {
      final json = {
        'id': 3,
        'orden_id': 55,
        'monto': '349.99',
        'metodo_pago': 'STRIPE',
        'estado': 'PENDIENTE',
        'referencia_externa': 'cs_test_123',
        'fecha': '2026-09-21T10:00:00Z',
      };

      final tx = PaymentTransactionModel.fromJson(json);
      expect(tx.ordenId, 55);
      expect(tx.monto, 349.99);
      expect(tx.isPending, isTrue);
      expect(tx.isConfirmed, isFalse);
      expect(tx.fecha, isNotNull);
    });

    test('estados confirmado / rechazado / reembolsado', () {
      PaymentTransactionModel base(String estado) =>
          PaymentTransactionModel(
            id: 1,
            ordenId: 1,
            monto: 10,
            metodoPago: 'PAYPAL',
            estado: estado,
          );

      expect(base('CONFIRMADO').isConfirmed, isTrue);
      expect(base('RECHAZADO').isRejected, isTrue);
      expect(base('REEMBOLSADO').isRefunded, isTrue);
      expect(base('EN_PROCESO').isPending, isFalse);
    });
  });
}
