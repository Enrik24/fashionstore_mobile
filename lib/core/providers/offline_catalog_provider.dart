import 'package:flutter/material.dart';

import '../models/api_response.dart';
import '../models/phase2_models.dart';
import '../models/product_model.dart';
import '../services/offline_catalog_service.dart';
import '../services/storage_quota_service.dart';
import '../services/storage_service.dart';

/// [EXAMEN-2] Estado del catálogo descargable y su sello (CU05).
class OfflineCatalogProvider extends ChangeNotifier {
  OfflineCatalogProvider({
    required OfflineCatalogService service,
    StorageService? storageService,
  }) : _service = service,
       _storageService = storageService;

  final OfflineCatalogService _service;
  // [EXAMEN-2] B1.1.j: el sello de descarga se persiste para que el widget
  // "datos actualizados al ..." pueda mostrarlo sin consultar la base.
  final StorageService? _storageService;
  List<ProductModel> _products = const [];
  OfflineDownloadStatus _status = const OfflineDownloadStatus();
  bool _loadingLocal = false;
  bool _downloading = false;
  String? _error;
  // [EXAMEN-2] B1.1.f: confirmación de la descarga completada.
  String? _mensajeConfirmacion;
  // [EXAMEN-2] B1.1.i: cuando el paquete no cabe, se ofrece la descarga
  // selectiva con estos N productos.
  int? _productosSelectivos;
  // [EXAMEN-2] Ola 2: el error pertenece a una **operación** concreta. Una
  // carga local posterior no debe borrar el error de una descarga fallida
  // (si no, el mensaje "Incompleto - requiere reconexión" desaparecía).
  String? _errorOrigen;

  List<ProductModel> get products => _products;
  OfflineDownloadStatus get status => _status;
  bool get isLoading => _loadingLocal || _downloading;
  bool get isLoadingLocal => _loadingLocal;
  bool get isDownloading => _downloading;
  String? get errorMessage => _error;
  DateTime? get selloDescarga => _status.sello;

  /// [EXAMEN-2] B1.1.f: "Datos descargados. Última actualización: [hora]".
  String? get mensajeConfirmacion => _mensajeConfirmacion;

  /// [EXAMEN-2] B1.1.i: hay que ofrecer una descarga selectiva.
  bool get requiereDescargaSelectiva => _productosSelectivos != null;

  /// [EXAMEN-2] B1.1.i: cuántos productos caben en el espacio disponible.
  int? get productosSelectivos => _productosSelectivos;

  // [EXAMEN-2] C2.4: progreso/espacio para UI de descarga (RF-030).
  double get progreso {
    if (_downloading || _status.enProgreso) return 0.5;
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

  Future<void> descargarPaquete({
    int? sucursalId,
    // [EXAMEN-2] B1.1.i: descarga selectiva (N productos más vendidos).
    int? limiteProductos,
  }) async {
    if (_downloading) return;
    _downloading = true;
    _error = null;
    _errorOrigen = 'descarga';
    _mensajeConfirmacion = null;
    notifyListeners();
    try {
      // [EXAMEN-2] CU05/RNF-06: si el servidor no responde, la descarga no
      // puede quedar cargando para siempre; se conserva el error y el estado
      // anterior del catálogo local.
      _status = await _service
          .descargarPaquete(
            sucursalId: sucursalId,
            limiteProductos: limiteProductos,
          )
          .timeout(const Duration(seconds: 60));
      _products = await _service.catalogoLocal();
      _error = null;
      _productosSelectivos = null;
      // [EXAMEN-2] B1.1.f: confirmación explícita de la descarga.
      final sello = _status.sello;
      _mensajeConfirmacion = sello == null
          ? 'Datos descargados.'
          : 'Datos descargados. Última actualización: '
                '${_horaLegible(sello)}';
      // [EXAMEN-2] B1.1.j: el sello se persiste para el widget de datos
      // actualizados (antes nunca se escribía y el sello no se veía).
      if (sello != null) {
        try {
          await _storageService?.saveDownloadStamp(sello);
        } catch (_) {
          // El sello persistido es un extra: su fallo no debe tumbar la
          // descarga (el `sello` en memoria ya está actualizado).
        }
      }
    } on CuotaInsuficienteException catch (cuota) {
      // [EXAMEN-2] B1.1.i: se ofrece la descarga selectiva.
      _productosSelectivos = cuota.maxProductos;
      _error =
          'Espacio local insuficiente (RNF-14): se necesitan ~${cuota.estimadoBytes} '
          'bytes y hay ${cuota.disponibleBytes} disponibles. '
          'Puedes descargar sólo los ${cuota.maxProductos} productos más vendidos.';
    } catch (error) {
      _error = _mensajeLegible(error);
      _status = _service.estadoDescarga.copyWith(
        enProgreso: false,
        incompleto: true,
        error: _error,
      );
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// [EXAMEN-2] B1.1.f: hora legible para la confirmación de descarga.
  String _horaLegible(DateTime sello) {
    final local = sello.toLocal();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(local.day)}/${dos(local.month)}/${local.year} '
        '${dos(local.hour)}:${dos(local.minute)}';
  }

  /// [EXAMEN-2] B2.1: actualización **incremental** de los datos locales
  /// (catálogo, stock, clientes y promociones) sin bajar el paquete completo.
  Future<Map<String, int>> actualizarDatos({int? sucursalId}) async {
    _downloading = true;
    _error = null;
    notifyListeners();
    try {
      final resultado = await _service.actualizarDatos(sucursalId: sucursalId);
      _products = await _service.catalogoLocal();
      _mensajeConfirmacion = 'Datos actualizados.';
      return resultado;
    } catch (error) {
      _error = _mensajeLegible(error);
      return const <String, int>{};
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// Traduce el fallo de red/servidor a un mensaje útil para el cajero.
  String _mensajeLegible(Object error) {
    final texto = error.toString();
    final errorBaseDatos = _service.errorBaseDatos;
    if (errorBaseDatos != null) {
      return 'No se pudo abrir la base local cifrada. Reinicia la aplicación o '
          'revisa el almacenamiento del dispositivo. Detalle: $errorBaseDatos';
    }
    if (error is ApiException && error.statusCode != null) {
      final codigo = error.statusCode!;
      if (codigo >= 500) {
        return 'El servidor no está disponible ahora mismo (HTTP $codigo). '
            'Intenta más tarde.';
      }
      if (codigo == 401 || codigo == 403) {
        return 'Tu sesión no tiene permiso para descargar el paquete. '
            'Inicia sesión nuevamente.';
      }
    }
    if (texto.contains('TimeoutException') || texto.contains('tiempo')) {
      return 'El servidor no respondió a tiempo. Revisa tu conexión e intenta de nuevo.';
    }
    if (texto.contains('503') ||
        texto.contains('502') ||
        texto.contains('500')) {
      return 'El servidor no está disponible ahora mismo. Intenta más tarde.';
    }
    return texto;
  }

  Future<void> cargarLocal() async {
    if (_loadingLocal) return;
    _loadingLocal = true;
    notifyListeners();
    try {
      _products = await _service.catalogoLocal();
      // [EXAMEN-2] Ola 2: sólo se limpia el error si es **propio**; el error de
      // una descarga fallida se conserva.
      if (_errorOrigen != 'descarga') {
        _error = null;
        _errorOrigen = null;
      }
    } catch (error) {
      _error = _mensajeLegible(error);
      _errorOrigen = 'carga';
    } finally {
      _loadingLocal = false;
      notifyListeners();
    }
  }

  Future<List<ProductModel>> buscar(String texto) =>
      _service.buscarLocal(texto);
}
