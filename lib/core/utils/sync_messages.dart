// [EXAMEN-2] C2.8: traducción de estados/motivos de sincronización (CU08/CU09).
class SyncMessages {
  const SyncMessages._();

  static String traducirEstado(String estado) {
    return switch (estado.toUpperCase()) {
      'PENDIENTE' || 'PENDIENTE_SINCRONIZACION' || 'PENDIENTE_ENVIO' =>
        'Pendiente de sincronización',
      'ENVIADA' || 'EN_PROCESO' || 'EN_COLA' => 'Enviada / en proceso',
      'CONFIRMADA' || 'CONFIRMADO' => 'Confirmada',
      'DUPLICADA' || 'DUPLICADO' => 'Duplicada (no se duplicó)',
      'RECHAZADA' || 'RECHAZADO' => 'Rechazada',
      'CONFLICTO' => 'Conflicto — requiere revisión',
      'ERROR_CRITICO' => 'Error crítico',
      'REQUIERE_ACCION_CLIENTE' => 'Requiere acción del cliente',
      'EXPIRADO' => 'Expirado',
      'CANCELADO' => 'Cancelado',
      // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): estados de devolución/reposición.
      'ERROR_VENTA_INVALIDA' => 'Venta original inválida',
      'PENDIENTE_REEMBOLSO' => 'Pendiente de reembolso',
      'SIN_ALTERNATIVA' => 'Sin alternativa de talla',
      'DEVOLUCION' => 'Devolución',
      'REPOSICION' => 'Reposición',
      'COMPLETADA' => 'Completada',
      'FALLIDA' => 'Fallida',
      _ => estado,
    };
  }

  static String traducirMotivo(String motivo) {
    final codigo = motivo.toUpperCase();
    // [EXAMEN-2] Fase 3 (CU13/CU18): códigos de devolución/reposición (cap19).
    if (codigo.contains('ERROR_VENTA_INVALIDA')) {
      return 'La venta original ya no es válida; su devolución no se aplicó.';
    }
    if (codigo.contains('PENDIENTE_REEMBOLSO')) {
      return 'Devolución aprobada, pendiente de entregar el reembolso.';
    }
    if (codigo.contains('SIN_ALTERNATIVA')) {
      return 'No hay talla mayor ni menor; se derivó a devolución (RN-022).';
    }
    if (codigo.contains('STOCK')) {
      return 'Stock insuficiente en el servidor. La venta no se eliminó.';
    }
    if (codigo.contains('PRECIO')) {
      return 'El precio cambió. Revise el total antes de aceptar.';
    }
    if (codigo.contains('INACTIVO')) {
      return 'El producto ya no está activo.';
    }
    if (codigo.contains('TENANT')) {
      return 'La cuenta está suspendida; regularice la suscripción.';
    }
    if (codigo.contains('EXPIR')) return 'La orden o el pago venció.';
    if (codigo.contains('PAGO')) {
      return 'El pago requiere revisión para evitar un cobro duplicado.';
    }
    return motivo.isEmpty ? 'Conflicto sin detalle.' : motivo;
  }

  static String mensajeSincronizacion({
    required int confirmadas,
    required int rechazadas,
  }) =>
      'Sincronización completa: $confirmadas confirmadas, '
      '$rechazadas rechazadas.';
}
