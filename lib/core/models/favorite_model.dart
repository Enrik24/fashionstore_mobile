import 'product_model.dart';

/// Favorito de un cliente (CU25).
/// Backend: `GET /favoritos/` -> FavoritoResponse
/// {id, cliente_id, producto_id, producto: ProductoResumenResponse,
///  disponible, fecha_agregado}
class FavoriteModel {
  final int id;
  final int clienteId;
  final int productoId;
  final ProductModel producto;
  final bool disponible;
  final DateTime? fechaAgregado;

  FavoriteModel({
    required this.id,
    required this.clienteId,
    required this.productoId,
    required this.producto,
    this.disponible = true,
    this.fechaAgregado,
  });

  static int _parseInt(dynamic raw, [int fallback = 0]) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  factory FavoriteModel.fromJson(Map<String, dynamic> json) {
    ProductModel product;
    final rawProduct = json['producto'];
    if (rawProduct is Map<String, dynamic>) {
      product = ProductModel.fromJson(rawProduct);
    } else {
      product = ProductModel(
        id: _parseInt(json['producto_id']),
        sku: '',
        nombre: json['producto_nombre']?.toString() ?? 'Producto',
        precio: 0.0,
      );
    }

    DateTime? fecha;
    final rawFecha = json['fecha_agregado']?.toString();
    if (rawFecha != null && rawFecha.isNotEmpty) {
      try {
        fecha = DateTime.parse(rawFecha);
      } catch (_) {}
    }

    return FavoriteModel(
      id: _parseInt(json['id']),
      clienteId: _parseInt(json['cliente_id']),
      productoId: _parseInt(json['producto_id'], product.id),
      producto: product,
      disponible: json['disponible'] != false,
      fechaAgregado: fecha,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'producto_id': productoId,
      'disponible': disponible,
      'fecha_agregado': fechaAgregado?.toIso8601String(),
    };
  }
}
