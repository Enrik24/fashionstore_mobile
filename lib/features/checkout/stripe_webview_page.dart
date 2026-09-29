import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../config/theme.dart';
import '../../core/models/order_model.dart';
import '../../core/providers/checkout_provider.dart';

/// Pago con Stripe DENTRO de la app.
///
/// Detecta el retorno a nuestras URLs de éxito/cancelación
/// (`fashionstore.app/pago-exito|pago-cancelado`, que se envían al crear
/// la sesión) y confirma el pago contra el backend antes de mostrar el
/// resultado. Si el usuario cierra sin pagar, la orden queda pendiente y
/// la pantalla de éxito ofrece re-verificar.
class StripeWebViewPage extends StatefulWidget {
  final OrderModel order;
  final String checkoutUrl;
  final String sessionId;

  const StripeWebViewPage({
    super.key,
    required this.order,
    required this.checkoutUrl,
    required this.sessionId,
  });

  @override
  State<StripeWebViewPage> createState() => _StripeWebViewPageState();
}

class _StripeWebViewPageState extends State<StripeWebViewPage> {
  late final WebViewController _controller;
  bool _loadingPage = true;
  bool _confirming = false;
  bool _finished = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loadingPage = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loadingPage = false);
          },
          onWebResourceError: (error) {
            if (mounted && !_finished) {
              setState(() => _loadError =
                  'No se pudo cargar la página de pago (${error.description}). Revisa tu conexión e inténtalo de nuevo.');
            }
          },
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.contains('fashionstore.app/pago-exito')) {
              _onStripeFinished(paid: true);
              return NavigationDecision.prevent;
            }
            if (url.contains('fashionstore.app/pago-cancelado')) {
              _onStripeFinished(paid: false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  Future<void> _onStripeFinished({required bool paid}) async {
    if (_finished || !mounted) return;
    _finished = true;
    if (!paid) {
      // Canceló en Stripe: mostrar el success en pendiente (con verificar).
      context.go('/checkout/success', extra: {
        'order': widget.order,
        'stripeSessionId': widget.sessionId,
      });
      return;
    }
    setState(() => _confirming = true);
    final checkout = context.read<CheckoutProvider>();
    final ok = await checkout.confirmarPagoStripe(
      sessionId: widget.sessionId,
      orderId: widget.order.id,
    );
    if (!mounted) return;
    final updated = checkout.lastCreatedOrder ?? widget.order;
    if (!ok) {
      // La confirmación dirá el motivo en la pantalla de éxito.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(checkout.errorMessage ??
              'Stripe aún no registra el pago. Usa "Ya pagué, verificar pago".'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
    context.go('/checkout/success', extra: {
      'order': updated,
      'stripeSessionId': widget.sessionId,
    });
  }

  Future<void> _confirmExit() async {
    // Salir sin pagar: la orden queda pendiente, verificable después.
    if (_confirming) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del pago'),
        content: const Text(
            'Si sales ahora, tu pedido queda en espera de pago y podrás verificarlo después.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Seguir pagando')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Salir')),
        ],
      ),
    );
    if (leave == true && mounted) {
      context.go('/checkout/success', extra: {
        'order': widget.order,
        'stripeSessionId': widget.sessionId,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _confirmExit();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pago con tarjeta'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmExit,
          ),
        ),
        body: Stack(
          children: [
            if (_loadError == null)
              WebViewWidget(controller: _controller)
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          size: 56, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      Text(_loadError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _loadError = null);
                          _controller.loadRequest(Uri.parse(widget.checkoutUrl));
                        },
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loadingPage && _loadError == null)
              const Center(child: CircularProgressIndicator()),
            if (_confirming)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text('Confirmando tu pago...',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
