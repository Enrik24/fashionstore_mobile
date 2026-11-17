// [EXAMEN-2] C2.8: traducción de estados/motivos de sincronización (CU08/CU09).
import 'conflict_classifier.dart';

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
      // [EXAMEN-2] B1.5.b: requiere decisión humana; bloquea esa operación.
      'CONFLICTO_MANUAL' => 'Conflicto — requiere decisión del administrador',
      // [EXAMEN-2] B1.5.c: datos maestros inválidos en el servidor.
      'ERROR_DATOS' =>
        'Error de datos maestros — producto desactivado o eliminado',
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

  /// [EXAMEN-2] B1.5: mensaje de un **tipo de conflicto** del backend
  /// (`TipoConflicto`). Devuelve `null` si el tipo no es conocido.
  static String? traducirTipoConflicto(String tipo) {
    switch (tipo.toUpperCase()) {
      case TiposConflicto.stockInsuficiente:
        return 'Stock insuficiente en el servidor. La venta no se eliminó.';
      case TiposConflicto.precioDesactualizado:
        return 'El precio cambió. Revise el total antes de aceptar.';
      case TiposConflicto.productoInactivo:
        return 'El producto ya no está activo en el servidor.';
      case TiposConflicto.varianteInexistente:
        return 'La variante ya no existe en el catálogo del servidor.';
      case TiposConflicto.ventaOrigenInvalida:
        return 'La venta original no es válida; la operación no se aplicó.';
      case TiposConflicto.sucursalInvalida:
        return 'La sucursal ya no está disponible.';
      case TiposConflicto.tenantSuspendido:
        return 'La cuenta está suspendida; regularice la suscripción.';
      case TiposConflicto.ordenExpirada:
        return 'La orden venció antes de aplicarse.';
      case TiposConflicto.pagoYaCapturado:
        return 'El pago ya fue capturado; el sistema genera el reembolso.';
      case TiposConflicto.pagoDuplicado:
        return 'El pago requiere revisión para evitar un cobro duplicado.';
      default:
        return null;
    }
  }

  static String traducirMotivo(String motivo) {
    final codigo = motivo.toUpperCase();
    // [EXAMEN-2] B1.5: si el motivo es un tipo de conflicto del backend, se
    // traduce con su mensaje específico.
    final porTipo = traducirTipoConflicto(codigo);
    if (porTipo != null) return porTipo;
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
    int pendientes = 0,
  }) {
    // [BUG-SYNC] con operaciones aún pendientes no es "completa": era
    // engañoso ver "Sincronización completa: 0 confirmadas, 0 rechazadas"
    // con el badge "Pendientes: 1" encendido.
    if (pendientes > 0) {
      return 'Sincronización parcial: $confirmadas confirmadas, '
          '$rechazadas rechazadas, $pendientes pendientes de reintentar.';
    }
    return 'Sincronización completa: $confirmadas confirmadas, '
        '$rechazadas rechazadas.';
  }
}
