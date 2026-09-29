import 'package:dio/dio.dart';
import '../../config/config.dart';
import '../../config/constants.dart';
import '../models/comprobante_model.dart';
import '../models/order_model.dart';
import '../models/payment_transaction_model.dart';
import 'api_service.dart';

class OrderService {
  final ApiService _apiService;

  OrderService({required ApiService apiService}) : _apiService = apiService;

  Future<OrderModel> crearOrden({
    int? sucursalId,
    String? direccionEnvio,
    String? ciudadEnvio,
    String? telefonoContacto,
    String metodoPago = 'STRIPE',
    String tipo = 'DIGITAL',
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final payload = {
        if (sucursalId != null) 'sucursal_id': sucursalId,
        if (direccionEnvio != null && direccionEnvio.isNotEmpty)
          'direccion_envio': direccionEnvio,
        if (ciudadEnvio != null && ciudadEnvio.isNotEmpty)
          'ciudad_envio': ciudadEnvio,
        if (telefonoContacto != null && telefonoContacto.isNotEmpty)
          'telefono_contacto': telefonoContacto,
        'metodo_pago': metodoPago,
        'tipo': tipo,
        if (items != null && items.isNotEmpty) 'items': items,
      };

      final response = await _apiService.dio.post(
        AppConstants.epOrdenes,
        data: payload,
      );

      return OrderModel.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<OrderModel>> getOrdenes() async {
    try {
      final response = await _apiService.dio.get(AppConstants.epOrdenes);
      if (response.data is List) {
        return (response.data as List)
            .map((item) => OrderModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map && response.data['items'] != null) {
        return (response.data['items'] as List)
            .map((item) => OrderModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<List<OrderModel>> getHistorialCompras({int skip = 0, int limit = 20}) async {
    try {
      final response = await _apiService.dio.get(
        AppConstants.epHistorialCompras,
        queryParameters: {'skip': skip, 'limit': limit},
      );
      if (response.data is List) {
        return (response.data as List)
            .map((item) => OrderModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map && response.data['items'] != null) {
        return (response.data['items'] as List)
            .map((item) => OrderModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      // Fallback a getOrdenes si falla o si usa el endpoint estándar
      return getOrdenes();
    }
  }

  Future<OrderModel> getOrdenDetalle(int id) async {
    try {
      final response = await _apiService.dio.get('${AppConstants.epOrdenes}$id');
      return OrderModel.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `GET /ordenes/{id}/comprobante` — obtiene o genera el comprobante
  /// (factura/ticket) de una orden del cliente.
  Future<ComprobanteModel> getComprobante(int ordenId) async {
    try {
      final response = await _apiService.dio.get(
        '${AppConstants.epOrdenes}$ordenId/comprobante',
      );
      return ComprobanteModel.fromJson(
          response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// URL del PDF del comprobante (`GET /ordenes/{id}/comprobante/pdf`).
  /// El backend lo sirve inline para visualizar o descargar.
  static String comprobantePdfUrl(int ordenId) {
    return '${AppConfig.apiBaseUrl}${AppConstants.epOrdenes}$ordenId/comprobante/pdf';
  }

  /// Descarga los bytes del PDF del comprobante usando el cliente
  /// autenticado (dio). Evita abrir la URL en navegador externo, que falla
  /// en varios dispositivos y no muestra el motivo real del error.
  Future<List<int>> descargarComprobantePdf(int ordenId) async {
    try {
      final response = await _apiService.dio.get<List<int>>(
        '${AppConstants.epOrdenes}$ordenId/comprobante/pdf',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data ?? [];
      if (data.isEmpty) {
        throw Exception('El servidor devolvió un PDF vacío.');
      }
      return data;
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `GET /pagos/transacciones/orden/{orden_id}` — historial de
  /// transacciones de pago de una orden (CU18).
  Future<List<PaymentTransactionModel>> getTransacciones(
      int ordenId) async {
    try {
      final response = await _apiService.dio.get(
        '${AppConstants.epTransaccionesOrden}/$ordenId',
      );
      if (response.data is List) {
        return (response.data as List)
            .map((e) =>
                PaymentTransactionModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<StripeSessionResponse> createStripeCheckoutSession(
    int ordenId, {
    String? successUrl,
    String? cancelUrl,
  }) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epStripeCheckout,
        data: {
          'orden_id': ordenId,
          if (successUrl != null && successUrl.isNotEmpty) 'success_url': successUrl,
          if (cancelUrl != null && cancelUrl.isNotEmpty) 'cancel_url': cancelUrl,
        },
      );
      return StripeSessionResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `POST /pagos/stripe/confirmar-retorno` — verifica la sesión de Stripe
  /// y marca la orden como PAGADO (descuenta stock + genera comprobante).
  /// Es lo que hace el frontend web en su página de success; la app móvil
  /// debe llamarlo al volver del navegador externo, si no la orden queda
  /// en PENDIENTE_PAGO aunque el cobro exista en Stripe.
  Future<void> confirmarStripeRetorno(String sessionId, int ordenId) async {
    try {
      await _apiService.dio.post(
        AppConstants.epStripeConfirmar,
        queryParameters: {'session_id': sessionId, 'orden_id': ordenId},
      );
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  Future<PayPalOrderResponse> createPayPalOrder(
    int ordenId, {
    String? returnUrl,
    String? cancelUrl,
  }) async {
    try {
      final response = await _apiService.dio.post(
        AppConstants.epPaypalCrearOrden,
        data: {
          'orden_id': ordenId,
          if (returnUrl != null && returnUrl.isNotEmpty) 'return_url': returnUrl,
          if (cancelUrl != null && cancelUrl.isNotEmpty) 'cancel_url': cancelUrl,
        },
      );
      return PayPalOrderResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }

  /// `POST /pagos/paypal/capturar` — captura la orden aprobada en PayPal
  /// y marca la orden como PAGADO. Equivalente móvil del success web.
  Future<void> capturePayPalOrder(String paypalOrderId, int ordenId) async {
    try {
      await _apiService.dio.post(
        AppConstants.epPaypalCapturar,
        data: {'paypal_order_id': paypalOrderId, 'orden_id': ordenId},
      );
    } catch (e) {
      throw _apiService.handleError(e);
    }
  }
}
