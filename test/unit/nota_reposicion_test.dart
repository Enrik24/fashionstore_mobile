// [EXAMEN-2] CU18: nota de reposición local (campos + PDF con QR).
import 'dart:io';

import 'package:fashionstore_mobile/core/services/offline_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fase3_helpers.dart';

void main() {
  test(
    'datos de la nota: venta, prendas, motivo, diferencia y número REP-',
    () {
      final datos = OfflineDocumentService.datosNotaReposicion(
        uuidOffline: 'uuid-nota-rep-1',
        numeroComprobanteOrigen: 'FAC-3001',
        numeroReposicion: 'REP-LOCAL-ABCDEF12',
        prendaDevuelta: 'Blusa M',
        prendaNueva: 'Blusa L',
        motivo: 'TALLA_INCORRECTA',
        diferenciaPrecio: 20,
        tipoDiferencia: 'COBRO',
        montoPagadoDiferencia: 20,
      );
      expect(datos['venta_original'], 'FAC-3001');
      expect(datos['numero_reposicion'], 'REP-LOCAL-ABCDEF12');
      expect(datos['prenda_devuelta'], 'Blusa M');
      expect(datos['prenda_nueva'], 'Blusa L');
      expect(datos['motivo'], 'TALLA_INCORRECTA');
      expect(datos['diferencia_precio'], '20.00');
      expect(datos['tipo_diferencia'], 'COBRO');
      expect(datos['monto_pagado_diferencia'], '20.00');
    },
  );

  test('genera PDF temporal con QR y lo registra en comprobantes', () async {
    mockPathProvider();
    final servicios = await crearServicios();
    final docs = OfflineDocumentService(
      database: servicios.db,
      tenantId: tenantFase3,
    );
    final ruta = await docs.generarNotaReposicion(
      uuidOffline: 'uuid-nota-rep-2',
      datos: OfflineDocumentService.datosNotaReposicion(
        uuidOffline: 'uuid-nota-rep-2',
        numeroComprobanteOrigen: 'FAC-3002',
        numeroReposicion: 'REP-LOCAL-12345678',
        motivo: 'TALLA_INCORRECTA',
        diferenciaPrecio: 0,
        tipoDiferencia: 'SIN_DIFERENCIA',
      ),
    );
    expect(ruta, endsWith('.pdf'));
    expect(await File(ruta).exists(), isTrue);
    final filas = await servicios.db.database!.query(
      'comprobantes',
      where: 'uuid_offline = ?',
      whereArgs: ['uuid-nota-rep-2'],
    );
    expect(filas, hasLength(1));
    expect(filas.single['tipo_operacion'], 'REPOSICION');
    expect(filas.single['es_temporal'], 1);
    expect(filas.single['ruta_archivo'], ruta);
    await servicios.db.cerrar();
  });
}
