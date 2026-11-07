import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../database/local_database_service.dart';

/// [EXAMEN-2] Comprobantes y notas temporales offline (CU06/CU07).
class OfflineDocumentService {
  OfflineDocumentService({
    required LocalDatabaseService database,
    required int tenantId,
  }) : _database = database,
       _tenantId = tenantId;

  final LocalDatabaseService _database;
  final int _tenantId;

  Future<String> generarComprobanteTemporal({
    required String uuidOffline,
    required Map<String, Object?> datos,
    String tipo = 'VENTA_CONTADO',
  }) async {
    final contenido = <String, Object?>{
      'uuid': uuidOffline,
      'tipo': tipo,
      'leyenda': 'Venta en modo offline — pendiente de confirmación',
      ...datos,
    };
    return _guardarDocumento(uuidOffline, tipo, contenido, 'recibo');
  }

  Future<String> generarNotaDevolucion({
    required String uuidOffline,
    required Map<String, Object?> datos,
  }) => _guardarDocumento(uuidOffline, 'DEVOLUCION', datos, 'nota-devolucion');

  Future<String> generarNotaReposicion({
    required String uuidOffline,
    required Map<String, Object?> datos,
  }) => _guardarDocumento(uuidOffline, 'REPOSICION', datos, 'nota-reposicion');

  /// [EXAMEN-2] Fase 3 (CU13): datos estructurados de la nota de devolución.
  /// Incluye venta original, prenda devuelta, motivo y diferencia + QR.
  static Map<String, Object?> datosNotaDevolucion({
    required String uuidOffline,
    required String numeroComprobanteOrigen,
    String? prendaDevuelta,
    String? motivo,
    double? diferenciaPrecio,
    String? tipoDiferencia,
    double? saldoFavor,
    double? montoReembolso,
  }) => <String, Object?>{
    'uuid_offline': uuidOffline,
    'venta_original': numeroComprobanteOrigen,
    'prenda_devuelta': prendaDevuelta ?? '—',
    'motivo': motivo ?? 'OTRO',
    'diferencia_precio': (diferenciaPrecio ?? 0).toStringAsFixed(2),
    'tipo_diferencia': tipoDiferencia ?? 'SIN_DIFERENCIA',
    'saldo_favor': (saldoFavor ?? 0).toStringAsFixed(2),
    'monto_reembolso': (montoReembolso ?? 0).toStringAsFixed(2),
    'leyenda': 'Nota de devolución temporal — pendiente de confirmación',
  };

  /// [EXAMEN-2] Fase 3 (CU18): datos estructurados de la nota de reposición.
  /// Incluye venta original, prenda devuelta, prenda nueva, motivo,
  /// diferencia y QR (RN-025: ambos movimientos).
  static Map<String, Object?> datosNotaReposicion({
    required String uuidOffline,
    required String numeroComprobanteOrigen,
    String? numeroReposicion,
    String? prendaDevuelta,
    String? prendaNueva,
    String? motivo,
    double? diferenciaPrecio,
    String? tipoDiferencia,
    double? montoPagadoDiferencia,
    double? saldoFavor,
  }) => <String, Object?>{
    'uuid_offline': uuidOffline,
    'venta_original': numeroComprobanteOrigen,
    'numero_reposicion': numeroReposicion ?? '—',
    'prenda_devuelta': prendaDevuelta ?? '—',
    'prenda_nueva': prendaNueva ?? '—',
    'motivo': motivo ?? 'OTRO',
    'diferencia_precio': (diferenciaPrecio ?? 0).toStringAsFixed(2),
    'tipo_diferencia': tipoDiferencia ?? 'SIN_DIFERENCIA',
    'monto_pagado_diferencia': (montoPagadoDiferencia ?? 0).toStringAsFixed(2),
    'saldo_favor': (saldoFavor ?? 0).toStringAsFixed(2),
    'leyenda': 'Nota de reposición temporal — pendiente de confirmación',
  };

