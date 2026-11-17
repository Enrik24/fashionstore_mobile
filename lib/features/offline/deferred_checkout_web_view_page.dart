import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/theme.dart';

/// Detecta la URL de retorno que configura el backend en el Checkout Session
/// de un pago diferido:
///   `{STRIPE_PAGO_DIFERIDO_SUCCESS_URL}/{uuid_pago}?retorno=exito`
///   `{STRIPE_PAGO_DIFERIDO_CANCEL_URL}/{uuid_pago}?retorno=cancelado`
bool esRetornoCheckoutDiferido(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final path = uri.path.toLowerCase();
  final retorno = uri.queryParameters['retorno']?.toLowerCase();
  return path.contains('pago-pendiente') ||
      path.contains('pago-exito') ||
      path.contains('pago-cancelado') ||
      retorno == 'exito' ||
      retorno == 'cancelado';
}

bool esRetornoCancelado(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.queryParameters['retorno']?.toLowerCase() == 'cancelado' ||
      uri.path.toLowerCase().contains('pago-cancelado');
}

/// Checkout de Stripe para un pago diferido **dentro de la app**.
///
/// El backend crea una Checkout Session (sin `client_secret`) y devuelve
/// `checkout_url`. En lugar de salir al navegador del dispositivo se carga
/// aquí. Cuando Stripe redirige a la URL de éxito/cancelación se intercepta
/// la navegación y se confirma el cobro contra el backend.
class DeferredCheckoutWebViewPage extends StatefulWidget {
  const DeferredCheckoutWebViewPage({
    super.key,
    required this.checkoutUrl,
    required this.uuidPago,
    required this.onConfirmar,
  });

  final String checkoutUrl;
  final String uuidPago;

  /// Confirma el cobro en el servidor. Devuelve `true` si quedó confirmado.
  final Future<bool> Function() onConfirmar;

  @override
  State<DeferredCheckoutWebViewPage> createState() =>
      _DeferredCheckoutWebViewPageState();
}

class _DeferredCheckoutWebViewPageState
    extends State<DeferredCheckoutWebViewPage> {
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
              setState(() {
                _loadError = 'No se pudo cargar el checkout de Stripe '
                    '(${error.description}). Revisa tu conexión e inténtalo '
                    'de nuevo.';
              });
            }
          },
          onNavigationRequest: (request) {
            if (_finished || !esRetornoCheckoutDiferido(request.url)) {
              return NavigationDecision.navigate;
            }
            _onStripeFinished(
              cancelado: esRetornoCancelado(request.url),
            );
            // No cargamos la web del frontend dentro del WebView.
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  Future<void> _onStripeFinished({required bool cancelado}) async {
    if (_finished || !mounted) return;
    if (cancelado) {
      _finished = true;
      Navigator.of(context).pop(false);
      return;
    }
    _finished = true;
    setState(() => _confirming = true);
    try {
      final ok = await widget.onConfirmar();
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _confirming = false;
        _finished = false;
        _loadError = 'Stripe aún no registra el pago en el servidor. '
            'Termina el cobro y vuelve a verificar.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _finished = false;
        _loadError = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _confirmExit() async {
    if (_confirming) return;
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del pago'),
        content: const Text(
          'Si sales ahora, el pago queda pendiente y podrás verificarlo '
          'después desde «Pagos diferidos».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seguir pagando'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (salir == true && mounted) Navigator.of(context).pop(false);
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
          title: const Text('Pago seguro'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmExit,
          ),
          actions: [
            TextButton(
              onPressed: _confirming
                  ? null
                  : () => _onStripeFinished(cancelado: false),
              child: const Text('Ya pagué'),
            ),
          ],
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        size: 52,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
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
                      Text(
                        'Confirmando tu pago...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
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
