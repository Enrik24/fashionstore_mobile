import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/database/local_schema.dart';
import 'package:fashionstore_mobile/core/database/repositories/local_customer_repository.dart';
import 'package:fashionstore_mobile/core/services/local_crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // [EXAMEN-2] La base se prueba con FFI mediante el factory inyectado.
  sqfliteFfiInit();

  late LocalDatabaseService servicio;

  setUp(() {
    servicio = LocalDatabaseService(factory: databaseFactoryFfi, cifrar: false);
  });

  tearDown(() async {
    await servicio.cerrar();
  });

  test(
    'abre una base en memoria y aplica la migración v1 idempotente',
    () async {
      await servicio.abrir(ruta: inMemoryDatabasePath);

      expect(servicio.estaAbierta, isTrue);
      expect(await servicio.versionEsquema(), LocalSchema.version);

      final tablas = await servicio.database!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final nombres = tablas.map((fila) => fila['name']).toSet();
      expect(nombres, containsAll(LocalSchema.tablas));

      expect(await servicio.migrar(), LocalSchema.version);
      expect(await servicio.versionEsquema(), LocalSchema.version);
    },
  );

  test('ejecuta varias escrituras dentro de una transacción', () async {
    await servicio.abrir(ruta: inMemoryDatabasePath);

    await servicio.ejecutarTransaccion<void>((txn) async {
      await txn.insert('configuracion', <String, Object?>{
        'clave': 'actual',
        'tenant_id': 10,
        'valor': '{"moneda":"COP"}',
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      });
      await txn.insert('permisos', <String, Object?>{
        'clave': 'actual',
        'tenant_id': 10,
        'rol': 'Cajero',
        'permisos': '[]',
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      });
    });

    final configuracion = await servicio.database!.query('configuracion');
    final permisos = await servicio.database!.query('permisos');
    expect(configuracion, hasLength(1));
    expect(permisos, hasLength(1));
  });

  test('borrarPorTenant conserva los datos de otros tenants', () async {
    await servicio.abrir(ruta: inMemoryDatabasePath);
    final ahora = DateTime.now().toUtc().toIso8601String();
    for (final tenant in <int>[10, 20]) {
      await servicio.database!.insert('configuracion', <String, Object?>{
        'clave': 'actual',
        'tenant_id': tenant,
        'valor': 'tenant-$tenant',
        'fecha_actualizacion': ahora,
      });
      await servicio.database!.insert('permisos', <String, Object?>{
        'clave': 'actual',
        'tenant_id': tenant,
        'rol': 'Cajero',
        'permisos': '[]',
        'fecha_actualizacion': ahora,
      });
    }

    await servicio.borrarPorTenant(10);

    final configuraciones = await servicio.database!.query('configuracion');
    final permisos = await servicio.database!.query('permisos');
    expect(configuraciones.single['tenant_id'], 20);
    expect(permisos.single['tenant_id'], 20);
    expect(await servicio.versionEsquema(), LocalSchema.version);
  });

  test(
    'borrarTodo elimina datos de todos los tenants y conserva el esquema',
    () async {
      await servicio.abrir(ruta: inMemoryDatabasePath);
      final ahora = DateTime.now().toUtc().toIso8601String();
      for (final tenant in <int>[10, 20]) {
        await servicio.database!.insert('sesion', <String, Object?>{
          'clave': 'actual',
          'tenant_id': tenant,
          'pin_configurado': 1,
          'fecha_actualizacion': ahora,
        });
      }

      await servicio.borrarTodo();

      expect(await servicio.database!.query('sesion'), isEmpty);
      expect(await servicio.versionEsquema(), LocalSchema.version);
    },
  );

  // [EXAMEN-2] C2.3 P1: migración v2 idempotente con las columnas nuevas.
  test('migración v2 idempotente crea las columnas nuevas sin borrar datos', () async {
    await servicio.abrir(ruta: inMemoryDatabasePath);
    // [EXAMEN-2] Fase 3: la base migra v1→v4 sin borrar datos de v2.
    expect(await servicio.versionEsquema(), LocalSchema.version);

    // Dato previo a la segunda migración: debe sobrevivir.
    await servicio.database!.insert('productos', <String, Object?>{
      'id': 99,
      'tenant_id': 10,
      'nombre': 'Pantalón',
      'precio': 150,
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    });

    // Segunda aplicación idempotente (sin error, sin subir versión extra).
    expect(await servicio.migrar(), LocalSchema.version);
    expect(await servicio.migrar(), LocalSchema.version);

    const esperadas = <String, List<String>>{
      'productos': <String>[
        'version',
        'updated_at',
        'deleted_at',
        'precio_referencia',
        'tipo_tela_id',
        'composicion',
      ],
      'variantes': <String>[
        'version',
        'updated_at',
        'deleted_at',
        'precio_variante',
      ],
      'stock': <String>['cantidad_reservada', 'stock_minimo'],
      'pagos': <String>['stripe_payment_intent_id', 'fecha_ultimo_intento'],
      'operaciones': <String>[
        'fecha_ultimo_intento',
        'fecha_recepcion_servidor',
        'error_detalle',
      ],
      'conflictos': <String>['detalle_json', 'fecha', 'resuelto_por'],
    };
    for (final entrada in esperadas.entries) {
      final info = await servicio.database!.rawQuery(
        'PRAGMA table_info(${entrada.key})',
      );
      final columnas = info.map((fila) => fila['name']).toSet();
      for (final columna in entrada.value) {
        expect(columnas, contains(columna), reason: '${entrada.key}.$columna');
      }
    }

    final productos = await servicio.database!.query(
      'productos',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[99, 10],
    );
    expect(productos, hasLength(1));
    expect(productos.single['nombre'], 'Pantalón');
  });

  // [EXAMEN-2] C2.3 P1: PII de clientes cifrada en reposo (AES-GCM).
  test('PII de clientes se almacena cifrada y se lee descifrada', () async {
    await servicio.abrir(ruta: inMemoryDatabasePath);
    final crypto = LocalCryptoService();
    final clave = crypto.generarClaveBase();
    final repo = LocalCustomerRepository(
      servicio.database!,
      tenantId: 10,
      crypto: crypto,
      keyProvider: () async => clave,
    );

    await repo.guardarClientes(<Map<String, Object?>>[
      <String, Object?>{
        'id': 7,
        'nombre': 'Ana',
        'nit_ci': '123456',
        'telefono': '591-70000000',
        'correo': 'ana@example.com',
      },
    ]);

    // En SQLite no aparece el texto en claro: va prefijado y cifrado.
    final cruda = await servicio.database!.query(
      'clientes',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[7, 10],
    );
    expect(cruda, hasLength(1));
    final nit = cruda.single['nit_ci']?.toString() ?? '';
    final telefono = cruda.single['telefono']?.toString() ?? '';
    final correo = cruda.single['correo']?.toString() ?? '';
    expect(nit.startsWith('AEG:'), isTrue);
    expect(telefono.startsWith('AEG:'), isTrue);
    expect(correo.startsWith('AEG:'), isTrue);
    expect(nit, isNot('123456'));
    expect(telefono, isNot(contains('70000000')));
    expect(correo, isNot(contains('ana@example.com')));

    // La lectura con la misma clave devuelve la PII en claro.
    final leido = await repo.obtenerPorId(7);
    expect(leido, isNotNull);
    expect(leido!['nit_ci'], '123456');
    expect(leido['telefono'], '591-70000000');
    expect(leido['correo'], 'ana@example.com');
  });
}
