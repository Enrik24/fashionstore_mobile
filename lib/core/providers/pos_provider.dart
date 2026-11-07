import 'package:flutter/material.dart';

import '../models/phase2_models.dart';
import '../models/product_model.dart';
import '../services/pos_service.dart';
import '../services/offline_document_service.dart';

/// [EXAMEN-2] Estado de la venta de contado offline (CU07).
class PosProvider extends ChangeNotifier {
  PosProvider({
    required PosService service,
    OfflineDocumentService? documentService,
  }) : _service = service,
       _documentService = documentService;

  final PosService _service;
  final OfflineDocumentService? _documentService;
  List<ProductModel> _searchResults = const [];
  LocalSaleModel? _lastSale;
  bool _loading = false;
  String? _error;
  String? _receiptPath;

  List<ProductModel> get searchResults => _searchResults;
  LocalSaleModel? get lastSale => _lastSale;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  String? get receiptPath => _receiptPath;
  double get total => _service.calcularTotalLocal();

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

  void addProduct({
    required int varianteProductoId,
    required int cantidad,
    required double precioUnitario,
    required String nombre,
    int stockConocido = 0,
  }) {
    _service.agregarProducto(
      varianteProductoId: varianteProductoId,
      cantidad: cantidad,
      precioUnitario: precioUnitario,
      nombre: nombre,
      stockConocido: stockConocido,
    );
    notifyListeners();
  }

  double changeFor(double received) => _service.calcularCambio(received);

  Future<LocalSaleModel?> confirm({
    required int sucursalId,
    required int cajeroId,
    required double montoRecibido,
    String? clienteId,
  }) async {
    _loading = true;
    notifyListeners();
    try {
      _lastSale = await _service.confirmarVentaOffline(
        sucursalId: sucursalId,
        cajeroId: cajeroId,
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
