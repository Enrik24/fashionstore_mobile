// [EXAMEN-2] CU17: dispositivo registrado para operar sin conexión.
class DeviceModel {
  const DeviceModel({
    required this.id,
    required this.tenantId,
    required this.usuarioId,
    required this.plataforma,
    required this.activo,
    this.nombre,
    this.ultimaConexion,
    this.fechaRegistro,
  });

  final String id;
  final int tenantId;
  final int usuarioId;
  final String plataforma;
  final String? nombre;
  final bool activo;
  final DateTime? ultimaConexion;
  final DateTime? fechaRegistro;

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    DateTime? fecha(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    return DeviceModel(
      id: json['id']?.toString() ?? '',
      tenantId: (json['tenant_id'] as num?)?.toInt() ?? 0,
      usuarioId: (json['usuario_id'] as num?)?.toInt() ?? 0,
      plataforma: json['plataforma']?.toString() ?? '',
      nombre: json['nombre']?.toString(),
      activo: json['activo'] as bool? ?? false,
      ultimaConexion: fecha(json['ultima_conexion']),
      fechaRegistro: fecha(json['fecha_registro']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tenant_id': tenantId,
    'usuario_id': usuarioId,
    'plataforma': plataforma,
    'nombre': nombre,
    'activo': activo,
    'ultima_conexion': ultimaConexion?.toIso8601String(),
    'fecha_registro': fechaRegistro?.toIso8601String(),
  };
}
