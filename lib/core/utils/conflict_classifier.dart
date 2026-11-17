/// [EXAMEN-2] Ola 3 / B1.5 — clasificación de conflictos de sincronización.
///
/// El backend (`app/apps/operaciones_offline/models.py`) define el contrato:
///
/// - `TipoConflicto`: `STOCK_INSUFICIENTE`, `PRECIO_DESACTUALIZADO`,
///   `PRODUCTO_INACTIVO`, `VARIANTE_INEXISTENTE`, `VENTA_ORIGEN_INVALIDA`,
///   `SUCURSAL_INVALIDA`, `TENANT_SUSPENDIDO`, `ORDEN_EXPIRADA`,
///   `PAGO_YA_CAPTURADO`, `PAGO_DUPLICADO`.
/// - `EstrategiaResolucion`: `AUTOMATICA`, `MANUAL`, `RECHAZO`.
/// - `SYNC_CONFLICTO_UMBRAL_PRECIO = 0.05` (`app/config.py`): una variación de
///   precio ≤ 5% se resuelve automáticamente; por encima, requiere decisión
///   humana.
///
/// Antes de esta tarea el móvil **no conocía ninguno** de estos valores: leía
/// `detalle` (clave que el backend no envía) en vez de `datos_resultado`, por
/// lo que el tipo de conflicto y la comparación local↔central nunca llegaban
/// a la pantalla de conflictos.
library;

/// Tipos de conflicto del backend (`TipoConflicto`).
class TiposConflicto {
  const TiposConflicto._();

  static const String stockInsuficiente = 'STOCK_INSUFICIENTE';
  static const String precioDesactualizado = 'PRECIO_DESACTUALIZADO';
  static const String productoInactivo = 'PRODUCTO_INACTIVO';
  static const String varianteInexistente = 'VARIANTE_INEXISTENTE';
  static const String ventaOrigenInvalida = 'VENTA_ORIGEN_INVALIDA';
  static const String sucursalInvalida = 'SUCURSAL_INVALIDA';
  static const String tenantSuspendido = 'TENANT_SUSPENDIDO';
  static const String ordenExpirada = 'ORDEN_EXPIRADA';
  static const String pagoYaCapturado = 'PAGO_YA_CAPTURADO';
  static const String pagoDuplicado = 'PAGO_DUPLICADO';

  static const List<String> todos = <String>[
    stockInsuficiente,
    precioDesactualizado,
    productoInactivo,
    varianteInexistente,
    ventaOrigenInvalida,
    sucursalInvalida,
    tenantSuspendido,
    ordenExpirada,
    pagoYaCapturado,
    pagoDuplicado,
  ];
}

/// Estrategias de resolución del backend (`EstrategiaResolucion`).
class EstrategiasResolucion {
  const EstrategiasResolucion._();

  static const String automatica = 'AUTOMATICA';
  static const String manual = 'MANUAL';
  static const String rechazo = 'RECHAZO';
}

/// Estados locales de un conflicto.
///
/// - `CONFLICTO`: revisión tractable por el usuario.
/// - `CONFLICTO_MANUAL`: requiere decisión humana (bloquea esa operación).
/// - `ERROR_DATOS`: datos maestros inválidos (producto desactivado/eliminado).
class EstadosConflicto {
  const EstadosConflicto._();

  static const String conflicto = 'CONFLICTO';
  static const String conflictoManual = 'CONFLICTO_MANUAL';
  static const String errorDatos = 'ERROR_DATOS';
  static const String pendiente = 'PENDIENTE';
  static const String resuelto = 'RESUELTO';
  static const String descartada = 'DESCARTADA';
}

/// Resultado de clasificar un conflicto.
class ClasificacionConflicto {
  const ClasificacionConflicto({
    required this.tipo,
    required this.estado,
    required this.estrategia,
    required this.resolubleAutomaticamente,
    this.diferenciaPorcentaje = 0,
    this.motivo,
  });

  final String tipo;

  /// Estado local con el que se guarda el conflicto.
  final String estado;

  /// `AUTOMATICA` | `MANUAL` | `RECHAZO`.
  final String estrategia;

  /// [EXAMEN-2] B1.5.a: la variación de precio cabe en el umbral del 5%.
  final bool resolubleAutomaticamente;

  /// [EXAMEN-2] B1.5.a: variación de precio detectada (0..1).
  final double diferenciaPorcentaje;

  final String? motivo;
}

/// Utilidad para clasificar el conflicto devuelto por el backend.
class ConflictClassifier {
  const ConflictClassifier._();

  /// [EXAMEN-2] B1.5.a: umbral de variación de precio que el backend
  /// considera resoluble automáticamente (`SYNC_CONFLICTO_UMBRAL_PRECIO`).
  static const double umbralPrecio = 0.05;

