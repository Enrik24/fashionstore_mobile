import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fashionstore_mobile/core/models/api_response.dart';
import 'package:fashionstore_mobile/core/models/favorite_model.dart';
import 'package:fashionstore_mobile/core/models/product_model.dart';
import 'package:fashionstore_mobile/core/providers/favorites_provider.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/favorites_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';

/// Doble de prueba de [FavoritesService] sin red.
class FakeFavoritesService extends FavoritesService {
  FakeFavoritesService({required super.apiService});

  Set<int> ids = {};
  bool failNext = false;

  @override
  Future<Set<int>> getFavoritoIds() async => Set.of(ids);

  @override
  Future<FavoriteModel> agregar(int productoId) async {
    if (failNext) {
      failNext = false;
      throw ApiException(message: 'Error de red');
    }
    ids.add(productoId);
    return FavoriteModel(
      id: ids.length,
      clienteId: 1,
      productoId: productoId,
      producto: ProductModel(
          id: productoId,
          sku: 'TST',
          nombre: 'Producto $productoId',
          precio: 100.0),
    );
  }

  @override
  Future<void> quitar(int productoId) async {
    if (failNext) {
      failNext = false;
      throw ApiException(message: 'Error de red');
    }
    ids.remove(productoId);
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

  group('FavoritesProvider lógica (CU25)', () {
    late FakeFavoritesService fake;
    late FavoritesProvider provider;

    setUp(() async {
      final api = await _buildApiService();
      fake = FakeFavoritesService(apiService: api);
      provider = FavoritesProvider(favoritesService: fake);
    });

    test('loadIds carga el set inicial', () async {
      fake.ids = {1, 2, 3};
      await provider.loadIds();
      expect(provider.favoriteIds, {1, 2, 3});
      expect(provider.isFavorite(2), isTrue);
      expect(provider.isFavorite(99), isFalse);
    });

    test('toggle agrega con actualización optimista', () async {
      final added = await provider.toggle(10);
      expect(added, isTrue);
      expect(provider.isFavorite(10), isTrue);
      expect(provider.favorites.any((f) => f.productoId == 10), isTrue);
    });

    test('toggle quita un favorito existente', () async {
      fake.ids = {10};
      await provider.loadIds();
      final added = await provider.toggle(10);
      expect(added, isFalse);
      expect(provider.isFavorite(10), isFalse);
    });

    test('toggle hace rollback si el backend falla', () async {
      fake.failNext = true;
      final added = await provider.toggle(20);
      // El estado final debe ser el previo (no favorito).
      expect(added, isFalse);
      expect(provider.isFavorite(20), isFalse);
      expect(provider.errorMessage, isNotNull);
    });

    test('clearState limpia todo', () async {
      fake.ids = {1, 2};
      await provider.loadIds();
      provider.clearState();
      expect(provider.favoriteIds, isEmpty);
      expect(provider.favorites, isEmpty);
    });
  });
}
