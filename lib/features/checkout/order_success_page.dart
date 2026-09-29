import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../core/models/order_model.dart';
import '../../core/providers/checkout_provider.dart';

/// Pantalla post-compra.
///
/// Flujo Stripe/PayPal en móvil: la app abre el portal de pago en un
/// navegador externo y, al volver, debe confirmar el retorno contra el
/// backend (`POST /pagos/stripe/confirmar-retorno`), igual que hace el
/// frontend web. Sin esa confirmación la orden queda en PENDIENTE_PAGO
/// aunque el cobro exista en Stripe.
class OrderSuccessPage extends StatefulWidget {
  final OrderModel? order;
  final String? stripeSessionId;
  final String? paypalOrderId;

  const OrderSuccessPage({
    super.key,
    this.order,
    this.stripeSessionId,
    this.paypalOrderId,
  });

  @override
  State<OrderSuccessPage> createState() => _OrderSuccessPageState();
}

class _OrderSuccessPageState extends State<OrderSuccessPage> {
  OrderModel? _order;
  bool _verifying = false;
  bool _autoTried = false;
  String? _verifyError;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    // Al volver del navegador externo, intentar confirmar automáticamente
    // si la orden sigue pendiente y tenemos IDs de pasarela.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConfirm());
  }

  Future<void> _autoConfirm() async {
    if (_autoTried || !mounted) return;
    _autoTried = true;
    final order = _order;
    if (order == null || !order.isPending) return;
    final hasStripe = (widget.stripeSessionId ?? '').isNotEmpty;
    final hasPayPal = (widget.paypalOrderId ?? '').isNotEmpty;
    if (!hasStripe && !hasPayPal) return;
    await _verifyPayment();
  }

  Future<void> _verifyPayment() async {
    if (!mounted) return;
    setState(() {
      _verifying = true;
      _verifyError = null;
    });
    final checkout = context.read<CheckoutProvider>();
    final orderId = _order?.id;
    bool ok = false;
    if ((widget.stripeSessionId ?? '').isNotEmpty && orderId != null) {
      ok = await checkout.confirmarPagoStripe(
        sessionId: widget.stripeSessionId,
        orderId: orderId,
      );
    } else if ((widget.paypalOrderId ?? '').isNotEmpty && orderId != null) {
      ok = await checkout.confirmarPagoPayPal(
        paypalOrderId: widget.paypalOrderId,
        orderId: orderId,
      );
    } else {
      // Sin IDs de pasarela no hay sesión que verificar en Stripe.
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verifyError =
            'No se encontró la sesión de pago de esta orden. Vuelve al checkout y genera el pago de nuevo.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _verifying = false;
      if (ok && checkout.lastCreatedOrder != null) {
        _order = checkout.lastCreatedOrder;
      }
      final stillPending = _order?.isPending ?? true;
      if (!ok) {
        _verifyError = checkout.errorMessage ??
            'Aún no se detecta el pago. Si ya pagaste, espera unos segundos y reintenta.';
      } else if (stillPending) {
        // El backend confirmó la consulta pero Stripe aún no marca pagado.
        _verifyError =
            'Stripe aún no registra tu pago. Revisa en el navegador que el cobro se haya completado y reintenta en unos segundos.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'es_BO',
      symbol: 'Bs. ',
      decimalDigits: 2,
    );
    final order = _order;
    final pending = order?.isPending ?? false;

    return WillPopScope(
      onWillPop: () async {
        context.go('/home');
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success / Pending Icon Circle
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: (pending
                              ? AppColors.warning
                              : AppColors.success)
                          .withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: _verifying
                          ? const SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Icon(
                              pending
                                  ? Icons.hourglass_top_rounded
                                  : Icons.check_circle_rounded,
                              color: pending
                                  ? AppColors.warning
                                  : AppColors.success,
                              size: 64,
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    pending ? '¡Pedido en espera de pago!' : '¡Pedido Confirmado!',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pending
                        ? 'Completaste el pedido pero el pago aún figura PENDIENTE. Si ya pagaste en el navegador, pulsa "Ya pagué, verificar pago".'
                        : 'Gracias por tu compra. Hemos recibido tu pedido correctamente y pronto comenzaremos a prepararlo.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  if (_verifyError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Text(
                        _verifyError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),

                  // Order Details Card
                  if (order != null)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('N° de Orden:', style: TextStyle(color: AppColors.textSecondary)),
                              Text(
                                order.numeroOrden,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Estado:', style: TextStyle(color: AppColors.textSecondary)),
                              Text(
                                order.estado,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: pending ? AppColors.warning : AppColors.success,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Método de Pago:', style: TextStyle(color: AppColors.textSecondary)),
                              Text(
                                order.metodoPago ?? 'Stripe',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          if (order.direccionEnvio != null) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Entrega:', style: TextStyle(color: AppColors.textSecondary)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${order.direccionEnvio!}, ${order.ciudadEnvio ?? 'Santa Cruz'}',
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                pending ? 'Total a pagar:' : 'Total Pagado:',
                                style: const TextStyle(color: AppColors.textSecondary),
                              ),
                              Text(
                                currencyFormatter.format(order.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accent,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Verify payment button (solo si sigue pendiente)
                  if (pending) ...[
                    ElevatedButton.icon(
                      onPressed: _verifying ? null : _verifyPayment,
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: Text(_verifying ? 'Verificando pago...' : 'Ya pagué, verificar pago'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Action Buttons
                  if (order != null && !pending) ...[
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/profile/orders/${order.id}'),
                      icon: const Icon(Icons.receipt_long_outlined,
                          size: 18),
                      label: const Text('Ver mi factura'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(
                            color: AppColors.accent),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton(
                    onPressed: () => context.go('/home'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Volver al Inicio', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => context.go('/catalog'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Seguir Explorando el Catálogo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
