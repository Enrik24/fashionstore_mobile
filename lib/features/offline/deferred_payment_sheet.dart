import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';

import '../../core/providers/pending_payment_provider.dart';

/// PaymentSheet del pago diferido. El `client_secret` solo existe en memoria.
class DeferredPaymentSheet extends StatefulWidget {
  const DeferredPaymentSheet({super.key, required this.uuidPago});

  final String uuidPago;

  @override
  State<DeferredPaymentSheet> createState() => _DeferredPaymentSheetState();
}

class _DeferredPaymentSheetState extends State<DeferredPaymentSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _confirmar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = context.read<PendingPaymentProvider>();
      final secret = await provider.prepararPaymentSheet(widget.uuidPago);
      if (secret == null) {
        throw StateError(
          'El pago aun no esta disponible. Espera la sincronizacion.',
        );
      }
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: secret,
          merchantDisplayName: 'FashionStore',
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      await Stripe.instance.confirmPaymentSheetPayment();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          Text('Pago diferido ${widget.uuidPago}', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'Stripe procesa el cobro en el dispositivo; la app no guarda datos de tarjeta.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _confirmar,
            child: Text(_loading ? 'Preparando pago...' : 'Pagar ahora'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}