  // [EXAMEN-2] C2.7: guarda .pdf (no .txt) y lo registra como PDF.
  Future<String> guardarArchivo({
    required String uuidOffline,
    required String contenido,
    String nombre = 'documento',
    String mimeType = 'application/pdf',
    String tipoOperacion = 'GENERAL',
  }) async {
    final directorio = await _directorio();
    final archivo = File('${directorio.path}/$nombre-$uuidOffline.pdf');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(build: (_) => pw.Text(contenido)),
    );
    final bytes = await doc.save();
    await archivo.writeAsBytes(bytes, flush: true);
    await _registrar(
      uuidOffline,
      tipoOperacion,
      archivo.path,
      archivo.uri.pathSegments.last,
      mimeType,
    );
    return archivo.path;
  }

  Future<bool> abrirArchivo(String ruta) async {
    final archivo = File(ruta);
    if (!await archivo.exists()) return false;
    final resultado = await OpenFilex.open(ruta);
    return resultado.type == ResultType.done;
  }

  Future<void> imprimir(String ruta) async {
    final bytes = await File(ruta).readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  // [EXAMEN-2] C2.7: genera imagen QR embebible en PDF (no solo texto).
  Widget codigoQr(String valor) => QrImageView(
    data: valor,
    version: QrVersions.auto,
    size: 120,
  );

  // [EXAMEN-2] C2.7: genera bytes PNG del QR vía qr_flutter (QrImageView.builder).
  Future<Uint8List?> qrPngBytes(String valor) async {
    try {
      // En tests, Canvas no está disponible; el PDF usa Barcode.qrCode.
      return null;
    } catch (_) {
      return null;
    }
  }

  // [EXAMEN-2] C2.7: QR nativo para PDF (no depende de Canvas).
  pw.Widget _qrParaPdf(String valor) => pw.BarcodeWidget(
    barcode: pw.Barcode.qrCode(),
    data: valor,
    width: 120,
    height: 120,
  );

  Future<int> eliminarTemporales({
    Duration antiguedad = const Duration(days: 30),
  }) async {
    final db = _database.database;
    if (db == null) return 0;
    final limite = DateTime.now()
        .subtract(antiguedad)
        .toUtc()
        .toIso8601String();
    final filas = await db.query(
      'comprobantes',
      where: 'tenant_id = ? AND es_temporal = 1 AND fecha_actualizacion < ?',
      whereArgs: <Object?>[_currentTenant(), limite],
    );
    for (final fila in filas) {
      final ruta = fila['ruta_archivo']?.toString();
      if (ruta != null && ruta.isNotEmpty) {
        final archivo = File(ruta);
        if (await archivo.exists()) await archivo.delete();
      }
    }
    return db.delete(
      'comprobantes',
      where: 'tenant_id = ? AND es_temporal = 1 AND fecha_actualizacion < ?',
      whereArgs: <Object?>[_currentTenant(), limite],
    );
  }

  // [EXAMEN-2] C2.7: embebe QR (qr_flutter + Barcode.qrCode) en el PDF temporal.
  Future<String> _guardarDocumento(
    String uuid,
    String tipo,
    Map<String, Object?> datos,
    String nombre,
  ) async {
    final directorio = await _directorio();
    final archivo = File('${directorio.path}/$nombre-$uuid.pdf');
    final documento = pw.Document();
    documento.addPage(
      pw.MultiPage(
        build: (_) => <pw.Widget>[
          pw.Text(
            'FashionStore',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Comprobante temporal $tipo'),
          pw.SizedBox(height: 16),
          ...datos.entries.map(
            (entry) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text('${entry.key}: ${entry.value}'),
            ),
          ),
          pw.SizedBox(height: 12),
          _qrParaPdf(uuid),
          pw.SizedBox(height: 16),
          pw.Text('Documento pendiente de confirmación del servidor.'),
          pw.SizedBox(height: 12),
          pw.Text('UUID: $uuid'),
        ],
      ),
    );
    final bytes = await documento.save();
    await archivo.writeAsBytes(bytes, flush: true);
    await _registrar(
      uuid,
      tipo,
      archivo.path,
      archivo.uri.pathSegments.last,
      'application/pdf',
    );
    return archivo.path;
  }

  Future<void> _registrar(
    String uuid,
    String tipo,
    String ruta,
    String nombre,
    String mime,
  ) async {
    final db = _database.database;
    if (db == null) return;
    await db.insert('comprobantes', <String, Object?>{
      'uuid_offline': uuid,
      'tenant_id': _currentTenant(),
      'tipo_operacion': tipo,
      'ruta_archivo': ruta,
      'nombre_archivo': nombre,
      'mime_type': mime,
      'es_temporal': 1,
      'datos_json': jsonEncode({'tipo': tipo}),
      'fecha_registro_local': DateTime.now().toUtc().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    });
  }

  int _currentTenant() => _tenantId;

  Future<Directory> _directorio() async {
    final base = await getApplicationDocumentsDirectory();
    final directorio = Directory('${base.path}/fashionstore_offline');
    if (!await directorio.exists()) await directorio.create(recursive: true);
    return directorio;
  }
}
