/// Valoración de un producto (CU26).
/// Backend: ValoracionResponse
/// {id, producto_id, cliente_id, cliente_nombre, puntuacion, comentario,
///  estado, fecha_creacion, fecha_actualizacion}
class ReviewModel {
  final int id;
  final int productoId;
  final int clienteId;
  final String clienteNombre;
  final int puntuacion;
  final String? comentario;
  final String estado;
  final DateTime? fechaCreacion;
  final DateTime? fechaActualizacion;

  ReviewModel({
    required this.id,
    required this.productoId,
    required this.clienteId,
    required this.clienteNombre,
    required this.puntuacion,
    this.comentario,
    this.estado = 'PUBLICADA',
    this.fechaCreacion,
    this.fechaActualizacion,
  });

  bool get isPublicada => estado.toUpperCase() == 'PUBLICADA';

  static int _parseInt(dynamic raw, [int fallback = 0]) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static DateTime? _parseDate(dynamic raw) {
    final s = raw?.toString();
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    return ReviewModel(
      id: _parseInt(json['id']),
      productoId: _parseInt(json['producto_id']),
      clienteId: _parseInt(json['cliente_id']),
      clienteNombre: json['cliente_nombre']?.toString() ?? 'Cliente',
      puntuacion: _parseInt(json['puntuacion'], 5).clamp(1, 5),
      comentario: json['comentario']?.toString(),
      estado: json['estado']?.toString() ?? 'PUBLICADA',
      fechaCreacion: _parseDate(json['fecha_creacion']),
      fechaActualizacion: _parseDate(json['fecha_actualizacion']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'producto_id': productoId,
      'cliente_id': clienteId,
      'cliente_nombre': clienteNombre,
      'puntuacion': puntuacion,
      'comentario': comentario,
      'estado': estado,
    };
  }
}

/// Respuesta de `GET /productos/{id}/puede-valorar` (CU26).
class CanReviewModel {
  final bool puedeValorar;
  final String? motivo;
  final ReviewModel? valoracionExistente;

  CanReviewModel({
    required this.puedeValorar,
    this.motivo,
    this.valoracionExistente,
  });

  factory CanReviewModel.fromJson(Map<String, dynamic> json) {
    final rawExistente = json['valoracion_existente'];
    return CanReviewModel(
      puedeValorar: json['puede_valorar'] == true,
      motivo: json['motivo']?.toString(),
      valoracionExistente: rawExistente is Map<String, dynamic>
          ? ReviewModel.fromJson(rawExistente)
          : null,
    );
  }
}
