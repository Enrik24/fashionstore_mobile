// [FIX-UI] Etiquetas legibles para pagos diferidos (CU16): referencia corta
// de pedido en lugar del UUID completo y estado en lenguaje natural.
library;

/// Referencia corta de un pedido/pago: primeros 8 hex del UUID en mayúsculas.
String referenciaCorta(String? uuid) {
  if (uuid == null || uuid.isEmpty) return '—';
  final limpio = uuid.replaceAll('-', '');
  final largo = limpio.length < 8 ? limpio.length : 8;
  return limpio.substring(0, largo).toUpperCase();
}

/// Etiqueta legible del estado local de un pago diferido.
String etiquetaEstadoPago(String estado) {
  switch (estado.toUpperCase()) {
    case 'PENDIENTE':
    case 'PENDIENTE_ENVIO':
      return 'Pendiente de envío';
    case 'REQUIERE_ACCION_CLIENTE':
      return 'Listo para pagar';
    case 'EN_PROCESO':
      return 'En proceso';
    case 'EN_COLA':
      return 'En cola';
    case 'CONFIRMADO':
      return 'Confirmado';
    case 'CANCELADO':
      return 'Cancelado';
    case 'EXPIRADO':
      return 'Expirado';
    case 'RECHAZADO':
      return 'Rechazado';
    case 'ERROR_CRITICO':
      return 'Error crítico';
    default:
      return estado;
  }
}