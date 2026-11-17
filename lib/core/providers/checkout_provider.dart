import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/config.dart';
import '../models/api_response.dart';
import '../models/order_model.dart';
import '../models/cart_model.dart';
import '../models/reservation_model.dart';
import '../services/order_service.dart';
import '../services/cart_service.dart';

class CheckoutProvider extends ChangeNotifier {
  final OrderService _orderService;
  final CartService? _cartService;

  CheckoutProvider({
    required OrderService orderService,
    CartService? cartService,
  }) : _orderService = orderService,
       _cartService = cartService;

  // Delivery state
  String _deliveryType = 'SHIPPING'; // 'SHIPPING' | 'PICKUP'
  String _shippingAddress = '';
  String _city = 'Santa Cruz';
  String _phoneNumber = '';
  BranchModel? _selectedBranch;

  // Payment state
  String _paymentMethod = 'STRIPE'; // 'STRIPE', 'PAYPAL', 'QR', 'EFECTIVO'

  // Processing state
  bool _isProcessing = false;
  String? _errorMessage;
  // [EXAMEN-2] CU15/§19: feedback informativo (no error) del flujo offline.
  String? _mensaje;
  OrderModel? _lastCreatedOrder;
  List<OrderModel> _orderHistory = [];
  bool _isLoadingHistory = false;

  // IDs de la pasarela para confirmar el retorno al volver a la app.
  // Sin esto la orden queda en PENDIENTE_PAGO aunque el cobro exista en Stripe.
  String? _lastStripeSessionId;
  int? _lastStripeOrderId;
  String? _lastPayPalOrderId;
  int? _lastPayPalInternalOrderId;
  bool _isConfirmingPayment = false;

  // Getters
  String get deliveryType => _deliveryType;
  String get shippingAddress => _shippingAddress;
  String get city => _city;
  String get phoneNumber => _phoneNumber;
  BranchModel? get selectedBranch => _selectedBranch;
  String get paymentMethod => _paymentMethod;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  // [EXAMEN-2] CU15/§19: "Pedido guardado localmente...".
  String? get mensaje => _mensaje;
  static const String mensajePagoDiferidoOffline =
      'Pedido guardado localmente. El pago se completará cuando haya conexión.';
  OrderModel? get lastCreatedOrder => _lastCreatedOrder;
  List<OrderModel> get orderHistory => _orderHistory;
  bool get isLoadingHistory => _isLoadingHistory;
  String? get lastStripeSessionId => _lastStripeSessionId;
  int? get lastStripeOrderId => _lastStripeOrderId;
  String? get lastPayPalOrderId => _lastPayPalOrderId;
  int? get lastPayPalInternalOrderId => _lastPayPalInternalOrderId;
  bool get isConfirmingPayment => _isConfirmingPayment;

  void setDeliveryType(String val) {
    _deliveryType = val;
    notifyListeners();
  }

  void setShippingAddress(String val) {
    _shippingAddress = val;
    notifyListeners();
  }

  void setCity(String val) {
    _city = val;
    notifyListeners();
  }

  void setPhoneNumber(String val) {
    _phoneNumber = val;
    notifyListeners();
  }

  void setSelectedBranch(BranchModel? branch) {
    _selectedBranch = branch;
    notifyListeners();
  }

  void setPaymentMethod(String val) {
    _paymentMethod = val;
    notifyListeners();
  }

  bool isFormValid() {
    if (_deliveryType == 'SHIPPING') {
      return _shippingAddress.trim().isNotEmpty;
    } else {
      return _selectedBranch != null;
    }
  }