  /// Clasifica el `datos_resultado` de una operación en conflicto.
  ///
  /// [datos] es el mapa `datos_resultado` del backend. Formato esperado:
  /// ```json
  /// {
  ///   "tipo_conflicto": "PRECIO_DESACTUALIZADO",
  ///   "estrategia_resolucion": "MANUAL",
  ///   "diferencias": [
  ///     {"precio_local": 100, "precio_central": 110,
  ///      "diferencia": -10, "diferencia_porcentaje": 0.0909,
  ///      "resoluble_automaticamente": false}
  ///   ],
  ///   "total_local": 100, "total_central": 110
  /// }
  /// ```
  static ClasificacionConflicto clasificar(Map<String, Object?> datos) {
    final tipo = (datos['tipo_conflicto']?.toString() ?? '').toUpperCase();
    final estrategia =
        (datos['estrategia_resolucion']?.toString() ?? '').toUpperCase();

    // Variación de precio: la mayor de las diferencias por línea.
    var porcentaje = 0.0;
    var resoluble = true;
    final diferencias = datos['diferencias'];
    if (diferencias is List) {
      for (final linea in diferencias.whereType<Map>()) {
        final valor = (linea['diferencia_porcentaje'] as num?)?.toDouble();
        if (valor != null && valor > porcentaje) porcentaje = valor;
        final marcado = linea['resoluble_automaticamente'];
        if (marcado is bool && !marcado) resoluble = false;
      }
      if (porcentaje == 0) {
        // El backend puede no enviar el porcentaje: se recalcula.
        final local = (datos['total_local'] as num?)?.toDouble();
        final central = (datos['total_central'] as num?)?.toDouble();
        if (local != null && central != null && central != 0) {
          porcentaje = ((local - central) / central).abs();
          resoluble = porcentaje <= umbralPrecio;
        }
      }
    } else if (tipo == TiposConflicto.precioDesactualizado) {
      // Conflicto de precio sin desglose: se recalcula el porcentaje con los
      // totales; si no hay datos, se considera **no** resoluble para que un
      // humano lo revise (el backend no envió el detalle).
      final local = (datos['total_local'] as num?)?.toDouble();
      final central = (datos['total_central'] as num?)?.toDouble();
      if (local != null && central != null && central != 0) {
        porcentaje = ((local - central) / central).abs();
        resoluble = porcentaje <= umbralPrecio;
      } else {
        resoluble = false;
      }
    }

    final estado = estadoPara(
      tipo: tipo,
      estrategia: estrategia,
      resoluble: resoluble,
    );
    return ClasificacionConflicto(
      tipo: tipo.isEmpty ? 'DESCONOCIDO' : tipo,
      estado: estado,
      estrategia: estrategia.isEmpty ? EstrategiasResolucion.manual : estrategia,
      resolubleAutomaticamente: resoluble,
      diferenciaPorcentaje: porcentaje,
    );
  }

  /// [EXAMEN-2] B1.5.b/c: estado local según el tipo y la estrategia.
  static String estadoPara({
    required String tipo,
    required String estrategia,
    required bool resoluble,
  }) {
    // Datos maestros: el producto está desactivado o la variante ya no existe.
    if (tipo == TiposConflicto.productoInactivo ||
        tipo == TiposConflicto.varianteInexistente ||
        tipo == TiposConflicto.sucursalInvalida) {
      return EstadosConflicto.errorDatos;
    }
    // Decisión humana: el backend lo pidió, o la variación de precio excede
    // el umbral del 5%.
    if (estrategia == EstrategiasResolucion.manual) {
      return EstadosConflicto.conflictoManual;
    }
    if (tipo == TiposConflicto.precioDesactualizado && !resoluble) {
      return EstadosConflicto.conflictoManual;
    }
    if (estrategia == EstrategiasResolucion.rechazo) {
      return EstadosConflicto.conflicto;
    }
    return EstadosConflicto.conflicto;
  }

  /// [EXAMEN-2] B1.5.d: el conflicto es de un pago ya capturado ⇒ el
  /// reembolso es del backend (RN-018) y el móvil sólo debe avisar.
  static bool esPagoYaCapturado(String tipo) =>
      tipo.toUpperCase() == TiposConflicto.pagoYaCapturado;

  /// [EXAMEN-2] B1.5.e: el conflicto es de un pago duplicado.
  static bool esPagoDuplicado(String tipo) =>
      tipo.toUpperCase() == TiposConflicto.pagoDuplicado;

  /// [EXAMEN-2] B1.5.d/e: el conflicto requiere una intervención que el móvil
  /// no puede ejecutar (reembolso o cobro duplicado).
  static bool requiereIntervencionServidor(String tipo) {
    final t = tipo.toUpperCase();
    return t == TiposConflicto.pagoYaCapturado ||
        t == TiposConflicto.pagoDuplicado;
  }
}
