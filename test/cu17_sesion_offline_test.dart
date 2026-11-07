import 'package:fashionstore_mobile/core/database/local_database_service.dart';
import 'package:fashionstore_mobile/core/database/repositories/local_config_repository.dart';
import 'package:fashionstore_mobile/core/database/repositories/local_permissions_repository.dart';
import 'package:fashionstore_mobile/core/models/api_response.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/device_service.dart';
import 'package:fashionstore_mobile/core/services/local_crypto_service.dart';
import 'package:fashionstore_mobile/core/services/offline_session_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeOfflineClient implements OfflineApiClient {
  final Map<String, dynamic> sesion;
  final List<String> llamadas = <String>[];

  _FakeOfflineClient(this.sesion);

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    llamadas.add('GET $path');
    if (path.contains('/sesion/estado')) {
      return <String, dynamic>{
        'usuario_id': 7,
        'tenant_id': 3,
        'dispositivo_id': 'device-1',
        'pin_configurado': true,
        'dispositivo_activo': true,
        'intentos_restantes': 5,
        'max_horas_sesion_offline': 12,
      };
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    llamadas.add('POST $path');
    if (path.endsWith('/sesion/iniciar')) return sesion;
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> delete(String path, {Object? data}) async {
    llamadas.add('DELETE $path');
    return <String, dynamic>{};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late StorageService storage;
  late LocalDatabaseService database;
  late _FakeOfflineClient client;

  final respuestaSesion = <String, dynamic>{
    'token_offline': 'token-offline-seguro',
    'expira_en': DateTime.now()
        .add(const Duration(hours: 8))
        .toUtc()
        .toIso8601String(),
    'usuario_id': 7,
    'tenant_id': 3,
    'dispositivo_id': 'device-1',
    'roles': <String>['Cajero'],
    'permisos': <String>['catalogo:leer', 'ventas:crear'],
    'configuracion': <String, dynamic>{
      'tenant_id': 3,
      'max_horas_sesion_offline': 12,
      'habilitar_carrito_offline': true,
    },
  };

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = StorageService(
      secureStorage: const FlutterSecureStorage(),
      prefs: await SharedPreferences.getInstance(),
    );
    database = LocalDatabaseService(
      storageService: storage,
      factory: databaseFactoryFfi,
      cifrar: false,
    );
    await database.abrir(ruta: inMemoryDatabasePath);
    client = _FakeOfflineClient(respuestaSesion);
  });

  tearDown(() async {
    await database.cerrar();
  });

  OfflineSessionService crearServicio() {
    final api = ApiService(storageService: storage);
    final devices = DeviceService(
      storageService: storage,
      apiService: api,
      client: client,
    );
    return OfflineSessionService(
      storageService: storage,
      cryptoService: LocalCryptoService(iteracionesPbkdf2: 1000),
      deviceService: devices,
      client: client,
      configRepository: LocalConfigRepository(database),
      permissionsRepository: LocalPermissionsRepository(database),
    );
  }

  test('configura el PIN con hash y salt y valida localmente', () async {
    final servicio = crearServicio();
    await servicio.initialize();

    expect(
      await servicio.configurarPin(pin: '135790', contrasenaActual: 'Actual1!'),
      isTrue,
    );
    expect(servicio.pinConfigurado, isTrue);
    expect(await storage.readPinHash(), isNot('135790'));
    expect(await storage.readPinSalt(), isNotEmpty);
    expect(await servicio.iniciarSesionOffline('135790'), isTrue);
  });

  test('el quinto PIN incorrecto bloquea el acceso local', () async {
    final servicio = crearServicio();
    await servicio.initialize();
    await servicio.configurarPin(pin: '135790', contrasenaActual: 'Actual1!');

    for (var intento = 1; intento <= 5; intento++) {
      await expectLater(
        servicio.iniciarSesionOffline('999999'),
        throwsA(isA<ApiException>()),
      );
    }
    expect(servicio.intentosRestantes, 0);
    await expectLater(
      servicio.iniciarSesionOffline('135790'),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'inicia sesión remota y conserva token, configuración y permisos',
    () async {
      final servicio = crearServicio();
      await servicio.initialize();
      await servicio.configurarPin(pin: '135790', contrasenaActual: 'Actual1!');

      final respuesta = await servicio.iniciarSesionRemota('135790');

      expect(respuesta['token_offline'], 'token-offline-seguro');
      expect(await storage.readOfflineToken(), 'token-offline-seguro');
      expect(storage.readLastTenant(), 3);
      expect(servicio.haySesionValida, isTrue);
      expect(await LocalConfigRepository(database).leer(3), isNotNull);
      expect(
        await LocalPermissionsRepository(
          database,
        ).leerPermisos(tenantId: 3, usuarioId: 7),
        containsAll(<String>['catalogo:leer', 'ventas:crear']),
      );
      expect(client.llamadas, contains('POST /offline/sesion/iniciar'));
    },
  );
}
