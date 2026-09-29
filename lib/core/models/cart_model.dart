class CartItemModel {
  final int id;
  final int varianteProductoId;
  int cantidad;
  final double precioUnitario;
  final double subtotal;
  final String productoNombre;
  final String? productoImagen;
  final String? tallaNombre;
  final String? colorNombre;
  final String? colorHex;
  final String? skuVariante;
  final int stockDisponible;
  final int productoId;
  final int? categoriaId;

  CartItemModel({
    required this.id,
    required this.varianteProductoId,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    required this.productoNombre,
    this.productoImagen,
    this.tallaNombre,
    this.colorNombre,
    this.colorHex,
    this.skuVariante,
    this.stockDisponible = 99,
    this.productoId = 0,
    this.categoriaId,
  });

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    String prodName = 'Prenda de Moda';
    String? prodImg;
    String? tName;
    String? cName;
    String? cHex;
    String? skuVar;
    int stock = 99;
    int prodId = json['producto_id'] is int
        ? json['producto_id']
        : int.tryParse(json['producto_id']?.toString() ?? '') ?? 0;
    int? catId = json['categoria_id'] is int
        ? json['categoria_id']
        : int.tryParse(json['categoria_id']?.toString() ?? '');

    // El backend envía el detalle en 'variante_producto' o 'variante'
    final Map<String, dynamic>? v = (json['variante_producto'] is Map)
        ? json['variante_producto'] as Map<String, dynamic>
        : (json['variante'] is Map ? json['variante'] as Map<String, dynamic> : null);

    if (v != null) {
      skuVar = v['sku_variante']?.toString();
      stock = v['stock_total'] is int
          ? v['stock_total']
          : int.tryParse(v['stock_total']?.toString() ?? '99') ?? 99;

      // Talla: TallaResponse serializa 'valor' (ej. "M", "L", "32")
      if (v['talla'] is Map) {
        final t = v['talla'] as Map<String, dynamic>;
        tName = t['valor']?.toString() ?? t['nombre']?.toString();
      } else {
        tName = v['talla_nombre']?.toString() ?? v['talla']?.toString();
      }

      // Color
      if (v['color'] is Map) {
        final c = v['color'] as Map<String, dynamic>;
        cName = c['nombre']?.toString();
        cHex = c['codigo_hex']?.toString();
      } else {
        cName = v['color_nombre']?.toString() ?? v['color']?.toString();
        cHex = v['color_hex']?.toString();
      }

      // Producto y sus imágenes de Cloudinary
      if (v['producto'] is Map) {
        final p = v['producto'] as Map<String, dynamic>;
        prodName = p['nombre']?.toString() ?? prodName;
        if (prodId == 0) {
          final rawPid = p['id'];
          prodId = rawPid is int
              ? rawPid
              : int.tryParse(rawPid?.toString() ?? '') ?? 0;
        }
        catId ??= p['categoria_id'] is int
            ? p['categoria_id']
            : int.tryParse(p['categoria_id']?.toString() ?? '');
        final rawImgs = p['imagenes'];
        if (rawImgs is List && rawImgs.isNotEmpty) {
          prodImg = rawImgs[0]?.toString();
        } else if (rawImgs is String && rawImgs.isNotEmpty) {
          prodImg = rawImgs;
        }
      }
    }

    // Fallbacks directos si vienen en la raíz del json
    prodName = json['producto_nombre']?.toString() ?? prodName;
    prodImg = json['producto_imagen']?.toString() ?? prodImg;
    tName = json['talla'] is String ? json['talla']?.toString() : tName;
    cName = json['color'] is String ? json['color']?.toString() : cName;

    final unitPrice = (json['precio_unitario'] is num)
        ? (json['precio_unitario'] as num).toDouble()
        : double.tryParse(json['precio_unitario']?.toString() ?? '0') ?? 0.0;

    final q = json['cantidad'] is int
        ? json['cantidad']
        : int.tryParse(json['cantidad']?.toString() ?? '1') ?? 1;

    final sub = json['subtotal'] != null
        ? ((json['subtotal'] is num)
            ? (json['subtotal'] as num).toDouble()
            : double.tryParse(json['subtotal'].toString()) ?? (unitPrice * q))
        : (unitPrice * q);

    return CartItemModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      varianteProductoId: json['variante_producto_id'] is int
          ? json['variante_producto_id']
          : int.tryParse(json['variante_producto_id']?.toString() ?? '0') ?? 0,
      cantidad: q,
      precioUnitario: unitPrice,
      subtotal: sub,
      productoNombre: prodName,
      productoImagen: prodImg,
      tallaNombre: tName,
      colorNombre: cName,
      colorHex: cHex,
      skuVariante: skuVar,
      stockDisponible: stock,
      productoId: prodId,
      categoriaId: catId,
    );
  }

  /// Ítems en el formato de `POST /cupones/validar` (CU27).
  Map<String, dynamic> toValidationJson() {
    return {
      'producto_id': productoId,
      if (categoriaId != null) 'categoria_id': categoriaId,
      'cantidad': cantidad,
      'precio_unitario': precioUnitario,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'variante_producto_id': varianteProductoId,
      'cantidad': cantidad,
      'precio_unitario': precioUnitario,
      'subtotal': subtotal,
      'producto_nombre': productoNombre,
      'producto_imagen': productoImagen,
      'talla_nombre': tallaNombre,
      'color_nombre': colorNombre,
      'color_hex': colorHex,
      'sku_variante': skuVariante,
    };
  }
}

