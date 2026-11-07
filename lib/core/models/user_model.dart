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

  Rol({required this.id, required this.nombre, this.descripcion});

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
  // [EXAMEN-2] Contexto multitenant y permisos efectivos para CU17.
  final int? tenantId;
  // [EXAMEN-2] C1.4: nombre del tenant para cabecera POS/sesión (§5.2).
  final String? tenantNombre;
  final List<String> permisos;
  final bool offlinePinConfigurado;
  final bool debeCambiarContrasena;

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
    this.tenantId,
    this.tenantNombre,
    this.permisos = const [],
    this.offlinePinConfigurado = false,
    this.debeCambiarContrasena = false,
  });

  String get fullName => '$nombre $apellido'.trim();
  String get initials {
    final n = nombre.isNotEmpty ? nombre[0].toUpperCase() : '';
    final a = apellido.isNotEmpty ? apellido[0].toUpperCase() : '';
    return '$n$a';
  }

  bool get isAdmin =>
      roles.any((r) => r.nombre.toLowerCase() == 'administrador');
  bool get isClient =>
      roles.any((r) => r.nombre.toLowerCase() == 'cliente') || roles.isEmpty;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    var rawRoles = json['roles'];
    List<Rol> parsedRoles = [];
    if (rawRoles is List) {
      parsedRoles = rawRoles
          .map((r) => Rol.fromJson(r as Map<String, dynamic>))
          .toList();
    }

    final rawPermisos = json['permisos'];
    final parsedPermisos = rawPermisos is List
        ? rawPermisos.map((p) => p.toString()).toList()
        : const <String>[];

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
      // [EXAMEN-2] Acepta el snake_case del backend y el camelCase local.
      tenantId: (json['tenant_id'] ?? json['tenantId']) as int?,
      tenantNombre: (json['tenant'] is Map
          ? (json['tenant'] as Map)['nombre']?.toString()
          : json['tenant_nombre']?.toString() ?? json['tenantNombre']?.toString()),
      permisos: parsedPermisos,
      offlinePinConfigurado:
          (json['offline_pin_configurado'] ?? json['offlinePinConfigurado'])
              as bool? ??
          false,
      debeCambiarContrasena:
          (json['debe_cambiar_contrasena'] ?? json['debeCambiarContrasena'])
              as bool? ??
          false,
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
    // [EXAMEN-2] Persistencia local del contexto offline.
    'tenant_id': tenantId,
    'tenant_nombre': tenantNombre,
    'permisos': permisos,
    'offline_pin_configurado': offlinePinConfigurado,
    'debe_cambiar_contrasena': debeCambiarContrasena,
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
    int? tenantId,
    String? tenantNombre,
    List<String>? permisos,
    bool? offlinePinConfigurado,
    bool? debeCambiarContrasena,
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
      // [EXAMEN-2](copyWith)
      tenantId: tenantId ?? this.tenantId,
      tenantNombre: tenantNombre ?? this.tenantNombre,
      permisos: permisos ?? this.permisos,
      offlinePinConfigurado:
          offlinePinConfigurado ?? this.offlinePinConfigurado,
      debeCambiarContrasena:
          debeCambiarContrasena ?? this.debeCambiarContrasena,
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
  // [EXAMEN-2] C1.4: tenant y preferencias del cliente (§5.2).
  final int? tenantId;
  final Map<String, dynamic>? preferencias;

  ClienteProfile({
    required this.id,
    required this.nitCi,
    this.direccionEnvio,
    required this.nombre,
    required this.apellido,
    required this.correo,
    this.telefono,
    this.fechaRegistro,
    this.tenantId,
    this.preferencias,
  });

  String get fullName => '$nombre $apellido'.trim();

  factory ClienteProfile.fromJson(Map<String, dynamic> json) {
    final prefs = json['preferencias'];
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
      tenantId: (json['tenant_id'] ?? json['tenantId']) as int?,
      preferencias: prefs is Map<String, dynamic> ? prefs : null,
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
    'tenant_id': tenantId,
    'preferencias': preferencias,
  };

  ClienteProfile copyWith({
    int? id,
    String? nitCi,
    String? direccionEnvio,
    String? nombre,
    String? apellido,
    String? correo,
    String? telefono,
    DateTime? fechaRegistro,
    int? tenantId,
    Map<String, dynamic>? preferencias,
  }) {
    return ClienteProfile(
      id: id ?? this.id,
      nitCi: nitCi ?? this.nitCi,
      direccionEnvio: direccionEnvio ?? this.direccionEnvio,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      correo: correo ?? this.correo,
      telefono: telefono ?? this.telefono,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
      tenantId: tenantId ?? this.tenantId,
      preferencias: preferencias ?? this.preferencias,
    );
  }
}
