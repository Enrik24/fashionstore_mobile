class BranchModel {
  final int id;
  final String nombre;
  final String direccion;
  final String? telefono;
  final double latitud;
  final double longitud;
  final String? horarioApertura;
  final String? horarioCierre;
  final bool activo;

  BranchModel({
    required this.id,
    required this.nombre,
    required this.direccion,
    this.telefono,
    required this.latitud,
    required this.longitud,
    this.horarioApertura,
    this.horarioCierre,
    this.activo = true,
  });

  factory BranchModel.fromJson(Map<String, dynamic> json) {
    return BranchModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      nombre: json['nombre']?.toString() ?? 'Sucursal',
      direccion: json['direccion']?.toString() ?? '',
      telefono: json['telefono']?.toString(),
      latitud: (json['latitud'] is num)
          ? (json['latitud'] as num).toDouble()
          : double.tryParse(json['latitud']?.toString() ?? '-17.7833') ?? -17.7833,
      longitud: (json['longitud'] is num)
          ? (json['longitud'] as num).toDouble()
          : double.tryParse(json['longitud']?.toString() ?? '-63.1821') ?? -63.1821,
      horarioApertura: json['horario_apertura']?.toString() ?? '09:00',
      horarioCierre: json['horario_cierre']?.toString() ?? '21:00',
      activo: json['activo'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'direccion': direccion,
      'telefono': telefono,
      'latitud': latitud,
      'longitud': longitud,
      'horario_apertura': horarioApertura,
      'horario_cierre': horarioCierre,
      'activo': activo,
    };
  }
}

class ReservationItemModel {
  final int id;
  final int varianteProductoId;
  final int cantidad;
  final String? productoNombre;
  final String? productoImagen;
  final String? talla;
  final String? color;

  ReservationItemModel({
    required this.id,
    required this.varianteProductoId,
    required this.cantidad,
    this.productoNombre,
    this.productoImagen,
    this.talla,
    this.color,
  });

  factory ReservationItemModel.fromJson(Map<String, dynamic> json) {
    String? prodName = json['producto_nombre']?.toString();
    String? prodImg = json['producto_imagen']?.toString();
    String? t = json['talla']?.toString();
    String? c = json['color']?.toString();

    // El backend (DetalleReservaResponse) envía la variante en 'variante_producto'
    final Map<String, dynamic>? varianteMap = (json['variante_producto'] is Map)
        ? json['variante_producto'] as Map<String, dynamic>
        : (json['variante'] is Map ? json['variante'] as Map<String, dynamic> : null);

    if (varianteMap != null) {
      final v = varianteMap;
      t = t ?? (v['talla'] is Map
          ? (v['talla']['valor']?.toString() ?? v['talla']['nombre']?.toString())
          : v['talla_nombre']?.toString());
      c = c ?? (v['color'] is Map ? v['color']['nombre']?.toString() : v['color_nombre']?.toString());
      if (v['producto'] != null && v['producto'] is Map) {
        prodName = prodName ?? v['producto']['nombre']?.toString();
        if (v['producto']['imagenes'] is List && (v['producto']['imagenes'] as List).isNotEmpty) {
          prodImg = prodImg ?? v['producto']['imagenes'][0]?.toString();
        }
      }
    }

    return ReservationItemModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      varianteProductoId: json['variante_producto_id'] is int
          ? json['variante_producto_id']
          : int.tryParse(json['variante_producto_id']?.toString() ?? '0') ?? 0,
      cantidad: json['cantidad'] is int
          ? json['cantidad']
          : int.tryParse(json['cantidad']?.toString() ?? '1') ?? 1,
      productoNombre: prodName ?? 'Prenda',
      productoImagen: prodImg,
      talla: t,
      color: c,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'variante_producto_id': varianteProductoId,
      'cantidad': cantidad,
      'producto_nombre': productoNombre,
      'producto_imagen': productoImagen,
      'talla': talla,
      'color': color,
    };
  }
}

class ReservationModel {
  final int id;
  final String numeroReserva;
  final int clienteId;
  final int sucursalId;
  final String? sucursalNombre;
  final String? sucursalDireccion;
  final DateTime fechaReserva;
  final String? horarioAproximado;
  final String estado;
  final String? notas;
  final List<ReservationItemModel> items;
  final DateTime? createdAt;

  ReservationModel({
    required this.id,
    required this.numeroReserva,
    required this.clienteId,
    required this.sucursalId,
    this.sucursalNombre,
    this.sucursalDireccion,
    required this.fechaReserva,
    this.horarioAproximado,
    required this.estado,
    this.notas,
    this.items = const [],
    this.createdAt,
  });

  bool get isPending => estado.toUpperCase() == 'PENDIENTE';
  bool get isConfirmed => estado.toUpperCase() == 'CONFIRMADA';
  bool get isExpired => estado.toUpperCase() == 'EXPIRADA';
  bool get isCancelled => estado.toUpperCase() == 'CANCELADA';
  bool get isCompleted => estado.toUpperCase() == 'COMPLETADA';

  factory ReservationModel.fromJson(Map<String, dynamic> json) {
    var rawItems = json['detalles'] ?? json['items'] ?? [];
    List<ReservationItemModel> itemList = [];
    if (rawItems is List) {
      itemList = rawItems
          .map((item) => ReservationItemModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    DateTime parsedDate;
    try {
      parsedDate = json['fecha_reserva'] != null
          ? DateTime.parse(json['fecha_reserva'].toString())
          : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    DateTime? parsedCreated;
    if (json['created_at'] != null) {
      try {
        parsedCreated = DateTime.parse(json['created_at'].toString());
      } catch (_) {}
    }

    return ReservationModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      numeroReserva: json['numero_reserva']?.toString() ?? 'RES-${json['id']}',
      clienteId: json['cliente_id'] is int
          ? json['cliente_id']
          : int.tryParse(json['cliente_id']?.toString() ?? '0') ?? 0,
      sucursalId: json['sucursal_id'] is int
          ? json['sucursal_id']
          : int.tryParse(json['sucursal_id']?.toString() ?? '0') ?? 0,
      sucursalNombre: json['sucursal'] is Map
          ? json['sucursal']['nombre']?.toString()
          : json['sucursal_nombre']?.toString(),
      sucursalDireccion: json['sucursal'] is Map
          ? json['sucursal']['direccion']?.toString()
          : json['sucursal_direccion']?.toString(),
      fechaReserva: parsedDate,
      horarioAproximado: json['horario_aproximado']?.toString(),
      estado: json['estado']?.toString() ?? 'PENDIENTE',
      notas: json['notas']?.toString(),
      items: itemList,
      createdAt: parsedCreated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numero_reserva': numeroReserva,
      'cliente_id': clienteId,
      'sucursal_id': sucursalId,
      'sucursal_nombre': sucursalNombre,
      'sucursal_direccion': sucursalDireccion,
      'fecha_reserva': fechaReserva.toIso8601String(),
      'horario_aproximado': horarioAproximado,
      'estado': estado,
      'notas': notas,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }
}
