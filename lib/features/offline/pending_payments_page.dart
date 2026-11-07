import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'deferred_payment_sheet.dart';

import '../../core/providers/pending_payment_provider.dart';

/// [EXAMEN-2] Pagos diferidos pendientes y cuenta regresiva (CU16).
class PendingPaymentsPage extends StatelessWidget {
  const PendingPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PendingPaymentProvider>();
    return Scaffold(
      appBar: AppBar(title: Text('Pagos diferidos (${provider.pendingCount})')),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.payments.isEmpty
          ? const Center(child: Text('No hay pagos diferidos pendientes'))
          : ListView.builder(
              itemCount: provider.payments.length,
              itemBuilder: (context, index) {
                final pago = provider.payments[index];
                final restante = pago.cuentaRegresiva;
                return Card(
                  margin: const EdgeInsets.all(12),
                  child: ListTile(
                    title: Text(pago.uuidOrden ?? pago.uuidPago),
                    subtitle: Text(
                      '${pago.monto.toStringAsFixed(2)} ${pago.moneda} · '
                      '${restante == null ? 'Sin vencimiento' : '${restante.inMinutes}:${(restante.inSeconds % 60).toString().padLeft(2, '0')}'}',
                    ),
                    trailing: Text(pago.estado),
                    isThreeLine: true,
                    onTap: () async {
                      await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) =>
                            DeferredPaymentSheet(uuidPago: pago.uuidPago),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
