import 'dart:io';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../config/config.dart';
import '../services/local_crypto_service.dart';
import '../services/storage_service.dart';
import 'local_migrations.dart';
import 'local_schema.dart';

/// [EXAMEN-2] Acceso centralizado a la base SQLite local.
///
/// En producción usa `sqflite_sqlcipher` y la clave almacenada en
/// `flutter_secure_storage`. Las pruebas inyectan `sqflite_common_ffi`.
class LocalDatabaseService {
  LocalDatabaseService({
    StorageService? storageService,
    LocalCryptoService? cryptoService,
    DatabaseFactory? factory,
    bool? cifrar,
  }) : _storageService = storageService,
       _cryptoService = cryptoService ?? LocalCryptoService(),
       _factory = factory,
       _cifrar = cifrar ?? (factory == null);

  final StorageService? _storageService;
  final LocalCryptoService _cryptoService;
  final DatabaseFactory? _factory;
  final bool _cifrar;

  Database? _db;
  String? _path;

  Database? get database => _db;
  String? get path => _path;
  bool get estaAbierta => _db?.isOpen ?? false;

  /// Abre la base, creando la clave si todavía no existe.
  Future<Database> abrir({String? ruta, String? claveBase}) async {
    if (estaAbierta) return _db!;
    _path = ruta ?? await _rutaPorDefecto();
    var clave = claveBase ?? await _storageService?.readDatabaseKey();
    if (clave == null || clave.isEmpty) {
      clave = _cryptoService.generarClaveBase();
      await _storageService?.saveDatabaseKey(clave);
    }

    final factory = _factory ?? databaseFactory;
    if (_cifrar && _factory == null) {
      _db = await openDatabase(_path!, password: clave);
    } else {
      // [EXAMEN-2] FFI no cifra el archivo; SQLCipher sí lo hace en móvil.
      _db = await factory.openDatabase(
        _path!,
        options: OpenDatabaseOptions(
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        ),
      );
    }
    await migrar();
    return _db!;
  }

  Future<void> cerrar() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) await db.close();
  }

  /// Aplica las migraciones pendientes según la versión almacenada en `meta`.
  Future<int> migrar() async {
    final db = _exigirBase();
    final actual = await versionEsquema();
    if (actual < LocalSchema.version) {
      await LocalMigrations.migrar(db, actual);
    }
    return versionEsquema();
  }

  /// Ejecuta varias operaciones en una única transacción SQLite.
  Future<T> ejecutarTransaccion<T>(
    Future<T> Function(Transaction transaction) operacion,
  ) async {
    final db = _exigirBase();
    return db.transaction<T>(operacion);
  }

  /// Versión local; cero si la base aún no contiene la tabla `meta`.
  Future<int> versionEsquema() async {
    final db = _exigirBase();
    if (!await _tablaExiste('meta')) return 0;
    final filas = await db.query(
      'meta',
      columns: <String>['version_esquema'],
      where: 'clave = ? AND tenant_id = ?',
      whereArgs: <Object>[
        LocalSchema.schemaMetaKey,
        LocalSchema.reservedGlobalTenantId,
      ],
      limit: 1,
    );
    if (filas.isEmpty) return 0;
    return (filas.first['version_esquema'] as num?)?.toInt() ?? 0;
  }

  /// Elimina exclusivamente los datos del tenant indicado.
  ///
  /// La fila global que registra el esquema permanece para no invalidar la
  /// base ni afectar a los tenants restantes.
  Future<void> borrarPorTenant(int tenantId) async {
    final db = _exigirBase();
    await db.transaction<void>((txn) async {
      final tablas = await _tablasConTenant(txn);
      for (final tabla in tablas) {
        await txn.delete(
          tabla,
          where: 'tenant_id = ?',
          whereArgs: <Object>[tenantId],
        );
      }
    });
  }

  /// Elimina todos los datos de negocio, conservando el control del esquema.
  Future<void> borrarTodo() async {
    final db = _exigirBase();
    await db.transaction<void>((txn) async {
      final tablas = await _tablasConTenant(txn);
      for (final tabla in tablas) {
        await txn.delete(
          tabla,
          where: 'tenant_id != ?',
          whereArgs: <Object>[LocalSchema.reservedGlobalTenantId],
        );
      }
    });
  }

  /// Elimina el archivo local cifrado. Se usa ante revocación del dispositivo.
  Future<void> eliminarArchivoLocal() async {
    final ruta = _path;
    await cerrar();
    _path = null;
    if (ruta == null) return;
    final archivo = File(ruta);
    if (await archivo.exists()) await archivo.delete();
  }

  /// Espacio ocupado por el archivo SQLite, en bytes.
  Future<int> espacioUsado() async {
    final archivo = File(_path!);
    if (!await archivo.exists()) return 0;
    return await archivo.length();
  }

  /// [EXAMEN-2] C2.3: espacio disponible según límite configurado y uso real.
  ///
  /// No existe una API Dart estándar para espacio libre del disco sin plugin;
  /// se calcula como `offlineEspacioMaximoMb - espacioUsado()` (archivo real).
  Future<int> espacioDisponible() async {
    final usado = await espacioUsado();
    const total = AppConfig.offlineEspacioMaximoMb * 1024 * 1024;
    final disponible = total - usado;
    return disponible < 0 ? 0 : disponible;
  }

  Database _exigirBase() {
    final db = _db;
    if (db == null || !db.isOpen) {
      throw StateError('La base local no está abierta.');
    }
    return db;
  }

  Future<String> _rutaPorDefecto() async {
    final factory = _factory ?? databaseFactory;
    final directorio = await factory.getDatabasesPath();
    return '$directorio${Platform.pathSeparator}${LocalSchema.databaseName}';
  }

  Future<bool> _tablaExiste(String tabla) async {
    final filas = await _exigirBase().rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[tabla],
    );
    return filas.isNotEmpty;
  }

  Future<List<String>> _tablasConTenant(DatabaseExecutor db) async {
    final filas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    final tablas = <String>[];
    for (final fila in filas) {
      final nombre = fila['name'] as String;
      final columnas = await db.rawQuery('PRAGMA table_info($nombre)');
      if (columnas.any((columna) => columna['name'] == 'tenant_id')) {
        tablas.add(nombre);
      }
    }
    return tablas;
  }
}
