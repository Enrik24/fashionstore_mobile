class TokenResponse {
  final String accessToken;
  final String refreshToken;
  final String tokenType;

  TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = 'bearer',
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'bearer',
    );
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': tokenType,
  };
}

class Rol {
  final int id;
  final String nombre;
  final String? descripcion;

  Rol({
    required this.id,
    required this.nombre,
    this.descripcion,
  });

  factory Rol.fromJson(Map<String, dynamic> json) {
    return Rol(
      id: json['id'] as int? ?? 0,
      nombre: json['nombre'] as String? ?? '',
      descripcion: json['descripcion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'descripcion': descripcion,
  };
}

class UserModel {
  final int id;
  final String nombre;
  final String apellido;
  final String correo;
  final String? telefono;
  final String estado;
  final DateTime? fechaRegistro;
  final DateTime? ultimoAcceso;
  final List<Rol> roles;

  UserModel({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.correo,
    this.telefono,
    this.estado = 'ACTIVO',
    this.fechaRegistro,
    this.ultimoAcceso,
    this.roles = const [],
  });

  String get fullName => '$nombre $apellido'.trim();
  String get initials {
    final n = nombre.isNotEmpty ? nombre[0].toUpperCase() : '';
    final a = apellido.isNotEmpty ? apellido[0].toUpperCase() : '';
    return '$n$a';
  }

  bool get isAdmin => roles.any((r) => r.nombre.toLowerCase() == 'administrador');
  bool get isClient => roles.any((r) => r.nombre.toLowerCase() == 'cliente') || roles.isEmpty;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    var rawRoles = json['roles'];
    List<Rol> parsedRoles = [];
    if (rawRoles is List) {
      parsedRoles = rawRoles.map((r) => Rol.fromJson(r as Map<String, dynamic>)).toList();
    }

    return UserModel(
      id: json['id'] as int? ?? 0,
      nombre: json['nombre'] as String? ?? '',
      apellido: json['apellido'] as String? ?? '',
      correo: json['correo'] as String? ?? '',
      telefono: json['telefono'] as String?,
      estado: json['estado'] as String? ?? 'ACTIVO',
      fechaRegistro: json['fecha_registro'] != null
          ? DateTime.tryParse(json['fecha_registro'].toString())
          : null,
      ultimoAcceso: json['ultimo_acceso'] != null
          ? DateTime.tryParse(json['ultimo_acceso'].toString())
          : null,
      roles: parsedRoles,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'apellido': apellido,
    'correo': correo,
    'telefono': telefono,
    'estado': estado,
    'fecha_registro': fechaRegistro?.toIso8601String(),
    'ultimo_acceso': ultimoAcceso?.toIso8601String(),
    'roles': roles.map((r) => r.toJson()).toList(),
  };

  UserModel copyWith({
    int? id,
    String? nombre,
    String? apellido,
    String? correo,
    String? telefono,
    String? estado,
    DateTime? fechaRegistro,
    DateTime? ultimoAcceso,
    List<Rol>? roles,
  }) {
    return UserModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      correo: correo ?? this.correo,
      telefono: telefono ?? this.telefono,
      estado: estado ?? this.estado,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
      ultimoAcceso: ultimoAcceso ?? this.ultimoAcceso,
      roles: roles ?? this.roles,
    );
  }
}

class ClienteProfile {
  final int id;
  final String nitCi;
  final String? direccionEnvio;
  final String nombre;
  final String apellido;
  final String correo;
  final String? telefono;
  final DateTime? fechaRegistro;

  ClienteProfile({
    required this.id,
    required this.nitCi,
    this.direccionEnvio,
    required this.nombre,
    required this.apellido,
    required this.correo,
    this.telefono,
    this.fechaRegistro,
  });

  String get fullName => '$nombre $apellido'.trim();

  factory ClienteProfile.fromJson(Map<String, dynamic> json) {
    return ClienteProfile(
      id: json['id'] as int? ?? 0,
      nitCi: json['nit_ci'] as String? ?? '',
      direccionEnvio: json['direccion_envio'] as String?,
      nombre: json['nombre'] as String? ?? '',
      apellido: json['apellido'] as String? ?? '',
      correo: json['correo'] as String? ?? '',
      telefono: json['telefono'] as String?,
      fechaRegistro: json['fecha_registro'] != null
          ? DateTime.tryParse(json['fecha_registro'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nit_ci': nitCi,
    'direccion_envio': direccionEnvio,
    'nombre': nombre,
    'apellido': apellido,
    'correo': correo,
    'telefono': telefono,
    'fecha_registro': fechaRegistro?.toIso8601String(),
  };
}
