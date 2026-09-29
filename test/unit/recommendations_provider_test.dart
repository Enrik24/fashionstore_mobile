import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fashionstore_mobile/core/models/ai_model.dart';
import 'package:fashionstore_mobile/core/models/product_model.dart';
import 'package:fashionstore_mobile/core/providers/recommendations_provider.dart';
import 'package:fashionstore_mobile/core/services/ai_service.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/catalog_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';

ProductModel _product(int id, String genero) => ProductModel(
      id: id,
      sku: 'SKU-$id',
      nombre: 'Prenda $id',
      precio: 100.0,
      genero: genero,
    );

class FakeAiService extends AiService {
  FakeAiService({required super.apiService});

  RecomendacionResponse? stub;
  bool fail = false;

  @override
  Future<RecomendacionResponse> getRecomendaciones({
    int? clienteId,
    String? preferencias,
    int limite = 5,
  }) async {
    if (fail) throw Exception('IA no disponible');
    return stub ??
        RecomendacionResponse(
          mensajePersonalizado: '',
          recomendaciones: [],
        );
  }
}

class FakeCatalogService extends CatalogService {
  FakeCatalogService({required super.apiService});

  List<ProductModel> catalogItems = [];
  Map<int, ProductModel> details = {};

  @override
  Future<CatalogoResponse> getCatalogo({
    int page = 1,
    int pageSize = 20,
    int? categoriaId,
    int? temporadaId,
    int? tallaId,
    int? colorId,
    double? minPrecio,
    double? maxPrecio,
    String? search,
    String? orden,
    String? genero,
  }) async {
    return CatalogoResponse(
      items: catalogItems,
      total: catalogItems.length,
      page: 1,
      pageSize: pageSize,
      totalPages: 1,
    );
  }

  @override
  Future<ProductModel> getProductoDetalle(int id) async {
    final p = details[id];
    if (p == null) throw Exception('No encontrado');
    return p;
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

  group('RecommendationsProvider (sección home)', () {
    late FakeAiService fakeAi;
    late FakeCatalogService fakeCatalog;
    late RecommendationsProvider provider;

    setUp(() async {
      final api = await _buildApiService();
      fakeAi = FakeAiService(apiService: api);
      fakeCatalog = FakeCatalogService(apiService: api);
      provider = RecommendationsProvider(
        aiService: fakeAi,
        catalogService: fakeCatalog,
      );
    });

    test('con sesión: hidrata recomendaciones personalizadas', () async {
      fakeAi.stub = RecomendacionResponse(
        estiloDetectado: 'Casual',
        mensajePersonalizado: 'Para ti',
        recomendaciones: [
          RecomendacionItem(
              productoId: 1, nombre: 'P1', razon: 'R1'),
          RecomendacionItem(
              productoId: 2, nombre: 'P2', razon: 'R2'),
        ],
      );
      fakeCatalog.details = {1: _product(1, 'HOMBRE'), 2: _product(2, 'MUJER')};

      await provider.load(isAuthenticated: true);

      expect(provider.products, hasLength(2));
      expect(provider.isPersonalized, isTrue);
      expect(provider.badge, contains('Casual'));
      expect(provider.message, 'Para ti');
    });

    test('sin sesión: fallback balanceado por género', () async {
      fakeCatalog.catalogItems = [
        _product(1, 'HOMBRE'),
        _product(2, 'HOMBRE'),
        _product(3, 'HOMBRE'),
        _product(4, 'HOMBRE'),
        _product(5, 'MUJER'),
        _product(6, 'UNISEX'),
        _product(7, 'MUJER'),
      ];

      await provider.load(isAuthenticated: false);

      expect(provider.isPersonalized, isFalse);
      expect(provider.badge, contains('Novedades'));
      // Mitad hombres (3 de 6) + resto hasta el límite.
      expect(provider.products, hasLength(6));
      expect(
        provider.products.take(3).every((p) => p.genero == 'HOMBRE'),
        isTrue,
      );
    });

    test('si la IA falla: usa fallback público', () async {
      fakeAi.fail = true;
      fakeCatalog.catalogItems = [_product(9, 'MUJER')];

      await provider.load(isAuthenticated: true);

      expect(provider.products, hasLength(1));
      expect(provider.isPersonalized, isFalse);
    });

    test('si la IA devuelve vacío: usa fallback público', () async {
      fakeAi.stub = RecomendacionResponse(
        mensajePersonalizado: '',
        recomendaciones: [],
      );
      fakeCatalog.catalogItems = [_product(9, 'UNISEX')];

      await provider.load(isAuthenticated: true);

      expect(provider.products, hasLength(1));
      expect(provider.isPersonalized, isFalse);
    });
  });
}
