class ProductModel {
  final int id;
  final String sku;
  final String nombre;
  final String? descripcion;
  final double precio;
  final double? precioOferta;
  final List<String> imagenes;
  final String estado;
  final int? categoriaId;
  final String? categoriaNombre;
  final int? temporadaId;
  final String? temporadaNombre;
  final List<VarianteProducto> variantes;
  final double rating;
  final int totalReviews;
  final bool destacado;
  final String? genero;

  ProductModel({
    required this.id,
    required this.sku,
    required this.nombre,
    this.descripcion,
    required this.precio,
    this.precioOferta,
    this.imagenes = const [],
    this.estado = 'ACTIVO',
    this.categoriaId,
    this.categoriaNombre,
    this.temporadaId,
    this.temporadaNombre,
    this.variantes = const [],
    this.rating = 0.0,
    this.totalReviews = 0,
    this.destacado = false,
    this.genero,
  });

  String get primaryImage {
    if (imagenes.isNotEmpty && imagenes.first.isNotEmpty) {
      return imagenes.first;
    }
    return 'https://images.unsplash.com/photo-1523381210434-271e8be1f52b?auto=format&fit=crop&q=80&w=600';
  }

  bool get hasDiscount => precioOferta != null && precioOferta! < precio;

  double get displayPrice => precioOferta ?? precio;

  int get totalStock =>
      variantes.fold(0, (sum, item) => sum + item.stockTotal);

  bool get inStock => estado == 'ACTIVO' || (totalStock > 0 && estado != 'AGOTADO');

  bool get isAgotado => estado == 'AGOTADO';

  bool get isProximoIngreso => estado == 'PROXIMO_INGRESO';

  /// true cuando el backend ya envió valoraciones reales (CU26).
  bool get hasRatings => totalReviews > 0;

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    List<String> parseImagenes(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      if (raw is String) {
        if (raw.startsWith('[') && raw.endsWith(']')) {
          // simple array parsing
          final cleaned = raw.substring(1, raw.length - 1);
          return cleaned
              .split(',')
              .map((e) => e.replaceAll('"', '').replaceAll("'", "").trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        return [raw];
      }
      return [];
    }

    var variantesList = <VarianteProducto>[];
    if (json['variantes'] != null && json['variantes'] is List) {
      variantesList = (json['variantes'] as List)
          .map((v) => VarianteProducto.fromJson(v as Map<String, dynamic>))
          .toList();
    }

    return ProductModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      sku: json['sku']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? 'Producto',
      descripcion: json['descripcion']?.toString(),
      precio: (json['precio'] is num)
          ? (json['precio'] as num).toDouble()
          : double.tryParse(json['precio']?.toString() ?? '0') ?? 0.0,
      precioOferta: json['precio_oferta'] != null
          ? ((json['precio_oferta'] is num)
              ? (json['precio_oferta'] as num).toDouble()
              : double.tryParse(json['precio_oferta'].toString()))
          : null,
      imagenes: parseImagenes(json['imagenes']),
      estado: json['estado']?.toString() ?? 'ACTIVO',
      categoriaId: json['categoria_id'] is int
          ? json['categoria_id']
          : int.tryParse(json['categoria_id']?.toString() ?? ''),
      categoriaNombre: json['categoria'] is Map
          ? json['categoria']['nombre']?.toString()
          : json['categoria_nombre']?.toString(),
      temporadaId: json['temporada_id'] is int
          ? json['temporada_id']
          : int.tryParse(json['temporada_id']?.toString() ?? ''),
      temporadaNombre: json['temporada'] is Map
          ? json['temporada']['nombre']?.toString()
          : json['temporada_nombre']?.toString(),
      variantes: variantesList,
      // CU26: el backend envía promedio/total reales; 0.0 = "Sin valoraciones".
      rating: (json['promedio_valoracion'] ?? json['rating']) != null
          ? (((json['promedio_valoracion'] ?? json['rating']) is num)
              ? ((json['promedio_valoracion'] ?? json['rating']) as num).toDouble()
              : double.tryParse(
                      (json['promedio_valoracion'] ?? json['rating']).toString()) ??
                  0.0)
          : 0.0,
      totalReviews: (json['total_valoraciones'] ?? json['total_reviews']) != null
          ? int.tryParse(
                  (json['total_valoraciones'] ?? json['total_reviews']).toString()) ??
              0
          : 0,
      destacado: json['destacado'] == true,
      genero: json['genero']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sku': sku,
      'nombre': nombre,
      'descripcion': descripcion,
      'precio': precio,
      'precio_oferta': precioOferta,
      'imagenes': imagenes,
      'estado': estado,
      'categoria_id': categoriaId,
      'categoria_nombre': categoriaNombre,
      'temporada_id': temporadaId,
      'temporada_nombre': temporadaNombre,
      'variantes': variantes.map((v) => v.toJson()).toList(),
      'rating': rating,
      'total_reviews': totalReviews,
      'destacado': destacado,
      'genero': genero,
    };
  }
}

