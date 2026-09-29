import 'comprobante_model.dart';

class OrderItemModel {
  final int id;
  final int varianteProductoId;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;
  final String productoNombre;
  final String? productoImagen;
  final String? talla;
  final String? color;
  final int productoId;

  OrderItemModel({
    required this.id,
    required this.varianteProductoId,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    required this.productoNombre,
    this.productoImagen,
    this.talla,
    this.color,
    this.productoId = 0,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    String prodName = json['producto_nombre']?.toString() ?? 'Prenda';
    String? prodImg = json['producto_imagen']?.toString();
    String? t = json['talla']?.toString();
    String? c = json['color']?.toString();
    int prodId = json['producto_id'] is int
        ? json['producto_id']
        : int.tryParse(json['producto_id']?.toString() ?? '') ?? 0;

    if (json['variante'] != null && json['variante'] is Map) {
      final v = json['variante'] as Map<String, dynamic>;
      t = t ?? (v['talla'] is Map
          ? (v['talla']['valor']?.toString() ?? v['talla']['nombre']?.toString())
          : v['talla_nombre']?.toString());
      c = c ?? (v['color'] is Map ? v['color']['nombre']?.toString() : v['color_nombre']?.toString());
      if (v['producto'] != null && v['producto'] is Map) {
        prodName = v['producto']['nombre']?.toString() ?? prodName;
        if (prodId == 0) {
          final rawPid = v['producto']['id'];
          prodId = rawPid is int
              ? rawPid
              : int.tryParse(rawPid?.toString() ?? '') ?? 0;
        }
        if (v['producto']['imagenes'] is List && (v['producto']['imagenes'] as List).isNotEmpty) {
          prodImg = prodImg ?? v['producto']['imagenes'][0]?.toString();
        }
      }
    }

    // El backend de órdenes serializa el detalle en 'variante_producto'.
    if (json['variante_producto'] != null &&
        json['variante_producto'] is Map) {
      final v = json['variante_producto'] as Map<String, dynamic>;
      if (v['producto'] != null && v['producto'] is Map) {
        final p = v['producto'] as Map<String, dynamic>;
        prodName = p['nombre']?.toString() ?? prodName;
        if (prodId == 0) {
          final rawPid = p['id'];
          prodId = rawPid is int
              ? rawPid
              : int.tryParse(rawPid?.toString() ?? '') ?? 0;
        }
        if (p['imagenes'] is List &&
            (p['imagenes'] as List).isNotEmpty) {
          prodImg = prodImg ?? p['imagenes'][0]?.toString();
        }
      }
    }

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

    return OrderItemModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      varianteProductoId: json['variante_producto_id'] is int
          ? json['variante_producto_id']
          : int.tryParse(json['variante_producto_id']?.toString() ?? '0') ?? 0,
      cantidad: q,
      precioUnitario: unitPrice,
      subtotal: sub,
      productoNombre: prodName,
      productoImagen: prodImg,
      talla: t,
      color: c,
      productoId: prodId,
    );
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
      'talla': talla,
      'color': color,
      'producto_id': productoId,
    };
  }
}

class OrderModel {
  final int id;
  final String numeroOrden;
  final int clienteId;
  final double total;
  final double subtotal;
  final double costoEnvio;
  final double descuento;
  final double impuestos;
  final String estado;
  final int? sucursalId;
  final String? sucursalNombre;
  final String? direccionEnvio;
  final String? ciudadEnvio;
  final String? telefonoContacto;
  final String? metodoPago;
  final String? referenciaPago;
  final List<OrderItemModel> items;
  final DateTime? createdAt;
  final ComprobanteModel? comprobante;

  OrderModel({
    required this.id,
    required this.numeroOrden,
    required this.clienteId,
    required this.total,
    this.subtotal = 0.0,
    this.costoEnvio = 0.0,
    this.descuento = 0.0,
    this.impuestos = 0.0,
    required this.estado,
    this.sucursalId,
    this.sucursalNombre,
    this.direccionEnvio,
    this.ciudadEnvio,
    this.telefonoContacto,
    this.metodoPago,
    this.referenciaPago,
    this.items = const [],
    this.createdAt,
    this.comprobante,
  });