  Future<OrderModel?> createOrder({List<CartItemModel>? items}) async {
    if (_deliveryType == 'SHIPPING' && _shippingAddress.trim().isEmpty) {
      _errorMessage = 'Por favor ingresa la dirección de entrega.';
      notifyListeners();
      return null;
    }

    if (_deliveryType == 'PICKUP' && _selectedBranch == null) {
      _errorMessage = 'Por favor selecciona la sucursal de retiro.';
      notifyListeners();
      return null;
    }

    _isProcessing = true;
    _errorMessage = null;
    _mensaje = null;
    notifyListeners();

    try {
      List<Map<String, dynamic>>? itemPayload;
      if (items != null && items.isNotEmpty) {
        itemPayload = items
            .map(
              (i) => {
                'variante_producto_id': i.varianteProductoId,
                'cantidad': i.cantidad,
              },
            )
            .toList();
      }

      OrderModel order;
      try {
        order = await _orderService.crearOrden(
          sucursalId: _deliveryType == 'PICKUP' ? _selectedBranch?.id : null,
          direccionEnvio: _deliveryType == 'SHIPPING'
              ? _shippingAddress.trim()
              : null,
          ciudadEnvio: _deliveryType == 'SHIPPING' ? _city.trim() : null,
          telefonoContacto: _phoneNumber.trim(),
          metodoPago: _paymentMethod,
          tipo: 'DIGITAL',
          items: itemPayload,
        );
      } catch (error) {
        final cartService = _cartService;
        if (cartService == null || items == null || items.isEmpty) rethrow;
        // [EXAMEN-2] B1.6.g: sólo los fallos de **conectividad** degradan a
        // orden local con pago diferido. Un 4xx del servidor (validación,
        // tenant suspendido, producto desactivado) debe propagarse: antes se
        // creaba una orden local "fantasma" y el cliente veía "pedido guardado"
        // cuando el servidor lo había rechazado.
        if (!_esErrorDeConectividad(error)) rethrow;
        // [FIX] Si el carrito sólo existía en el servidor (ítems agregados con
        // conexión), el carrito local estaría vacío y la conversión fallaría:
        // se siembran los ítems en SQLite antes de convertir.
        await cartService.asegurarCarritoConItems(items);
        final conversion = await cartService.convertirEnPagoDiferido(
          sucursalId: _deliveryType == 'PICKUP' ? _selectedBranch?.id : null,
          direccionEnvio: _deliveryType == 'SHIPPING'
              ? _shippingAddress.trim()
              : null,
          clienteId: null,
        );
        order = OrderModel(
          id: 0,
          numeroOrden: 'OFFLINE-${conversion.uuidOrden.substring(0, 8)}',
          clienteId: 0,
          total: conversion.total,
          subtotal: conversion.total,
          estado: 'PENDIENTE_PAGO_DIFERIDO',
          metodoPago: _paymentMethod,
          uuidOrden: conversion.uuidOrden,
          origen: 'OFFLINE',
          esOffline: true,
          estadoSincronizacion: 'PENDIENTE',
          fechaLimitePago: DateTime.now().toUtc().add(
            const Duration(hours: 24),
          ),
          expiraEn: DateTime.now().toUtc().add(const Duration(hours: 24)),
        );
        _lastCreatedOrder = order;
        // [EXAMEN-2] CU15/§19: feedback del pago diferido offline.
        _mensaje = mensajePagoDiferidoOffline;
        _isProcessing = false;
        notifyListeners();
        return order;
      }

      _lastCreatedOrder = order;

      // NOTA: ya no se abre el navegador externo aquí. La pantalla de
      // checkout decide: Stripe va al WebView in-app, PayPal sigue externo.
      _isProcessing = false;
      notifyListeners();
      return order;
    } catch (e) {
      _errorMessage = e.toString();
      _isProcessing = false;
      notifyListeners();
      return null;
    }
  }

