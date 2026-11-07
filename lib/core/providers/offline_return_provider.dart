// [EXAMEN-2] CU13/CU18: estado de la devolución y reposición offline.
// Orquesta PosService (venta original, plazo, reserva) y ReturnService
// (crear offline, alternativas) sin hablar con Dio ni con SQLite.
import 'package:flutter/material.dart';

import '../models/return_request_model.dart';
import '../services/pos_service.dart';
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
  }) : _returnService = returnService,
       _posService = posService;

  final ReturnService _returnService;
  final PosService? _posService;

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

  /// Fija la venta original y evalúa el plazo RN-012.
  void setVentaOriginal(
    Map<String, Object?>? venta, {
    DateTime? fechaLimite,
  }) {
    _ventaOriginal = venta;
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
    _items.add(linea);
    _recalcular();
    notifyListeners();
  }

  void limpiarItems() {
    _items.clear();
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
    String motivo = MotivosDevolucion.tallaIncorrecta,
    bool saldoFavor = false,
    DateTime? fechaCambioLimite,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _ultimaSolicitud = await _returnService.crearDevolucionOffline(
        numeroComprobanteOrigen: numeroComprobanteOrigen,
        sucursalId: sucursalId,
        motivo: motivo,
        items: _items.map((e) => e.toLineaDevolucion()).toList(),
        saldoFavor: saldoFavor,
        fechaCambioLimite: fechaCambioLimite,
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
    String motivo = MotivosDevolucion.tallaIncorrecta,
    DateTime? fechaCambioLimite,
  }) async {
    _loading = true;
    _error = null;
    _sinAlternativa = false;
    notifyListeners();
    try {
      _ultimaSolicitud = await _returnService.crearReposicionOffline(
        numeroComprobanteOrigen: numeroComprobanteOrigen,
        sucursalId: sucursalId,
        motivo: motivo,
        items: _items.map((e) => e.toLineaDevolucion()).toList(),
        fechaCambioLimite: fechaCambioLimite,
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
}
