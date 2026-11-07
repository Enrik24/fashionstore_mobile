// [EXAMEN-2] CU18: reposición offline (plazo, mismo producto, stock,
// RN-025, diferencia clasificada, alternativas y SIN_ALTERNATIVA).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fashionstore_mobile/core/providers/offline_return_provider.dart';
import 'package:fashionstore_mobile/core/services/api_service.dart';
import 'package:fashionstore_mobile/core/services/return_service.dart';
import 'package:fashionstore_mobile/core/services/storage_service.dart';
import 'package:fashionstore_mobile/core/utils/sync_messages.dart';

import 'helpers/fase3_helpers.dart';

/// Adaptador falso para los endpoints N3 de alternativas (CU18).
class _FakeHttpAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<dynamic> body;

  _FakeHttpAdapter(this.body, {this.statusCode = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.path.contains('alternativas-talla')) {
      return ResponseBody.fromString('{}', 404);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<ApiService> _apiConAdaptador(_FakeHttpAdapter adapter) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = _FakeStorageService(prefs);
  final api = ApiService(storageService: storage);
  api.dio.httpClientAdapter = adapter;
  return api;
}

/// Storage sin plugins nativos (igual patrón que ai_assistant_chat_test).
class _FakeStorageService extends StorageService {
  _FakeStorageService(SharedPreferences prefs)
    : super(secureStorage: const FlutterSecureStorage(), prefs: prefs);

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;
}

void main() {
  test('CU18 solo dentro del plazo RN-012', () async {
    final servicios = await crearServicios();
    final solicitud = await servicios.returns.crearReposicionOffline(
      numeroComprobanteOrigen: 'FAC-1001',
      sucursalId: 1,
      items: const [
        LineaDevolucion(
          varianteProductoId: 101,
          productoId: 10,
          cantidad: 1,
          precioUnitario: 100,
          varianteCambioId: 102,
          precioVarianteNueva: 100,
        ),
      ],
      fechaCambioLimite: DateTime.now().add(const Duration(days: 3)),
    );
    expect(solicitud.tipo, 'REPOSICION');
    expect(solicitud.numeroReposicion, startsWith('REP-'));

    // Fuera de plazo: no se crea.
    expect(
      () => servicios.returns.crearReposicionOffline(
        numeroComprobanteOrigen: 'FAC-1002',
        sucursalId: 1,
        items: const [
          LineaDevolucion(
            varianteProductoId: 101,
            precioUnitario: 100,
            varianteCambioId: 102,
            precioVarianteNueva: 100,
          ),
        ],
        fechaCambioLimite: DateTime.now().subtract(const Duration(days: 1)),
      ),
      throwsA(isA<FormatException>()),
    );
    await servicios.db.cerrar();
  });

  test('CU18 mismo producto obligatorio para la prenda nueva', () async {
    final servicios = await crearServicios();
    // Variante 201 pertenece al producto 20, no al 10.
    expect(
      () => servicios.returns.crearReposicionOffline(
        numeroComprobanteOrigen: 'FAC-1003',
        sucursalId: 1,
        items: const [
          LineaDevolucion(
            varianteProductoId: 101,
            productoId: 10,
            precioUnitario: 100,
            varianteCambioId: 201,
            precioVarianteNueva: 150,
          ),
        ],
      ),
      throwsA(isA<FormatException>()),
    );
    await servicios.db.cerrar();
  });

  test('CU18 stock verificado: sin stock deriva a SIN_ALTERNATIVA', () async {
    final servicios = await crearServicios();
    await servicios.db.database!.update(
      'stock',
      {'cantidad': 0},
      where: 'variante_id = ? AND tenant_id = ?',
      whereArgs: [102, tenantFase3],
    );
    try {
      await servicios.returns.crearReposicionOffline(
        numeroComprobanteOrigen: 'FAC-1004',
        sucursalId: 1,
        items: const [
          LineaDevolucion(
            varianteProductoId: 101,
            precioUnitario: 100,
            varianteCambioId: 102,
            precioVarianteNueva: 100,
          ),
        ],
      );
      fail('Debía lanzar SIN_ALTERNATIVA');
    } on FormatException catch (e) {
      expect(e.message, contains('SIN_ALTERNATIVA'));
    }
    await servicios.db.cerrar();
  });

  test(
    'CU18 entrada y salida en la misma transacción (RN-025)',
    () async {
      final servicios = await crearServicios();
      await servicios.returns.crearReposicionOffline(
        numeroComprobanteOrigen: 'FAC-1005',
        sucursalId: 1,
        items: const [
          LineaDevolucion(
            varianteProductoId: 101,
            cantidad: 2,
            precioUnitario: 100,
            varianteCambioId: 102,
            precioVarianteNueva: 100,
          ),
        ],
      );
      // Devuelta reingresa (+2), nueva sale (-2) en la misma transacción.
      expect(await stockDe(servicios.db, 101), 12);
      expect(await stockDe(servicios.db, 102), 8);
      await servicios.db.cerrar();
    },
  );

  test('CU18 diferencia clasificada COBRO/SALDO_FAVOR/SIN_DIFERENCIA', () async {
    final servicios = await crearServicios();

    final cobro = await servicios.returns.crearReposicionOffline(
      numeroComprobanteOrigen: 'FAC-1006',
      sucursalId: 1,
      items: const [
        LineaDevolucion(
          varianteProductoId: 101,
          precioUnitario: 100,
          varianteCambioId: 102,
          precioVarianteNueva: 130,
        ),
      ],
    );
    expect(cobro.diferenciaPrecio, 30);
    expect(cobro.tipoDiferencia, 'COBRO');
    expect(cobro.montoPagadoDiferencia, 30);
    expect(cobro.saldoFavor, 0);

    final saldo = await servicios.returns.crearReposicionOffline(
      numeroComprobanteOrigen: 'FAC-1007',
      sucursalId: 1,
      items: const [
        LineaDevolucion(
          varianteProductoId: 101,
          precioUnitario: 130,
          varianteCambioId: 102,
          precioVarianteNueva: 100,
        ),
      ],
    );
    expect(saldo.tipoDiferencia, 'SALDO_FAVOR');
    expect(saldo.saldoFavor, 30);
    expect(saldo.montoPagadoDiferencia, 0);

    final igual = await servicios.returns.crearReposicionOffline(
      numeroComprobanteOrigen: 'FAC-1008',
      sucursalId: 1,
      items: const [
        LineaDevolucion(
          varianteProductoId: 101,
          precioUnitario: 100,
          varianteCambioId: 102,
          precioVarianteNueva: 100,
        ),
      ],
    );
    expect(igual.tipoDiferencia, 'SIN_DIFERENCIA');
    await servicios.db.cerrar();
  });

  test(
    'CU18 alternativas mayor/menor vía backend y SIN_ALTERNATIVA',
    () async {
      final servicios = await crearServicios();
      final api = await _apiConAdaptador(
        _FakeHttpAdapter([
          {'variante_id': 102, 'stock': 5, 'sucursal': 'Central'},
          {'variante_id': 99, 'stock': 2, 'sucursal': 'Norte'},
        ]),
      );
      final returns = ReturnService(apiService: api);
      final alternativas = await returns.buscarAlternativaTalla(
        varianteId: 101,
        sucursalId: 1,
      );
      expect(alternativas, hasLength(2));
      expect(alternativas.first['variante_id'], 102);

      // 404 N3 degrada a lista vacía sin romper.
      final api404 = await _apiConAdaptador(_FakeHttpAdapter([], statusCode: 404));
      final vacio = await ReturnService(apiService: api404)
          .buscarAlternativaTalla(varianteId: 101, sucursalId: 1);
      expect(vacio, isEmpty);

      // El provider marca SIN_ALTERNATIVA cuando no hay alternativas.
      final provider = OfflineReturnProvider(returnService: returns);
      await provider.buscarAlternativaTalla(varianteId: 101, sucursalId: 1);
      expect(provider.alternativas, hasLength(2));
      expect(provider.sinAlternativa, isFalse);
      expect(
        SyncMessages.traducirEstado('SIN_ALTERNATIVA'),
        'Sin alternativa de talla',
      );
      await servicios.db.cerrar();
    },
  );

  test('CU18 alias crearCambioOffline legacy delega a reposición', () async {
    final servicios = await crearServicios();
    final solicitud = await servicios.returns.crearCambioOffline(
      numeroComprobanteOrigen: 'FAC-1009',
      sucursalId: 1,
      items: const [
        LineaDevolucion(
          varianteProductoId: 101,
          precioUnitario: 100,
          varianteCambioId: 102,
          precioVarianteNueva: 100,
        ),
      ],
    );
    expect(solicitud.tipo, 'REPOSICION');
    await servicios.db.cerrar();
  });

  test(
    'CU18 DEVOLUCION y REPOSICION de la misma orden sin reembolso indebido',
    () async {
      final servicios = await crearServicios();
      final devolucion = await servicios.returns.crearDevolucionOffline(
        numeroComprobanteOrigen: 'FAC-1010',
        sucursalId: 1,
        items: const [
          LineaDevolucion(varianteProductoId: 101, precioUnitario: 100),
        ],
      );
      final reposicion = await servicios.returns.crearReposicionOffline(
        numeroComprobanteOrigen: 'FAC-1010',
        sucursalId: 1,
        items: const [
          LineaDevolucion(
            varianteProductoId: 101,
            precioUnitario: 100,
            varianteCambioId: 102,
            precioVarianteNueva: 100,
          ),
        ],
      );
      // La reposición no reembolsa: cobra diferencia o da saldo a favor.
      expect(reposicion.montoReembolso, 0);
      expect(reposicion.tipo, 'REPOSICION');
      expect(devolucion.tipo, 'DEVOLUCION');

      final tipos = (await servicios.queue.pendientes())
          .map((op) => op.tipoOperacion)
          .toList();
      expect(tipos, contains('DEVOLUCION'));
      expect(tipos, contains('REPOSICION'));
      final listaLocal = await servicios.returns.listarDesdeLocal();
      expect(listaLocal, hasLength(2));
      expect(
        listaLocal.where((e) => e.tipo == 'REPOSICION').single.numeroReposicion,
        startsWith('REP-'),
      );
      await servicios.db.cerrar();
    },
  );
}
