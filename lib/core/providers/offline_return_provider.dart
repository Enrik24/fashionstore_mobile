// [EXAMEN-2] CU13/CU18: estado de la devolución y reposición offline.
// Orquesta PosService (venta original, plazo, reserva) y ReturnService
// (crear offline, alternativas) sin hablar con Dio ni con SQLite.
import 'package:flutter/material.dart';

import '../models/return_request_model.dart';
import '../services/pos_service.dart';
import '../services/pos_sesion_service.dart';
import '../services/return_service.dart';

/// Línea seleccionada por el cajero (prenda devuelta / prenda nueva).
class LineaSeleccion {
  const LineaSeleccion({
    required this.varianteProductoId,
    this.productoId,
    this.productoNombre,
    this.cantidad = 1,
    required this.precioUnitario,
    this.varianteCambioId,
    this.precioVarianteNueva,
    this.detalleOrdenId,
  });

  final int varianteProductoId;
  final int? productoId;
  final String? productoNombre;
  final int cantidad;
  final double precioUnitario;
  final int? varianteCambioId;
  final double? precioVarianteNueva;
  final int? detalleOrdenId;

  LineaDevolucion toLineaDevolucion() => LineaDevolucion(
    varianteProductoId: varianteProductoId,
    detalleOrdenId: detalleOrdenId,
    productoId: productoId,
    productoNombre: productoNombre,
    cantidad: cantidad,
    precioUnitario: precioUnitario,
    varianteCambioId: varianteCambioId,
    precioVarianteNueva: precioVarianteNueva,
  );
}

class OfflineReturnProvider extends ChangeNotifier {
  OfflineReturnProvider({
    required ReturnService returnService,
    PosService? posService,
    // [EXAMEN-2] CU13/CU18: sucursal de la sesión (sin sucursalId fija).
    PosSesionService? sesion,
  }) : _returnService = returnService,
       _posService = posService,
       _sesion = sesion;

  final ReturnService _returnService;
  final PosService? _posService;
  final PosSesionService? _sesion;

  /// [EXAMEN-2] CU13/CU18: sucursal de la sesión para operaciones offline.
  Future<int> resolverSucursalId() =>
      _sesion?.resolverSucursalId() ?? Future.value(0);

  Map<String, Object?>? _ventaOriginal;
  bool _plazoValido = false;
  final List<LineaSeleccion> _items = [];
  String _tipoSolicitud = 'DEVOLUCION';
  double _diferencia = 0;
  double _saldoFavor = 0;
  List<Map<String, Object?>> _alternativas = const [];
  ReturnRequestModel? _ultimaSolicitud;
  bool _loading = false;
  String? _error;
  bool _sinAlternativa = false;
  // [EXAMEN-2] B0.1: motivo y medio de reembolso seleccionados por el cajero.
  String _motivo = MotivosDevolucion.tallaIncorrecta;
  String _medioReembolso = 'REEMBOLSO';

  Map<String, Object?>? get ventaOriginal => _ventaOriginal;
  bool get plazoValido => _plazoValido;
  List<LineaSeleccion> get itemsDevolucion => List.unmodifiable(_items);
  List<LineaSeleccion> get itemsReposicion => List.unmodifiable(
    _items.where((e) => e.varianteCambioId != null),
  );
  String get tipoSolicitud => _tipoSolicitud;
  double get diferencia => _diferencia;
  double get saldoFavor => _saldoFavor;
  List<Map<String, Object?>> get alternativas => _alternativas;
  ReturnRequestModel? get ultimaSolicitud => _ultimaSolicitud;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  bool get sinAlternativa => _sinAlternativa;

  /// [EXAMEN-2] B0.1: motivo de la devolución/reposición.
  String get motivo => _motivo;

  /// [EXAMEN-2] B0.1: medio de reembolso (`REEMBOLSO` o `SALDO_FAVOR`).
  String get medioReembolso => _medioReembolso;