  /// [EXAMEN-2] B1.6.g: ¿el fallo es de **conectividad** (y no del servidor)?
  ///
  /// Si el servidor respondió (cualquier código HTTP), el fallo es de
  /// negocio y no se puede degradar a una orden local con pago diferido.
  ///
  /// [FIX] `OrderService` envuelve los fallos de Dio en una `ApiException`
  /// (vía `handleError`). Cuando el servidor NO respondió (sin conexión),
  /// esa `ApiException` llega con `statusCode == null` y mensajes como
  /// "No se pudo conectar al servidor FashionStore (...)": antes no se
  /// reconocía como fallo de red (el texto dice "conectar", no "connection")
  /// y el pago diferido offline nunca se ejecutaba.
  bool _esErrorDeConectividad(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode != null) return false;
      return true;
    }
    if (error is SocketException) return true;
    // Un ApiException con statusCode nulo significa "el servidor no
    // respondió": conexión caída, timeout o DNS. Un rechazo del servidor
    // (4xx/5xx) siempre trae código y NO se degrada.
    if (error is ApiException) return error.statusCode == null;
    final texto = error.toString().toLowerCase();
    return texto.contains('socket') ||
        texto.contains('connection') ||
        texto.contains('conectar') ||
        texto.contains('conexión') ||
        texto.contains('conexion') ||
        texto.contains('network') ||
        texto.contains('failed host lookup') ||
        texto.contains('connection refused') ||
        texto.contains('timeout') ||
        texto.contains('timed out');
  }

  /// URLs de retorno que el WebView in-app intercepta (ver
  /// `StripeWebViewPage`). Stripe acepta cualquier URL https válida.
  static String stripeAppSuccessUrl(int orderId) =>
      'https://fashionstore.app/pago-exito?orden_id=$orderId&session_id={CHECKOUT_SESSION_ID}';
  static String stripeAppCancelUrl(int orderId) =>
      'https://fashionstore.app/pago-cancelado?orden_id=$orderId';

  /// Crea la sesión de Stripe con URLs de retorno detectables por el
  /// WebView in-app. Devuelve la sesión o null (con `_errorMessage`).
  Future<StripeSessionResponse?> createStripeSession(int orderId) async {
    try {
      final session = await _orderService.createStripeCheckoutSession(
        orderId,
        successUrl: stripeAppSuccessUrl(orderId),
        cancelUrl: stripeAppCancelUrl(orderId),
      );
      _lastStripeSessionId = session.sessionId.isNotEmpty
          ? session.sessionId
          : null;
      _lastStripeOrderId = orderId;
      notifyListeners();
      if (session.checkoutUrl.isEmpty || _lastStripeSessionId == null) {
        _errorMessage =
            'Stripe no devolvió una sesión válida. Inténtalo de nuevo.';
        notifyListeners();
        return null;
      }
      return session;
    } catch (e) {
      _errorMessage = 'No se pudo iniciar el pago con Stripe: $e';
      notifyListeners();
      return null;
    }
  }

  /// Apertura en navegador externo (respaldo; el flujo principal es el
  /// WebView in-app vía [createStripeSession]).
  Future<bool> launchStripeCheckout(int orderId) async {
    try {
      final successUrl = AppConfig.paymentSuccessUrl.isNotEmpty
          ? '${AppConfig.paymentSuccessUrl}?orden_id=$orderId&session_id={CHECKOUT_SESSION_ID}'
          : null;
      final cancelUrl = AppConfig.paymentCancelUrl.isNotEmpty
          ? '${AppConfig.paymentCancelUrl}?orden_id=$orderId'
          : null;

      final session = await _orderService.createStripeCheckoutSession(
        orderId,
        successUrl: successUrl,
        cancelUrl: cancelUrl,
      );
      // Guardar la sesión para confirmar el pago al volver del navegador.
      _lastStripeSessionId = session.sessionId.isNotEmpty
          ? session.sessionId
          : null;
      _lastStripeOrderId = orderId;
      notifyListeners();
      if (session.checkoutUrl.isNotEmpty) {
        final uri = Uri.parse(session.checkoutUrl);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return false;
    } catch (e) {
      _errorMessage = 'No se pudo iniciar el portal de pago de Stripe: $e';
      notifyListeners();
      return false;
    }
  }

  /// Confirma el retorno de Stripe contra el backend (marca PAGADO,
  /// descuenta stock y genera comprobante). Llamar al volver del navegador
  /// externo o desde el botón "Ya pagué, verificar" del success.
  Future<bool> confirmarPagoStripe({String? sessionId, int? orderId}) async {
    final sid = sessionId ?? _lastStripeSessionId;
    final oid = orderId ?? _lastStripeOrderId ?? _lastCreatedOrder?.id;
    if (sid == null || sid.isEmpty || oid == null) return false;
    _isConfirmingPayment = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _orderService.confirmarStripeRetorno(sid, oid);
      final updated = await _orderService.getOrdenDetalle(oid);
      _lastCreatedOrder = updated;
      _isConfirmingPayment = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'No se pudo confirmar el pago: $e';
      _isConfirmingPayment = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> launchPayPalCheckout(int orderId) async {
    try {
      final returnUrl = AppConfig.paymentSuccessUrl.isNotEmpty
          ? '${AppConfig.paymentSuccessUrl}?orden_id=$orderId&paypal_order_id={PAYPAL_ORDER_ID}'
          : null;
      final cancelUrl = AppConfig.paymentCancelUrl.isNotEmpty
          ? '${AppConfig.paymentCancelUrl}?orden_id=$orderId'
          : null;

      final payPalOrder = await _orderService.createPayPalOrder(
        orderId,
        returnUrl: returnUrl,
        cancelUrl: cancelUrl,
      );
      _lastPayPalOrderId = payPalOrder.orderId.isNotEmpty
          ? payPalOrder.orderId
          : null;
      _lastPayPalInternalOrderId = orderId;
      notifyListeners();
      if (payPalOrder.approveUrl.isNotEmpty) {
        final uri = Uri.parse(payPalOrder.approveUrl);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return false;
    } catch (e) {
      _errorMessage = 'No se pudo iniciar el portal de pago de PayPal: $e';
      notifyListeners();
      return false;
    }
  }

  /// Captura el pago de PayPal al volver del navegador externo.
  Future<bool> confirmarPagoPayPal({
    String? paypalOrderId,
    int? orderId,
  }) async {
    final pid = paypalOrderId ?? _lastPayPalOrderId;
    final oid = orderId ?? _lastPayPalInternalOrderId ?? _lastCreatedOrder?.id;
    if (pid == null || pid.isEmpty || oid == null) return false;
    _isConfirmingPayment = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _orderService.capturePayPalOrder(pid, oid);
      final updated = await _orderService.getOrdenDetalle(oid);
      _lastCreatedOrder = updated;
      _isConfirmingPayment = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'No se pudo confirmar el pago: $e';
      _isConfirmingPayment = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loadOrderHistory() async {
    _isLoadingHistory = true;
    notifyListeners();

    try {
      _orderHistory = await _orderService.getOrdenes();
    } catch (e) {
      _orderHistory = [];
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }
}
