import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/checkout_provider.dart';
import 'widgets/shipping_form.dart';
import 'widgets/payment_method_selector.dart';
import 'widgets/order_summary_widget.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();

  Future<void> _processOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final cartProvider = context.read<CartProvider>();
    final checkoutProvider = context.read<CheckoutProvider>();

    if (cartProvider.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu carrito está vacío')),
      );
      return;
    }

    final order = await checkoutProvider.createOrder(
      items: cartProvider.items,
    );

    if (!mounted) return;

    if (order != null) {
      // Stripe: pagar DENTRO de la app (WebView) con retorno automático.
      if (checkoutProvider.paymentMethod == 'STRIPE') {
        final session = await checkoutProvider.createStripeSession(order.id);
        if (!mounted) return;
        if (session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(checkoutProvider.errorMessage ??
                  'No se pudo iniciar el pago con Stripe'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
        // Clear cart locally (el backend ya convirtió el carrito en orden)
        await cartProvider.clearCart();
        if (!mounted) return;
        context.push(
          '/checkout/stripe',
          extra: {
            'order': order,
            'checkoutUrl': session.checkoutUrl,
            'sessionId': session.sessionId,
          },
        );
        return;
      }

      // PayPal sigue en navegador externo: abrirlo antes de mostrar el éxito.
      if (checkoutProvider.paymentMethod == 'PAYPAL') {
        final opened = await checkoutProvider.launchPayPalCheckout(order.id);
        if (!mounted) return;
        if (!opened) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(checkoutProvider.errorMessage ??
                  'No se pudo abrir PayPal'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
      }
      final paypalOrderId = checkoutProvider.lastPayPalOrderId;
      // Clear cart locally
      await cartProvider.clearCart();
      if (!mounted) return;

      // Navigate to order success (lleva los IDs para verificar el pago)
      context.go(
        '/checkout/success',
        extra: {
          'order': order,
          if (paypalOrderId != null) 'paypalOrderId': paypalOrderId,
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(checkoutProvider.errorMessage ?? 'Error al procesar el pedido'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final checkoutProvider = context.watch<CheckoutProvider>();
    
    final isPickup = checkoutProvider.deliveryType == 'PICKUP';
    final shippingCost = isPickup ? 0.0 : (cartProvider.subtotal > 300 ? 0.0 : 20.0);
    final total = (cartProvider.subtotal - cartProvider.discount) + shippingCost;

    String getButtonLabel() {
      switch (checkoutProvider.paymentMethod) {
        case 'STRIPE':
          return 'Pagar con Tarjeta (Stripe)';
        case 'PAYPAL':
          return 'Pagar con PayPal';
        case 'QR':
          return 'Generar Pago con QR';
        case 'EFECTIVO':
        default:
          return 'Confirmar Pedido';
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Confirmar Pedido'),
      ),
      body: cartProvider.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No hay artículos para comprar.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.go('/catalog'),
                    child: const Text('Ir al Catálogo'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShippingFormWidget(formKey: _formKey),
                  const SizedBox(height: 16),
                  const PaymentMethodSelector(),
                  const SizedBox(height: 16),
                  OrderSummaryWidget(
                    items: cartProvider.items,
                    subtotal: cartProvider.subtotal,
                    discount: cartProvider.discount,
                    couponCode: cartProvider.cuponCodigo,
                    shippingCost: shippingCost,
                    total: total > 0 ? total : 0.0,
                    deliveryType: checkoutProvider.deliveryType,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: checkoutProvider.isProcessing ? null : _processOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: checkoutProvider.isProcessing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('Procesando Orden...'),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.lock_outline, size: 20, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                getButtonLabel(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