  /// [EXAMEN-2] B0.1: las prendas de la venta original, para que el cajero
  /// elija cuáles devuelve sin teclear identificadores a mano.
  List<Map<String, Object?>> get itemsVentaOriginal {
    final items = _ventaOriginal?['items'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => Map<String, Object?>.from(e))
          .toList(growable: false);
    }
    return const <Map<String, Object?>>[];
  }

  /// [EXAMEN-2] B0.1: total a reembolsar de las prendas seleccionadas.
  double get totalReembolso => _items.fold<double>(
    0,
    (sum, e) => sum + e.precioUnitario * e.cantidad,
  );

  /// [EXAMEN-2] B0.1: hay al menos una prenda seleccionada.
  bool get tieneSeleccion => _items.isNotEmpty;

  /// [EXAMEN-2] B0.1: fecha límite de la venta original (RN-012).
  DateTime? get fechaLimiteVenta {
    final texto = _ventaOriginal?['fecha_limite_cambio']?.toString();
    if (texto == null || texto.isEmpty) return null;
    return DateTime.tryParse(texto);
  }

  /// Fija la venta original y evalúa el plazo RN-012.
  void setVentaOriginal(
    Map<String, Object?>? venta, {
    DateTime? fechaLimite,
  }) {
    _ventaOriginal = venta;
    // [EXAMEN-2] B0.1: al buscar otra venta, la selección previa se
    // descarta (las prendas pertenecen a la venta buscada).
    _items.clear();
    _alternativas = const [];
    _sinAlternativa = false;
    _recalcular();
    if (fechaLimite == null) {
      _plazoValido = true;
    } else {
      _plazoValido = _returnService.validarPlazoLocal(fechaLimite);
    }
    notifyListeners();
  }

  void setTipoSolicitud(String tipo) {
    _tipoSolicitud = tipo.toUpperCase();
    _recalcular();
    notifyListeners();
  }

  void agregarItem(LineaSeleccion linea) {
    _items.removeWhere(
      (e) =>
          e.varianteProductoId == linea.varianteProductoId &&
          e.varianteCambioId == linea.varianteCambioId,
    );
    _items.add(linea);
    _recalcular();
    notifyListeners();
  }

  /// [EXAMEN-2] B0.1: quita una prenda de la selección.
  void quitarItem(int varianteProductoId, {int? varianteCambioId}) {
    _items.removeWhere(
      (e) =>
          e.varianteProductoId == varianteProductoId &&
          (varianteCambioId == null || e.varianteCambioId == varianteCambioId),
    );
    _recalcular();
    notifyListeners();
  }

  /// [EXAMEN-2] B0.1: cambia la cantidad de una prenda seleccionada.
  void setCantidadItem(int varianteProductoId, int cantidad, {int? varianteCambioId}) {
    final indice = _items.indexWhere(
      (e) =>
          e.varianteProductoId == varianteProductoId &&
          (varianteCambioId == null || e.varianteCambioId == varianteCambioId),
    );
    if (indice < 0) return;
    final actual = _items[indice];
    if (cantidad <= 0) {
      _items.removeAt(indice);
    } else {
      _items[indice] = LineaSeleccion(
        varianteProductoId: actual.varianteProductoId,
        productoId: actual.productoId,
        productoNombre: actual.productoNombre,
        cantidad: cantidad,
        precioUnitario: actual.precioUnitario,
        varianteCambioId: actual.varianteCambioId,
        precioVarianteNueva: actual.precioVarianteNueva,
        detalleOrdenId: actual.detalleOrdenId,
      );
    }
    _recalcular();
    notifyListeners();
  }

  /// [EXAMEN-2] B0.1: motivo elegido por el cajero.
  void setMotivo(String motivo) {
    _motivo = motivo;
    notifyListeners();
  }

  /// [EXAMEN-2] B0.1: medio de reembolso elegido por el cajero.
  void setMedioReembolso(String medio) {
    _medioReembolso = medio;
    notifyListeners();
  }

  void limpiarItems() {
    _items.clear();
    _recalcular();
    notifyListeners();
  }

  /// [EXAMEN-2] B0.1.h: reinicia el estado compartido del provider al
  /// entrar a una pantalla de postventa (evita que las líneas agregadas en
  /// reposición se filtren a la devolución y viceversa).
  void reiniciarOperacion() {
    _items.clear();
    _ventaOriginal = null;
    _plazoValido = false;
    _alternativas = const [];
    _sinAlternativa = false;
    _error = null;
    _ultimaSolicitud = null;
    _motivo = MotivosDevolucion.tallaIncorrecta;
    _medioReembolso = 'REEMBOLSO';
    _recalcular();
    notifyListeners();
  }

  void _recalcular() {
    _diferencia = _items.fold<double>(
      0,
      (sum, e) =>
          sum + ((e.precioVarianteNueva ?? e.precioUnitario) - e.precioUnitario) * e.cantidad,
    );
    _saldoFavor = _diferencia < -0.005 ? -_diferencia : 0;
  }

  /// CU13: confirma la devolución pura offline y encola DEVOLUCION.
  Future<ReturnRequestModel?> confirmarDevolucionOffline({
    required String numeroComprobanteOrigen,
    required int sucursalId,
    // [EXAMEN-2] B0.1.e: si no se pasa, se usa el motivo seleccionado.
    String? motivo,
    bool? saldoFavor,
    DateTime? fechaCambioLimite,
    // [EXAMEN-2] B2.4: notificar al cliente la falta de alternativa de talla.
    bool notificarAlternativa = false,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _ultimaSolicitud = await _returnService.crearDevolucionOffline(
        numeroComprobanteOrigen: numeroComprobanteOrigen,
        sucursalId: sucursalId,
        motivo: motivo ?? _motivo,
        items: _items.map((e) => e.toLineaDevolucion()).toList(),
        // [EXAMEN-2] B0.1.f: el medio de reembolso elegido en la UI.
        saldoFavor: saldoFavor ?? (_medioReembolso == 'SALDO_FAVOR'),
        // [EXAMEN-2] B0.1.g: la fecha límite viene de la venta original; sin
        // ella el guard RN-012 del servicio queda inerte.
        fechaCambioLimite: fechaCambioLimite ?? fechaLimiteVenta,
        // [EXAMEN-2] B2.4: el backend notificara la falta de alternativa.
        notificarAlternativa: notificarAlternativa,
      );
      return _ultimaSolicitud;
    } catch (e) {
      _error = e.toString().replaceFirst('FormatException: ', '');
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// CU18: confirma la reposición offline y encola REPOSICION.
  Future<ReturnRequestModel?> confirmarReposicionOffline({
    required String numeroComprobanteOrigen,
    required int sucursalId,
    // [EXAMEN-2] B1.10.e: motivo seleccionado por el cajero.
    String? motivo,
    DateTime? fechaCambioLimite,
    // [EXAMEN-2] B1.10.h: medio de pago de la diferencia (offline ⇒ efectivo).
    String metodoPagoDiferencia = 'EFECTIVO',
    bool offline = false,
  }) async {
    _loading = true;
    _error = null;
    _sinAlternativa = false;
    notifyListeners();
    try {
      _ultimaSolicitud = await _returnService.crearReposicionOffline(
        numeroComprobanteOrigen: numeroComprobanteOrigen,
        sucursalId: sucursalId,
        motivo: motivo ?? _motivo,
        items: _items.map((e) => e.toLineaDevolucion()).toList(),
        // [EXAMEN-2] B0.1.g: fecha límite de la venta original (RN-012).
        fechaCambioLimite: fechaCambioLimite ?? fechaLimiteVenta,
        metodoPagoDiferencia: metodoPagoDiferencia,
        offline: offline,
      );
      return _ultimaSolicitud;
    } catch (e) {
      final texto = e.toString();
      _sinAlternativa = texto.contains('SIN_ALTERNATIVA');
      _error = texto.replaceFirst('FormatException: ', '');
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// CU18/RN-022: busca la talla mayor/menor en la sucursal u otras.
  Future<void> buscarAlternativaTalla({
    required int varianteId,
    int? sucursalId,
    String direccion = 'MAYOR',
  }) async {
    _loading = true;
    notifyListeners();
    try {
      _alternativas = await _returnService.buscarAlternativaTalla(
        varianteId: varianteId,
        sucursalId: sucursalId,
        direccion: direccion,
      );
      _sinAlternativa = _alternativas.isEmpty;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _alternativas = const [];
      _sinAlternativa = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// CU13/CU18: obtiene la solicitud guardada en local por su uuid.
  Future<ReturnRequestModel?> getSolicitudDesdeLocal(String uuid) =>
      _returnService.getSolicitudDesdeLocal(uuid);

  /// Delega la venta original al POS (central con red, local sin red).
  Future<Map<String, Object?>?> buscarVentaOriginal(
    String numeroComprobante, {
    bool enLinea = true,
  }) async {
    final pos = _posService;
    if (pos == null) return null;
    return pos.buscarVentaOriginal(
      numeroComprobante: numeroComprobante,
      enLinea: enLinea,
    );
  }

  /// Alias de la búsqueda de alternativas por talla.
  Future<void> buscarAlternativa(int varianteId, {int? sucursalId}) =>
      buscarAlternativaTalla(varianteId: varianteId, sucursalId: sucursalId);

  /// [EXAMEN-2] B0.3.c: producto de una variante en el catálogo local, para
  /// activar la validación de "misma prenda" (CU18).
  Future<int?> productoIdDeVariante(int varianteId) =>
      _returnService.productoIdDeVarianteLocal(varianteId);
}