class CartModel {
  final int id;
  final int clienteId;
  final List<CartItemModel> items;
  final double subtotal;
  final double descuentoAplicado;
  final double total;
  final String? cuponCodigo;

  CartModel({
    required this.id,
    required this.clienteId,
    required this.items,
    required this.subtotal,
    this.descuentoAplicado = 0.0,
    required this.total,
    this.cuponCodigo,
  });

  int get totalItems => items.fold(0, (sum, item) => sum + item.cantidad);

  bool get isEmpty => items.isEmpty;

  factory CartModel.empty() {
    return CartModel(
      id: 0,
      clienteId: 0,
      items: [],
      subtotal: 0.0,
      descuentoAplicado: 0.0,
      total: 0.0,
      cuponCodigo: null,
    );
  }

  factory CartModel.fromJson(Map<String, dynamic> json) {
    var rawItems = json['items'] ?? json['detalles'] ?? [];
    List<CartItemModel> itemList = [];
    if (rawItems is List) {
      itemList = rawItems
          .map((item) => CartItemModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    final sub = json['subtotal'] != null
        ? ((json['subtotal'] is num)
            ? (json['subtotal'] as num).toDouble()
            : double.tryParse(json['subtotal'].toString()) ?? 0.0)
        : itemList.fold(0.0, (s, i) => s + i.subtotal);

    final desc = json['descuento_aplicado'] != null
        ? ((json['descuento_aplicado'] is num)
            ? (json['descuento_aplicado'] as num).toDouble()
            : double.tryParse(json['descuento_aplicado'].toString()) ?? 0.0)
        : 0.0;

    final tot = json['total'] != null
        ? ((json['total'] is num)
            ? (json['total'] as num).toDouble()
            : double.tryParse(json['total'].toString()) ?? (sub - desc))
        : (sub - desc);

    String? coupon;
    if (json['cupon'] is Map) {
      coupon = json['cupon']['codigo']?.toString();
    }

    return CartModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      clienteId: json['cliente_id'] is int
          ? json['cliente_id']
          : int.tryParse(json['cliente_id']?.toString() ?? '0') ?? 0,
      items: itemList,
      subtotal: sub,
      descuentoAplicado: desc,
      total: tot,
      cuponCodigo: coupon,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'items': items.map((i) => i.toJson()).toList(),
      'subtotal': subtotal,
      'descuento_aplicado': descuentoAplicado,
      'total': total,
      'cupon_codigo': cuponCodigo,
    };
  }
}
