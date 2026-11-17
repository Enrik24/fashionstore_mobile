import 'package:flutter/material.dart';

import '../models/phase2_models.dart';
import '../models/product_model.dart';
import '../services/pos_service.dart';
import '../services/offline_document_service.dart';
import '../services/pos_sesion_service.dart';

/// [EXAMEN-2] Estado de la venta de contado offline (CU07).
class PosProvider extends ChangeNotifier {
  PosProvider({
    required PosService service,
    OfflineDocumentService? documentService,
    // [EXAMEN-2] CU07/CU13/CU18: sucursal y cajero de la sesión.
    PosSesionService? sesion,
  }) : _service = service,
       _documentService = documentService,
       _sesion = sesion;

  final PosService _service;
  final OfflineDocumentService? _documentService;
  final PosSesionService? _sesion;
  List<ProductModel> _searchResults = const [];
  LocalSaleModel? _lastSale;
  bool _loading = false;
  String? _error;
  String? _receiptPath;
  int? _sucursalActual;
  int? _cajeroActual;

  List<ProductModel> get searchResults => _searchResults;
  LocalSaleModel? get lastSale => _lastSale;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  String? get receiptPath => _receiptPath;
  // [EXAMEN-2] CU07/CU13/CU18: sucursal/cajero resueltos de la sesión.
  int? get sucursalActual => _sucursalActual;
  int get cajeroActual => _cajeroActual ?? _sesion?.cajeroId ?? 0;

  /// Resuelve sucursal y cajero desde la sesión (persistencia + paquete
  /// offline). Debe llamarse al entrar al flujo POS.
  Future<int> resolverSucursalActual() async {
    final sesion = _sesion;
    if (sesion == null) return _sucursalActual ?? 0;
    _sucursalActual = await sesion.resolverSucursalId();
    _cajeroActual = sesion.cajeroId;
    notifyListeners();
    return _sucursalActual ?? 0;
  }
  double get total => _service.calcularTotalLocal();

  /// [EXAMEN-2] B1.3.a: líneas de la venta en curso.
  List<Map<String, Object?>> get lineas => _service.lineasVenta;

  /// [EXAMEN-2] B1.3.a: cantidad agregada de una variante.
  int cantidadDe(int varianteProductoId) =>
      _service.cantidadDe(varianteProductoId);

  void startSale() {
    _service.iniciarVenta();
    _lastSale = null;
    notifyListeners();
  }

  Future<void> search(String text) async {
    _loading = true;
    notifyListeners();
    try {
      _searchResults = await _service.buscarVarianteLocal(text);
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// [EXAMEN-2] B0.2.e / B1.3.e: agrega una prenda a la venta.
  ///
  /// Si la variante **no está en el catálogo local descargado**, la venta se
  /// bloquea con un mensaje que indica conectar y descargar los datos
  /// (CU07, flujo alterno 1). Antes se aceptaba cualquier identificador y el
  /// total salía con precio 0.
  Future<bool> addProduct({
    required int varianteProductoId,
    required int cantidad,
    required double precioUnitario,
    required String nombre,
    int stockConocido = 0,
    // [EXAMEN-2] B1.3.f: forzar la venta aunque el stock local sea crítico.
    bool forzar = false,
  }) async {
    if (!forzar && !await _service.varianteEnCatalogoLocal(varianteProductoId)) {
      _error =
          'El producto no está en el catálogo descargado. '
          'Conéctate y descarga los datos actualizados para venderlo.';
      notifyListeners();
      return false;
    }
    _error = null;
    _service.agregarProducto(
      varianteProductoId: varianteProductoId,
      cantidad: cantidad,
      precioUnitario: precioUnitario,
      nombre: nombre,
      stockConocido: stockConocido,
      forzar: forzar,
    );
    notifyListeners();
    return true;
  }

  double changeFor(double received) => _service.calcularCambio(received);

  Future<LocalSaleModel?> confirm({
    // [EXAMEN-2] CU07: por defecto usa la sucursal/cajero de la sesión.
    int? sucursalId,
    int? cajeroId,
    required double montoRecibido,
    String? clienteId,
  }) async {
    final sucursal = sucursalId ?? _sucursalActual ?? 0;
    final cajero = cajeroId ?? cajeroActual;
    _loading = true;
    notifyListeners();
    try {
      _lastSale = await _service.confirmarVentaOffline(
        sucursalId: sucursal,
        cajeroId: cajero,
        montoRecibido: montoRecibido,
        clienteId: clienteId,
      );
      final comprobante = await _service.comprobanteTemporal(
        _lastSale!.uuidOffline,
      );
      if (comprobante != null) {
        _receiptPath = await _documentService?.generarComprobanteTemporal(
          uuidOffline: _lastSale!.uuidOffline,
          datos: comprobante,
        );
      }
      _error = null;
      return _lastSale;
    } catch (error) {
      _error = error.toString();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
