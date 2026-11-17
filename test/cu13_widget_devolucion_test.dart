// [EXAMEN-2] Ola 1 / B0.1: flujo de devolución offline **desde la app**.
//
// Este test cubre el hueco que impedía completar CU13: la pantalla
// `PosReturnPage` nunca llamaba a `OfflineReturnProvider.agregarItem`, por lo
// que `_items` quedaba vacío y `ReturnService.crearDevolucionOffline` lanzaba
// `FormatException('La devolución exige al menos una prenda')`.
//
// Los tests de servicio (`cu13_devolucion_offline_test.dart`) pasaban porque
// nunca ejercitaban el widget.
//
// -----------------------------------------------------------------------------
// Nota sobre `sqflite_common_ffi` en `testWidgets`:
// el isolate de la base FFI no debe tocarse desde la zona *fake-async* del
// binding; si se hace, el runner se queda colgado en el teardown. Por eso
// **todo** el trabajo con la base (abrir, sembrar, las consultas que dispara
// la pantalla y el cierre) va dentro de `tester.runAsync()`, y el render se
// hace con `pump()` fuera de él (el cursor parpadeante del `TextField` impide
// usar `pumpAndSettle()`).
import 'dart:async';

import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/providers/offline_return_provider.dart';
import 'package:fashionstore_mobile/core/services/offline_document_service.dart';
import 'package:fashionstore_mobile/core/services/offline_queue_service.dart';
import 'package:fashionstore_mobile/core/services/pos_service.dart';
import 'package:fashionstore_mobile/core/services/return_service.dart';
import 'package:fashionstore_mobile/features/pos/return/pos_return_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fase3_helpers.dart';

const String _comprobante = 'VTA-OFF-20260101-ABC123';

/// Siembra una venta offline con su detalle y su plazo vigente.
Future<void> _sembrarVenta(LocalDatabaseService db) async {
  final ahora = DateTime.now().toUtc().toIso8601String();
  await db.database!.insert('ventas_locales', <String, Object?>{
    'uuid_offline': 'uuid-venta-widget',
    'tenant_id': tenantFase3,
    'sucursal_id': 1,
    'estado': 'PENDIENTE_SINCRONIZACION',
    'estado_sincronizacion': 'PENDIENTE_SINCRONIZACION',
    'subtotal': 100,
    'impuestos': 0,
    'total': 100,
    'monto_recibido': 100,
    'cambio': 0,
    'metodo_pago': 'EFECTIVO',
    'es_offline': 1,
    'numero_comprobante': _comprobante,
    'numero_comprobante_generado': _comprobante,
    'fecha_limite_cambio':
        DateTime.now().toUtc().add(const Duration(days: 5)).toIso8601String(),
    'fecha_registro_local': ahora,
    'fecha_actualizacion': ahora,
  });
  await db.database!.insert('items_venta_local', <String, Object?>{
    'uuid_offline': 'uuid-venta-widget',
    'tenant_id': tenantFase3,
    'variante_producto_id': 101,
    'cantidad': 2,
    'precio_unitario': 100,
    'subtotal': 200,
    'producto_nombre': 'Blusa',
    'stock_conocido': 10,
    'fecha_actualizacion': ahora,
  });
}

/// Monta la pantalla con la base y el provider ya construidos.
Future<void> _montar(
  WidgetTester tester,
  LocalDatabaseService db,
  OfflineReturnProvider provider,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OfflineReturnProvider>.value(value: provider),
        Provider<OfflineDocumentService>(
          create: (_) => OfflineDocumentService(
            database: db,
            tenantId: tenantFase3,
          ),
        ),
      ],
      child: const MaterialApp(home: PosReturnPage()),
    ),
  );
  await tester.pump();
}

/// [EXAMEN-2] Ola 4: espera **determinista** a que una condición se cumpla.
///
/// Sustituye a los `Future.delayed(...)` fijos: bajo carga (suite completa)
/// el delay no bastaba y la prueba leía la base antes de que terminara la
/// operación (fallo intermitente).
Future<void> _esperarA(
  FutureOr<bool> Function() condicion, {
  Duration intervalo = const Duration(milliseconds: 25),
  Duration timeout = const Duration(seconds: 10),
}) async {
  final limite = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(limite)) {
    if (await condicion()) return;
    await Future<void>.delayed(intervalo);
  }
  fail('La condición no se cumplió dentro de ${timeout.inSeconds}s');
}

