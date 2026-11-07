// [EXAMEN-2] CU13: nota de devolución local (campos + PDF con QR).
import 'dart:io';

import 'package:fashionstore_mobile/core/services/offline_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fase3_helpers.dart';

void main() {
  test('datos de la nota: venta, prenda devuelta, motivo y diferencia', () {
    final datos = OfflineDocumentService.datosNotaDevolucion(
      uuidOffline: 'uuid-nota-1',
      numeroComprobanteOrigen: 'FAC-2001',
      prendaDevuelta: 'Blusa M',
      motivo: 'TALLA_INCORRECTA',
      diferenciaPrecio: 100,
      tipoDiferencia: 'SIN_DIFERENCIA',
      montoReembolso: 100,
    );
    expect(datos['venta_original'], 'FAC-2001');
    expect(datos['prenda_devuelta'], 'Blusa M');
    expect(datos['motivo'], 'TALLA_INCORRECTA');
    expect(datos['monto_reembolso'], '100.00');
    expect(datos['uuid_offline'], 'uuid-nota-1');
    expect(
      datos['leyenda'],
      contains('pendiente de confirmación'),
    );
  });

  test('genera PDF temporal con QR y lo registra en comprobantes', () async {
    mockPathProvider();
    final servicios = await crearServicios();
    final docs = OfflineDocumentService(
      database: servicios.db,
      tenantId: tenantFase3,
    );
    final ruta = await docs.generarNotaDevolucion(
      uuidOffline: 'uuid-nota-2',
      datos: OfflineDocumentService.datosNotaDevolucion(
        uuidOffline: 'uuid-nota-2',
        numeroComprobanteOrigen: 'FAC-2002',
        motivo: 'OTRO',
        diferenciaPrecio: 50,
        tipoDiferencia: 'SALDO_FAVOR',
        saldoFavor: 50,
      ),
    );
    expect(ruta, endsWith('.pdf'));
    expect(await File(ruta).exists(), isTrue);
    final filas = await servicios.db.database!.query(
      'comprobantes',
      where: 'uuid_offline = ?',
      whereArgs: ['uuid-nota-2'],
    );
    expect(filas, hasLength(1));
    expect(filas.single['tipo_operacion'], 'DEVOLUCION');
    expect(filas.single['es_temporal'], 1);
    expect(filas.single['ruta_archivo'], ruta);
    await servicios.db.cerrar();
  });
}