class VarianteProducto {
  final int id;
  final int productoId;
  final int? tallaId;
  final String? tallaNombre;
  final int? colorId;
  final String? colorNombre;
  final String? colorHex;
  final String? skuVariante;
  final double? precioVariante;
  final int stockTotal;
  final bool activo;

  VarianteProducto({
    required this.id,
    required this.productoId,
    this.tallaId,
    this.tallaNombre,
    this.colorId,
    this.colorNombre,
    this.colorHex,
    this.skuVariante,
    this.precioVariante,
    this.stockTotal = 0,
    this.activo = true,
  });

  factory VarianteProducto.fromJson(Map<String, dynamic> json) {
    return VarianteProducto(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      productoId: json['producto_id'] is int
          ? json['producto_id']
          : int.tryParse(json['producto_id']?.toString() ?? '0') ?? 0,
      tallaId: json['talla_id'] is int
          ? json['talla_id']
          : int.tryParse(json['talla_id']?.toString() ?? ''),
      tallaNombre: json['talla'] is Map
          ? (json['talla']['valor']?.toString() ?? json['talla']['nombre']?.toString())
          : json['talla_nombre']?.toString() ?? json['talla']?.toString(),
      colorId: json['color_id'] is int
          ? json['color_id']
          : int.tryParse(json['color_id']?.toString() ?? ''),
      colorNombre: json['color'] is Map
          ? json['color']['nombre']?.toString()
          : json['color_nombre']?.toString() ?? json['color']?.toString(),
      colorHex: json['color'] is Map
          ? json['color']['codigo_hex']?.toString()
          : json['color_hex']?.toString(),
      skuVariante: json['sku_variante']?.toString(),
      precioVariante: json['precio_variante'] != null
          ? ((json['precio_variante'] is num)
              ? (json['precio_variante'] as num).toDouble()
              : double.tryParse(json['precio_variante'].toString()))
          : null,
      stockTotal: json['stock_total'] is int
          ? json['stock_total']
          : (json['stock'] is int ? json['stock'] : int.tryParse(json['stock_total']?.toString() ?? json['stock']?.toString() ?? '0') ?? 0),
      activo: json['activo'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'producto_id': productoId,
      'talla_id': tallaId,
      'talla_nombre': tallaNombre,
      'color_id': colorId,
      'color_nombre': colorNombre,
      'color_hex': colorHex,
      'sku_variante': skuVariante,
      'precio_variante': precioVariante,
      'stock_total': stockTotal,
      'activo': activo,
    };
  }
}

class CatalogoResponse {
  final List<ProductModel> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  CatalogoResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory CatalogoResponse.fromJson(Map<String, dynamic> json) {
    var rawItems = json['items'] ?? json['data'] ?? json['productos'] ?? [];
    List<ProductModel> list = [];
    if (rawItems is List) {
      list = rawItems
          .map((item) => ProductModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    final totalCount = json['total'] is int
        ? json['total']
        : int.tryParse(json['total']?.toString() ?? '') ?? list.length;
    // El backend envía `limite`/`pagina`/`total_paginas` (snake_case ES).
    final pSize = json['page_size'] is int
        ? json['page_size']
        : (json['limite'] is int
            ? json['limite']
            : (json['limit'] is int ? json['limit'] : 20));
    final curPage = json['page'] is int
        ? json['page']
        : (json['pagina'] is int
            ? json['pagina']
            : int.tryParse(
                    json['pagina']?.toString() ?? '') ??
                1);

    final totalPgs = json['total_pages'] is int
        ? json['total_pages']
        : (json['total_paginas'] is int
            ? json['total_paginas']
            : (totalCount > 0 ? (totalCount / pSize).ceil() : 1));

    return CatalogoResponse(
      items: list,
      total: totalCount,
      page: curPage,
      pageSize: pSize,
      totalPages: totalPgs,
    );
  }
}

class DisponibilidadItem {
  final int sucursalId;
  final String sucursalNombre;
  final String? direccion;
  final String? telefono;
  final double? latitud;
  final double? longitud;
  final int? varianteId;
  final String? talla;
  final String? color;
  final int stock;
  final int cantidadReservada;
  final int cantidadVendida;
  final String estado;
  final bool disponible;

  DisponibilidadItem({
    required this.sucursalId,
    required this.sucursalNombre,
    this.direccion,
    this.telefono,
    this.latitud,
    this.longitud,
    this.varianteId,
    this.talla,
    this.color,
    required this.stock,
    this.cantidadReservada = 0,
    this.cantidadVendida = 0,
    this.estado = 'DISPONIBLE',
    required this.disponible,
  });

  factory DisponibilidadItem.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic v) {
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '0') ?? 0;
    }
    return DisponibilidadItem(
      sucursalId: json['sucursal_id'] is int
          ? json['sucursal_id']
          : int.tryParse(json['sucursal_id']?.toString() ?? '0') ?? 0,
      sucursalNombre: json['sucursal_nombre']?.toString() ??
          json['sucursal']?['nombre']?.toString() ??
          'Sucursal',
      direccion: json['direccion']?.toString() ??
          json['sucursal']?['direccion']?.toString(),
      telefono: json['telefono']?.toString() ??
          json['sucursal']?['telefono']?.toString(),
      latitud: json['latitud'] != null
          ? ((json['latitud'] is num)
              ? (json['latitud'] as num).toDouble()
              : double.tryParse(json['latitud'].toString()))
          : (json['sucursal']?['latitud'] != null
              ? double.tryParse(json['sucursal']['latitud'].toString())
              : null),
      longitud: json['longitud'] != null
          ? ((json['longitud'] is num)
              ? (json['longitud'] as num).toDouble()
              : double.tryParse(json['longitud'].toString()))
          : (json['sucursal']?['longitud'] != null
              ? double.tryParse(json['sucursal']['longitud'].toString())
              : null),
      varianteId: json['variante_id'] is int
          ? json['variante_id']
          : int.tryParse(json['variante_id']?.toString() ?? ''),
      talla: json['talla']?.toString(),
      color: json['color']?.toString(),
      stock: (json['cantidad_disponible'] is int)
          ? json['cantidad_disponible']
          : (json['stock'] is int
              ? json['stock']
              : int.tryParse(json['cantidad_disponible']?.toString() ??
                      json['stock']?.toString() ??
                      '0') ??
                  0),
      cantidadReservada: _toInt(json['cantidad_reservada']),
      cantidadVendida: _toInt(json['cantidad_vendida']),
      estado: json['estado']?.toString() ?? 'DISPONIBLE',
      disponible: json['estado'] == 'DISPONIBLE' ||
          json['disponible'] == true ||
          ((json['cantidad_disponible'] is num &&
                  (json['cantidad_disponible'] as num) > 0) ||
              (json['stock'] is num && (json['stock'] as num) > 0)),
    );
  }
}