void main() {
  testWidgets('CU13: el flujo de devolución se completa desde la app', (
    tester,
  ) async {
    mockPathProvider();
    late LocalDatabaseService db;
    late OfflineReturnProvider provider;

    await tester.runAsync(() async {
      db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      await _sembrarVenta(db);
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-widget',
        usuarioId: 42,
      );
      provider = OfflineReturnProvider(
        returnService: ReturnService(
          database: db,
          tenantId: tenantFase3,
          queue: queue,
          usuarioId: 42,
        ),
        // Sin `apiService`: la venta original se resuelve en la base local.
        posService: PosService(
          database: db,
          tenantId: tenantFase3,
          queue: queue,
        ),
      );
    });

    await _montar(tester, db, provider);

    // 1) El cajero busca la venta por su número de comprobante.
    //
    // [EXAMEN-2] Ola 4: **no** se usa un `delay` fijo. Bajo carga (suite
    // completa) los 300 ms no bastaban y la prueba leía la base antes de que
    // terminara la consulta ⇒ `operaciones` salía vacía. Se espera a que la
    // búsqueda termine de verdad.
    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField).first, _comprobante);
      await tester.tap(find.byIcon(Icons.search));
      await _esperarA(() => provider.ventaOriginal != null);
    });
    await tester.pump();

    // 2) La pantalla lista las prendas de la venta original.
    expect(find.text('Blusa'), findsOneWidget);
    expect(find.textContaining('Cantidad: 2'), findsOneWidget);

    // 3) Sin selección, el botón de confirmar está deshabilitado.
    final boton = find.widgetWithText(
      FilledButton,
      'Confirmar devolución offline',
    );
    expect(tester.widget<FilledButton>(boton).onPressed, isNull);

    // 4) El cajero marca la prenda a devolver.
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    // 5) El resumen real del reembolso se muestra (2 x 100).
    expect(provider.totalReembolso, 200);
    // El resumen está al final de la lista: se hace scroll para verificarlo.
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pump();
    expect(find.textContaining('Reembolso estimado: 200.00'), findsOneWidget);
    expect(tester.widget<FilledButton>(boton).onPressed, isNotNull);

    // 6) Confirmar: la operación se encola y se genera la nota.
    await tester.runAsync(() async {
      await tester.tap(boton);
      // [EXAMEN-2] Ola 4: se espera a que la operación quede **encolada** y
      // a que se registre la nota (el PDF se genera **después** del encolado,
      // así que esperar sólo a la operación no basta).
      await _esperarA(() async {
        final filas = await db.database!.query(
          'operaciones',
          where: 'tenant_id = ?',
          whereArgs: <Object?>[tenantFase3],
        );
        if (filas.isEmpty) return false;
        final notas = await db.database!.query(
          'comprobantes',
          where: 'tipo_operacion = ?',
          whereArgs: <Object?>['DEVOLUCION'],
        );
        return notas.isNotEmpty;
      });
    });
    await tester.pump();

    await tester.runAsync(() async {
      final operaciones = await db.database!.query(
        'operaciones',
        where: 'tenant_id = ?',
        whereArgs: <Object?>[tenantFase3],
      );
      expect(operaciones, hasLength(1));
      expect(operaciones.single['tipo_operacion'], 'DEVOLUCION');
      expect(operaciones.single['usuario_id'], 42);

      final solicitudes = await db.database!.query(
        'devoluciones_locales',
        where: 'tenant_id = ?',
        whereArgs: <Object?>[tenantFase3],
      );
      expect(solicitudes, hasLength(1));
      expect(solicitudes.single['estado'], 'PENDIENTE_SINCRONIZACION');
      expect(solicitudes.single['numero_comprobante_origen'], _comprobante);

      // La prenda devuelta reingresa al inventario. Sin sesión POS la
      // devolución se registra en la sucursal 0, por lo que la variante
      // puede quedar repartida en más de una fila de `stock`.
      final stock = await db.database!.query(
        'stock',
        where: 'variante_id = ? AND tenant_id = ?',
        whereArgs: <Object?>[101, tenantFase3],
      );
      final total = stock.fold<int>(
        0,
        (suma, fila) => suma + ((fila['cantidad'] as num?)?.toInt() ?? 0),
      );
      expect(total, 12); // 10 originales + 2 devueltas

      // El libro de movimientos registra la entrada (RN-021).
      final movimientos = await db.database!.query(
        'movimientos_inventario',
        where: 'tenant_id = ?',
        whereArgs: <Object?>[tenantFase3],
      );
      expect(movimientos, hasLength(1));
      expect(movimientos.single['tipo'], 'DEVOLUCION');

      // La nota de devolución se generó.
      final comprobantes = await db.database!.query(
        'comprobantes',
        where: 'tipo_operacion = ?',
        whereArgs: <Object?>['DEVOLUCION'],
      );
      expect(comprobantes, hasLength(1));

      await db.cerrar();
    });
  });

  testWidgets('CU13: sin prendas seleccionadas se informa del error', (
    tester,
  ) async {
    mockPathProvider();
    late LocalDatabaseService db;
    late OfflineReturnProvider provider;

    await tester.runAsync(() async {
      db = await abrirBaseFase3();
      await sembrarCatalogo(db);
      await _sembrarVenta(db);
      final queue = OfflineQueueService(
        database: db,
        tenantId: tenantFase3,
        dispositivoId: 'device-widget-2',
        usuarioId: 42,
      );
      provider = OfflineReturnProvider(
        returnService: ReturnService(
          database: db,
          tenantId: tenantFase3,
          queue: queue,
          usuarioId: 42,
        ),
        posService: PosService(
          database: db,
          tenantId: tenantFase3,
          queue: queue,
        ),
      );
    });

    await _montar(tester, db, provider);

    // Sin seleccionar prendas, `confirmarDevolucionOffline` falla con un
    // mensaje legible (no una traza cruda).
    await tester.runAsync(() async {
      await provider.confirmarDevolucionOffline(
        numeroComprobanteOrigen: _comprobante,
        sucursalId: 1,
      );
    });
    await tester.pump();
    expect(provider.errorMessage, contains('al menos una prenda'));

    await tester.runAsync(() => db.cerrar());
  });
}
