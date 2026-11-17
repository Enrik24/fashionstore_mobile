// [EXAMEN-2] CU17 / CU05: configuración offline efectiva del tenant.
class OfflineConfigModel {
  const OfflineConfigModel({
    this.tenantId = 0,
    this.descargaAutomatica = true,
    this.horaDescarga,
    this.incluirClientes = true,
    this.maxClientes = 100,
    this.habilitarCarritoOffline = true,
    this.maxHorasSesionOffline = 12,
    this.maxDiasOrdenPendiente = 1,
    this.moneda = 'BOB',
    this.clavePublicaStripe,
    // [EXAMEN-2] B1.1.a: tasa de impuestos vigente que el backend ya envía
    // en el paquete offline (`impuestos.tasa_total`). Antes el móvil la
    // ignoraba y los totales offline no incluían impuestos.
    this.tasaImpuestos = 0,
  });

  final int tenantId;
  final bool descargaAutomatica;
  final String? horaDescarga;
  final bool incluirClientes;
  final int maxClientes;
  final bool habilitarCarritoOffline;
  final int maxHorasSesionOffline;
  final int maxDiasOrdenPendiente;
  final String moneda;
  final String? clavePublicaStripe;

  /// [EXAMEN-2] B1.1.a: tasa total de impuestos (0 = sin impuestos).
  final double tasaImpuestos;

  factory OfflineConfigModel.fromJson(Map<String, dynamic> json) =>
      OfflineConfigModel(
        tenantId: (json['tenant_id'] as num?)?.toInt() ?? 0,
        descargaAutomatica: json['descarga_automatica'] as bool? ?? true,
        horaDescarga: json['hora_descarga']?.toString(),
        incluirClientes: json['incluir_clientes'] as bool? ?? true,
        maxClientes: (json['max_clientes'] as num?)?.toInt() ?? 100,
        habilitarCarritoOffline:
            json['habilitar_carrito_offline'] as bool? ?? true,
        maxHorasSesionOffline:
            (json['max_horas_sesion_offline'] as num?)?.toInt() ?? 12,
        maxDiasOrdenPendiente:
            (json['max_dias_orden_pendiente'] as num?)?.toInt() ?? 1,
        moneda: json['moneda']?.toString() ?? 'BOB',
        clavePublicaStripe: json['clave_publica_stripe']?.toString(),
        tasaImpuestos:
            (json['tasa_total'] as num?)?.toDouble() ??
            (json['tasa_impuestos'] as num?)?.toDouble() ??
            0,
      );

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'descarga_automatica': descargaAutomatica,
    'hora_descarga': horaDescarga,
    'incluir_clientes': incluirClientes,
    'max_clientes': maxClientes,
    'habilitar_carrito_offline': habilitarCarritoOffline,
    'max_horas_sesion_offline': maxHorasSesionOffline,
    'max_dias_orden_pendiente': maxDiasOrdenPendiente,
    'moneda': moneda,
    'clave_publica_stripe': clavePublicaStripe,
    'tasa_total': tasaImpuestos,
  };
}