class CategoryModel {
  final int id;
  final String nombre;
  final String? descripcion;
  final String? imagen;

  CategoryModel({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.imagen,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      nombre: json['nombre']?.toString() ?? '',
      descripcion: json['descripcion']?.toString(),
      imagen: json['imagen']?.toString(),
    );
  }
}

class TemporadaModel {
  final int id;
  final String nombre;
  final String? descripcion;

  TemporadaModel({
    required this.id,
    required this.nombre,
    this.descripcion,
  });

  factory TemporadaModel.fromJson(Map<String, dynamic> json) {
    return TemporadaModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      nombre: json['nombre']?.toString() ?? '',
      descripcion: json['descripcion']?.toString(),
    );
  }
}

class TallaModel {
  final int id;
  final String valor;
  final String? tipo;
  final String? descripcion;

  TallaModel({
    required this.id,
    required this.valor,
    this.tipo,
    this.descripcion,
  });

  factory TallaModel.fromJson(Map<String, dynamic> json) {
    return TallaModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      valor: json['valor']?.toString() ?? json['nombre']?.toString() ?? '',
      tipo: json['tipo']?.toString(),
      descripcion: json['descripcion']?.toString(),
    );
  }
}

class ColorFilterModel {
  final int id;
  final String nombre;
  final String? codigoHex;

  ColorFilterModel({
    required this.id,
    required this.nombre,
    this.codigoHex,
  });

  factory ColorFilterModel.fromJson(Map<String, dynamic> json) {
    return ColorFilterModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      nombre: json['nombre']?.toString() ?? '',
      codigoHex: json['codigo_hex']?.toString(),
    );
  }
}
