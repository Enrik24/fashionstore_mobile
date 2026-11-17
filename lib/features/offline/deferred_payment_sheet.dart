import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../core/models/phase2_models.dart';
import '../../core/providers/pending_payment_provider.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/pago_referencia.dart';
import 'deferred_checkout_web_view_page.dart';

/// PaymentSheet del pago diferido. El `client_secret` solo existe en memoria.
///
/// [FIX-UI] Antes el título mostraba el UUID completo del pago. Ahora usa una
/// referencia corta, el monto y el estado legible del pedido.
class DeferredPaymentSheet extends StatefulWidget {
  const DeferredPaymentSheet({super.key, required this.uuidPago});

  final String uuidPago;

  @override
  State<DeferredPaymentSheet> createState() => _DeferredPaymentSheetState();
}

class _DeferredPaymentSheetState extends State<DeferredPaymentSheet> {
  bool _loading = false;
  String? _error;

  String _mensajeError(Object error) =>
      error.toString().replaceFirst('Bad state: ', '');

  void _fallar(Object error) {
    if (mounted) setState(() => _error = _mensajeError(error));
  }

  Future<void> _confirmar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final navigator = Navigator.of(context);
      final provider = context.read<PendingPaymentProvider>();
      final preparacion = await provider.prepararPago(widget.uuidPago);

      if (preparacion.usaPaymentSheet) {
        // PaymentIntent (o modo simulado): cobro nativo con PaymentSheet.
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: preparacion.clientSecret!,
            merchantDisplayName: 'FashionStore',
          ),
        );
        await Stripe.instance.presentPaymentSheet();
        await Stripe.instance.confirmPaymentSheetPayment();
        provider.olvidarClientSecret(widget.uuidPago);
        if (mounted) navigator.pop(true);
        return;
      }

      if (preparacion.usaRedirect) {
        // Checkout Session: Stripe no entrega client_secret, solo la URL.
        // Se abre en un WebView DENTRO de la app (no en Chrome).
        final uri = Uri.tryParse(preparacion.checkoutUrl!);
        if (uri == null || !uri.hasScheme) {
          throw StateError(
            'El servidor devolvió una URL de checkout inválida.',
          );
        }
        final confirmado = await navigator.push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => DeferredCheckoutWebViewPage(
              checkoutUrl: preparacion.checkoutUrl!,
              uuidPago: widget.uuidPago,
              onConfirmar: () => provider.confirm(widget.uuidPago),
            ),
          ),
        );
        if (confirmado == true && mounted) navigator.pop(true);
        return;
      }

      throw StateError(
        'El pago aún no está disponible en el servidor. '
        'Sincroniza tus pedidos pendientes e inténtalo de nuevo.',
      );
    } catch (error) {
      _fallar(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PendingPaymentProvider>();
    PendingPaymentModel? pago;
    for (final p in provider.payments) {
      if (p.uuidPago == widget.uuidPago) {
        pago = p;
        break;
      }
    }
    final restante = pago?.cuentaRegresiva;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pago diferido',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Pedido #${referenciaCorta(pago?.uuidOrden ?? widget.uuidPago)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (pago != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${pago.monto.toStringAsFixed(2)} ${pago.moneda}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: restante != null && restante.inHours < 1
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      restante == null
                          ? etiquetaEstadoPago(pago.estado)
                          : '${etiquetaEstadoPago(pago.estado)} · vence en '
                                '${CountdownFormat.legible(restante)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Stripe procesa el cobro de forma segura; la app no guarda '
                'datos de tarjeta.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _confirmar,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Pagar ahora',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}