  bool get isPaid => estado.toUpperCase() == 'PAGADO' || estado.toUpperCase() == 'COMPLETADO';
  // El backend usa PENDIENTE_PAGO (no PENDIENTE a secas).
  bool get isPending => estado.toUpperCase().startsWith('PENDIENTE');
  bool get isCancelled => estado.toUpperCase() == 'CANCELADO';

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    var rawItems = json['detalles'] ?? json['items'] ?? [];
    List<OrderItemModel> itemList = [];
    if (rawItems is List) {
      itemList = rawItems
          .map((item) => OrderItemModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    String? sNombre;
    if (json['sucursal'] != null && json['sucursal'] is Map) {
      sNombre = json['sucursal']['nombre']?.toString();
    }

    final tot = (json['total'] is num)
        ? (json['total'] as num).toDouble()
        : double.tryParse(json['total']?.toString() ?? '0') ?? 0.0;

    final sub = json['subtotal'] != null
        ? ((json['subtotal'] is num)
            ? (json['subtotal'] as num).toDouble()
            : double.tryParse(json['subtotal'].toString()) ?? tot)
        : tot;

    DateTime? parsedDate;
    if (json['created_at'] != null) {
      try {
        parsedDate = DateTime.parse(json['created_at'].toString());
      } catch (_) {}
    }

    // El backend incluye el comprobante anidado (OrdenResponse.comprobante).
    ComprobanteModel? comprobante;
    if (json['comprobante'] is Map<String, dynamic>) {
      try {
        comprobante = ComprobanteModel.fromJson(
            json['comprobante'] as Map<String, dynamic>);
      } catch (_) {}
    }

    return OrderModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      numeroOrden: json['numero_orden']?.toString() ?? 'ORD-${json['id']}',
      clienteId: json['cliente_id'] is int
          ? json['cliente_id']
          : int.tryParse(json['cliente_id']?.toString() ?? '0') ?? 0,
      total: tot,
      subtotal: sub,
      costoEnvio: json['costo_envio'] != null
          ? ((json['costo_envio'] is num)
              ? (json['costo_envio'] as num).toDouble()
              : double.tryParse(json['costo_envio'].toString()) ?? 0.0)
          : 0.0,
      descuento: json['descuento'] != null
          ? ((json['descuento'] is num)
              ? (json['descuento'] as num).toDouble()
              : double.tryParse(json['descuento'].toString()) ?? 0.0)
          : 0.0,
      impuestos: json['impuestos'] != null
          ? ((json['impuestos'] is num)
              ? (json['impuestos'] as num).toDouble()
              : double.tryParse(json['impuestos'].toString()) ?? 0.0)
          : 0.0,
      estado: json['estado']?.toString() ?? 'PENDIENTE',
      sucursalId: json['sucursal_id'] is int
          ? json['sucursal_id']
          : int.tryParse(json['sucursal_id']?.toString() ?? ''),
      sucursalNombre: sNombre,
      direccionEnvio: json['direccion_envio']?.toString(),
      ciudadEnvio: json['ciudad_envio']?.toString() ?? json['ciudad']?.toString(),
      telefonoContacto: json['telefono_contacto']?.toString() ?? json['telefono']?.toString(),
      metodoPago: json['metodo_pago']?.toString(),
      referenciaPago: json['referencia_pago']?.toString(),
      items: itemList,
      createdAt: parsedDate ?? DateTime.now(),
      comprobante: comprobante,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numero_orden': numeroOrden,
      'cliente_id': clienteId,
      'total': total,
      'subtotal': subtotal,
      'costo_envio': costoEnvio,
      'descuento': descuento,
      'impuestos': impuestos,
      'estado': estado,
      'sucursal_id': sucursalId,
      'direccion_envio': direccionEnvio,
      'ciudad_envio': ciudadEnvio,
      'telefono_contacto': telefonoContacto,
      'metodo_pago': metodoPago,
      'referencia_pago': referenciaPago,
      'items': items.map((i) => i.toJson()).toList(),
      'comprobante': comprobante?.toJson(),
    };
  }
}

class StripeSessionResponse {
  final String checkoutUrl;
  final String sessionId;
  final int ordenId;

  StripeSessionResponse({
    required this.checkoutUrl,
    required this.sessionId,
    required this.ordenId,
  });

  factory StripeSessionResponse.fromJson(Map<String, dynamic> json) {
    return StripeSessionResponse(
      checkoutUrl: json['checkout_url']?.toString() ?? json['url']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? json['id']?.toString() ?? '',
      ordenId: json['orden_id'] is int
          ? json['orden_id']
          : int.tryParse(json['orden_id']?.toString() ?? '0') ?? 0,
    );
  }
}

class PayPalOrderResponse {
  final String orderId;
  final String approveUrl;
  final String status;

  PayPalOrderResponse({
    required this.orderId,
    required this.approveUrl,
    required this.status,
  });

  factory PayPalOrderResponse.fromJson(Map<String, dynamic> json) {
    return PayPalOrderResponse(
      orderId: json['order_id']?.toString() ?? '',
      approveUrl: json['approve_url']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

