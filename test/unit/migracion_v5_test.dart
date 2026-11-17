// [EXAMEN-2] Ola 1 / B2.5: migración local v5.
//
// Verifica que la v5 (flags de revisión, stock no confirmado, libro de
// movimientos e idempotencia de compensación por `uuid_operacion`) es
// **idempotente** y **no borra datos** de v1–v4.
import 'dart:io';

import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/database/local_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<LocalDatabaseService> _abrir(String nombre) async {
  sqfliteFfiInit();
  final dir = Directory.systemTemp.createTempSync('v5-db');
  final ruta = '${dir.path}${Platform.pathSeparator}$nombre.db';
  final db = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
  await db.abrir(ruta: ruta);
  return db;
}

Future<List<String>> _columnas(
  LocalDatabaseService servicio,
  String tabla,
) async {
  final filas = await servicio.database!.rawQuery('PRAGMA table_info($tabla)');
  return filas.map((f) => f['name'] as String).toList();
}

void main() {
  test('v5: una base nueva queda en versión 5 con las columnas nuevas', () async {
    final db = await _abrir('nueva');
    expect(await db.versionEsquema(), 5);

    // Flags de revisión (RN-006).
    expect(await _columnas(db, 'operaciones'), contains('requiere_revision'));
    expect(
      await _columnas(db, 'ventas_locales'),
      contains('requiere_revision'),
    );
    expect(
      await _columnas(db, 'reservas_locales'),
      contains('requiere_revision'),
    );
    expect(
      await _columnas(db, 'devoluciones_locales'),
      contains('requiere_revision'),
    );

    // Comprobante provisional (B0.5).
    expect(
      await _columnas(db, 'ventas_locales'),
      contains('numero_comprobante'),
    );
    expect(
      await _columnas(db, 'ventas_locales'),
      contains('numero_comprobante_generado'),
    );

    // Cliente de la reserva (B0.4.d).
    expect(await _columnas(db, 'reservas_locales'), contains('cliente_id'));

    // Stock no confirmado (CU07).
    expect(
      await _columnas(db, 'stock'),
      contains('cantidad_no_confirmada'),
    );

    // Libro de movimientos (RN-021/RNF-21).
    final tablas = await db.database!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='movimientos_inventario'",
    );
    expect(tablas, hasLength(1));
    expect(await _columnas(db, 'movimientos_inventario'), contains('tipo'));

    await db.cerrar();
  });

  test('v5: reaplicar la migración conserva los datos previos', () async {
    final db = await _abrir('reaplicar');
    final ahora = DateTime.now().toUtc().toIso8601String();

    // Dato de negocio previo (simula una venta ya registrada).
    await db.database!.insert('ventas_locales', <String, Object?>{
      'uuid_offline': 'uuid-legacy-1',
      'tenant_id': 4,
      'sucursal_id': 1,
      'estado': 'PENDIENTE_SINCRONIZACION',
      'total': 100,
      'subtotal': 100,
      'impuestos': 0,
      'monto_recibido': 100,
      'cambio': 0,
      'es_offline': 1,
      'fecha_limite_cambio': ahora,
      'fecha_registro_local': ahora,
      'fecha_actualizacion': ahora,
    });

    // Se simula una base instalada en v4 y se fuerza la re-aplicación.
    await db.database!.update(
      'meta',
      <String, Object?>{'version_esquema': 4},
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>[LocalSchema.schemaMetaKey, 0],
    );
    expect(await db.versionEsquema(), 4);

    // Re-aplicar la v5 no debe fallar ni borrar la venta previa.
    await db.migrar();
    expect(await db.versionEsquema(), 5);

    final filas = await db.database!.query(
      'ventas_locales',
      where: 'uuid_offline = ?',
      whereArgs: <Object?>['uuid-legacy-1'],
    );
    expect(filas, hasLength(1));
    expect(filas.single['total'], 100);

    // Segunda re-aplicación: también idempotente.
    await db.database!.update(
      'meta',
      <String, Object?>{'version_esquema': 4},
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object?>[LocalSchema.schemaMetaKey, 0],
    );
    await db.migrar();
    expect(await db.versionEsquema(), 5);
    final tras = await db.database!.query(
      'ventas_locales',
      where: 'uuid_offline = ?',
      whereArgs: <Object?>['uuid-legacy-1'],
    );
    expect(tras, hasLength(1));

    await db.cerrar();
  });

  test('v5: el libro de movimientos pertenece al tenant (se borra con él)', () async {
    final db = await _abrir('tenant');
    final ahora = DateTime.now().toUtc().toIso8601String();
    await db.database!.insert('movimientos_inventario', <String, Object?>{
      'uuid_offline': 'uuid-mov-1',
      'tenant_id': 4,
      'sucursal_id': 1,
      'tipo': 'DEVOLUCION',
      'variante_producto_id': 101,
      'cantidad': 1,
      'cantidad_no_confirmada': 0,
      'fecha_registro_local': ahora,
      'fecha_actualizacion': ahora,
    });

    await db.borrarPorTenant(4);
    final filas = await db.database!.query(
      'movimientos_inventario',
      where: 'tenant_id = ?',
      whereArgs: <Object?>[4],
    );
    expect(filas, isEmpty);

    await db.cerrar();
  });
}
