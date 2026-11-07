import 'package:flutter/material.dart';

import '../models/phase2_models.dart';
import '../models/product_model.dart';
import '../services/offline_catalog_service.dart';

/// [EXAMEN-2] Estado del catálogo descargable y su sello (CU05).
class OfflineCatalogProvider extends ChangeNotifier {
  OfflineCatalogProvider({required OfflineCatalogService service})
    : _service = service;

  final OfflineCatalogService _service;
  List<ProductModel> _products = const [];
  OfflineDownloadStatus _status = const OfflineDownloadStatus();
  bool _loading = false;
  String? _error;

  List<ProductModel> get products => _products;
  OfflineDownloadStatus get status => _status;
  bool get isLoading => _loading;
  String? get errorMessage => _error;
  DateTime? get selloDescarga => _status.sello;

  // [EXAMEN-2] C2.4: progreso/espacio para UI de descarga (RF-030).
  double get progreso {
    if (_loading || _status.enProgreso) return 0.5;
    if (_status.incompleto) return 0.0;
    if (_status.sello != null) return 1.0;
    return 0.0;
  }

  int? _espacioUsadoBytes;
  int? get espacioUsadoBytes => _espacioUsadoBytes;
  String get espacioUsado => _espacioUsadoBytes == null
      ? '—'
      : '${(_espacioUsadoBytes! / 1048576).toStringAsFixed(1)} MB';

  Future<void> refrescarEspacio() async {
    _espacioUsadoBytes = await _service.espacioUsado();
    notifyListeners();
  }

  // [EXAMEN-2] C2.4: limpiar catálogo local del tenant.
  Future<void> limpiar() async {
    await _service.limpiarCatalogo();
    _products = const [];
    _status = const OfflineDownloadStatus();
    _espacioUsadoBytes = null;
    notifyListeners();
  }

  Future<void> descargarPaquete({int? sucursalId}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _status = await _service.descargarPaquete(sucursalId: sucursalId);
      _products = await _service.catalogoLocal();
    } catch (error) {
      _error = error.toString();
      _status = _service.estadoDescarga;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> cargarLocal() async {
    _loading = true;
    notifyListeners();
    try {
      _products = await _service.catalogoLocal();
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<ProductModel>> buscar(String texto) =>
      _service.buscarLocal(texto);
}
