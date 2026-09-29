import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fashionstore_mobile/core/models/user_model.dart';
import 'package:fashionstore_mobile/core/providers/ai_provider.dart';
import 'package:fashionstore_mobile/core/providers/auth_provider.dart';
import 'package:fashionstore_mobile/core/providers/cart_provider.dart';
import 'package:fashionstore_mobile/core/services/ai_service.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/auth_service.dart';
import 'package:fashionstore_mobile/core/services/cart_service.dart';
import 'package:fashionstore_mobile/core/services/catalog_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';
import 'package:fashionstore_mobile/features/ai_assistant/ai_assistant_page.dart';

/// Respuesta real capturada del backend para:
/// "crea un outfit de hombre para verano" (tipo_respuesta = outfit)
const Map<String, dynamic> _outfitResponse = {
  'respuesta':
      'Te propongo un look veraniego: polera de algodón, short cargo, gorra y cinturón de cuero.',
  'sugerencias': ['¿Ver más poleras?', '¿Combinar con calzado?', 'Promociones de verano'],
  'productos_mencionados': [
    {
      'id': 6,
      'nombre': 'Polera Hombre Cat Logo Detroit Blue White',
      'descripcion': 'Polera para las temporadas de verano',
      'precio': 249.0,
      'categoria': 'Poleras',
      'variante_id': 5,
    },
    {
      'id': 27,
      'nombre': 'Short Cat Hombre Foundation Cargo Short Dusty Olive',
      'descripcion': '',
      'precio': 450.0,
      'categoria': 'Shorts',
      'variante_id': 67,
    },
  ],
  'tipo_respuesta': 'outfit',
  'accion': null,
};

const Map<String, dynamic> _recomendacionesResponse = {
  'cliente_id': null,
  'estilo_detectado': 'Casual',
  'mensaje_personalizado': 'Selección para ti',
  'recomendaciones': [
    {
      'producto_id': 6,
      'nombre': 'Polera Hombre Cat Logo',
      'razon': 'Tendencia de temporada',
      'precio': 249.0,
      'categoria': 'Poleras',
    },
  ],
};

/// Adaptador HTTP falso: evita depender del backend real durante el test.
class _FakeHttpAdapter implements HttpClientAdapter {
  final bool fail;

  _FakeHttpAdapter({this.fail = false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'sin conexión (simulado)',
      );
    }
    if (options.path.contains('asistente-chat')) {
      return _json(_outfitResponse);
    }
    if (options.path.contains('recomendaciones')) {
      return _json(_recomendacionesResponse);
    }
    return _json(const {});
  }

  ResponseBody _json(Map<String, dynamic> body) => ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// StorageService sin plugins nativos (secure storage / prefs reales).
class _FakeStorageService extends StorageService {
  _FakeStorageService(SharedPreferences prefs)
      : super(secureStorage: const FlutterSecureStorage(), prefs: prefs);

  String? _token;

  @override
  Future<String?> getAccessToken() async => _token;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokens(TokenResponse tokens) async {
    _token = tokens.accessToken;
  }

  @override
  Future<void> clearAllSession() async => _token = null;

  @override
  UserModel? getUser() => null;

  @override
  ClienteProfile? getClientProfile() => null;

  @override
  String? getRememberedEmail() => null;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<Widget> buildAssistantApp({bool failRequests = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storageService = _FakeStorageService(prefs);
    final apiService = ApiService(storageService: storageService);
    apiService.dio.httpClientAdapter = _FakeHttpAdapter(fail: failRequests);

    final authService = AuthService(apiService: apiService);
    final catalogService = CatalogService(apiService: apiService);
    final cartService = CartService(apiService: apiService);
    final aiService = AiService(apiService: apiService);

    final router = GoRouter(
      initialLocation: '/ai-assistant',
      routes: [
        GoRoute(
          path: '/ai-assistant',
          builder: (context, state) => const AiAssistantPage(),
        ),
        GoRoute(
          path: '/catalog/:id',
          builder: (context, state) => const Scaffold(body: Text('catalogo')),
        ),
      ],
    );

    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<ApiService>.value(value: apiService),
        Provider<AuthService>.value(value: authService),
        Provider<CatalogService>.value(value: catalogService),
        Provider<CartService>.value(value: cartService),
        Provider<AiService>.value(value: aiService),
        ChangeNotifierProvider<CartProvider>(
          create: (_) => CartProvider(cartService: cartService),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (context) => AuthProvider(
            authService: authService,
            storageService: storageService,
            cartProvider: context.read<CartProvider>(),
          ),
        ),
        ChangeNotifierProvider<AiProvider>(
          create: (_) => AiProvider(aiService: aiService),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  group('Asistente virtual (app móvil)', () {
    testWidgets('responde a una consulta escrita por teclado (outfit)',
        (tester) async {
      await tester.pumpWidget(await buildAssistantApp());
      await tester.pump(); // ejecuta el post-frame de initState

      await tester.enterText(
        find.byType(TextField),
        'crea un outfit de hombre para verano',
      );
      await tester.pump();
      expect(find.text('crea un outfit de hombre para verano'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(); // agrega el mensaje del usuario
      await tester.pump(const Duration(milliseconds: 100)); // llega respuesta

      expect(
        find.textContaining('look veraniego'),
        findsOneWidget,
        reason: 'El asistente debe mostrar la respuesta del backend',
      );
      expect(find.textContaining('Polera Hombre Cat Logo'), findsWidgets);
    });

    testWidgets('muestra un mensaje cuando la petición falla', (tester) async {
      await tester.pumpWidget(await buildAssistantApp(failRequests: true));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'hola');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('tuve un problema'), findsOneWidget);
    });
  });
}

