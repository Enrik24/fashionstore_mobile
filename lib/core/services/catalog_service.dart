import '../../config/constants.dart';
import '../models/product_model.dart';
import 'api_service.dart';

class CatalogService {
  final ApiService _apiService;

  CatalogService({required ApiService apiService}) : _apiService = apiService;

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
    try {
      final queryParams = <String, dynamic>{
        'pagina': page,
        'limite': pageSize,
      };

      if (categoriaId != null) queryParams['categoria_id'] = categoriaId;
      if (temporadaId != null) queryParams['temporada_id'] = temporadaId;
      if (tallaId != null) queryParams['talla_id'] = tallaId;
      if (colorId != null) queryParams['color_id'] = colorId;
      if (minPrecio != null) queryParams['precio_min'] = minPrecio;
      if (maxPrecio != null) queryParams['precio_max'] = maxPrecio;
      if (genero != null && genero.isNotEmpty) {
        queryParams['genero'] = genero.toUpperCase();
      }
      if (search != null && search.trim().isNotEmpty) {
        queryParams['q'] = search.trim();
      }
      if (orden != null && orden.isNotEmpty) {
        queryParams['ordenar_por'] = orden;
      }

      final response = await _apiService.dio.get(
        AppConstants.epPublicCatalogo,
        queryParameters: queryParams,
      );

      if (response.data is Map<String, dynamic>) {
        return CatalogoResponse.fromJson(response.data);
      } else if (response.data is List) {
        return CatalogoResponse(
          items: (response.data as List)
              .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
              .toList(),
          total: (response.data as List).length,
          page: page,
          pageSize: pageSize,
          totalPages: 1,
        );
      }
      return CatalogoResponse(items: [], total: 0, page: 1, pageSize: pageSize, totalPages: 1);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<CategoryModel>> getCategorias() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epCategorias);
      if (response.data is List) {
        return (response.data as List)
            .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<TemporadaModel>> getTemporadas() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epTemporadas);
      if (response.data is List) {
        return (response.data as List)
            .map((e) => TemporadaModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<TallaModel>> getTallas() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epTallas);
      if (response.data is List) {
        return (response.data as List)
            .map((e) => TallaModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ColorFilterModel>> getColores() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epColores);
      if (response.data is List) {
        return (response.data as List)
            .map((e) => ColorFilterModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<ProductModel> getProductoDetalle(int id) async {
    try {
      final response = await _apiService.dio.get(
        '${AppConstants.epPublicProductos}/$id',
      );
      return ProductModel.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<ProductModel>> buscarProductos(String query) async {
    try {
      final response = await _apiService.dio.get(
        AppConstants.epPublicBuscar,
        queryParameters: {'q': query},
      );

      if (response.data is List) {
        return (response.data as List)
            .map((item) => ProductModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map && response.data['items'] != null) {
        return (response.data['items'] as List)
            .map((item) => ProductModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<DisponibilidadItem>> getDisponibilidad(
    int productoId, {
    int? varianteId,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (varianteId != null) queryParams['variante_id'] = varianteId;

      final response = await _apiService.dio.get(
        '${AppConstants.epPublicDisponibilidad}/$productoId',
        queryParameters: queryParams,
      );

      if (response.data is List) {
        return (response.data as List)
            .map((item) => DisponibilidadItem.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map && response.data['disponibilidad'] != null) {
        return (response.data['disponibilidad'] as List)
            .map((item) => DisponibilidadItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
