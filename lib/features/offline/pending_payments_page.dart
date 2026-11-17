// [EXAMEN-2] CU16: pagos diferidos pendientes, cuenta regresiva y reintento.
//
// [FIX-UI] La lista mostraba el UUID completo como título y la cuenta
// regresiva en minutos totales (`1439:16`). Ahora: referencia corta de
// pedido, contador legible en vivo (`23 h 59 min` / `MM:SS`) y estado en
// lenguaje natural.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../core/models/phase2_models.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/pending_payment_provider.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/pago_referencia.dart';
import 'deferred_payment_sheet.dart';

/// [EXAMEN-2] Pagos diferidos pendientes y cuenta regresiva (CU16).
class PendingPaymentsPage extends StatefulWidget {
  const PendingPaymentsPage({super.key});

  @override
  State<PendingPaymentsPage> createState() => _PendingPaymentsPageState();
}

class _PendingPaymentsPageState extends State<PendingPaymentsPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresca la cuenta regresiva sin depender de eventos del servidor.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PendingPaymentProvider>().load();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// [EXAMEN-2] B1.7.c: reintenta el pago diferido contra el servidor.
  Future<void> _reintentar(
    BuildContext context,
    PendingPaymentProvider provider,
    String uuidPago,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.retry(uuidPago);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Se solicitó el reintento del pago'
              : provider.errorMessage ?? 'No se pudo reintentar el pago',
        ),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _abrirPago(BuildContext context, String uuidPago) async {
    final messenger = ScaffoldMessenger.of(context);
    final pagado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeferredPaymentSheet(uuidPago: uuidPago),
    );
    if (pagado == true && context.mounted) {
      // [FIX] Tras pagar, el carrito ya fue convertido en orden y borrado de
      // SQLite. Refrescamos desde el servidor para que no quede ningún ítem
      // offline en memoria (el backend marca el carrito como CONVERTIDO).
      await context.read<CartProvider>().loadCart();
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pago confirmado correctamente.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PendingPaymentProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Pagos diferidos')),
      body: provider.isLoading && provider.payments.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : provider.payments.isEmpty
          ? _Vacio()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _Resumen(provider: provider),
                const SizedBox(height: 12),
                for (final pago in provider.payments) ...[
                  _PagoCard(
                    pago: pago,
                    onReintentar: pago.estaPendiente
                        ? () => _reintentar(context, provider, pago.uuidPago)
                        : null,
                    onTap: () => _abrirPago(context, pago.uuidPago),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _Vacio extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.credit_card_outlined,
                size: 56,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sin pagos diferidos',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando confirmes un pedido sin conexión, el pago quedará '
              'guardado aquí para completarlo al volver a estar en línea.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.provider});

  final PendingPaymentProvider provider;

  @override
  Widget build(BuildContext context) {
    final cantidad = provider.pendingCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$cantidad ${cantidad == 1 ? 'pedido pendiente' : 'pedidos pendientes'} '
              '· ${provider.pendingAmount.toStringAsFixed(2)} BOB por cobrar',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PagoCard extends StatelessWidget {
  const _PagoCard({
    required this.pago,
    required this.onTap,
    this.onReintentar,
  });

  final PendingPaymentModel pago;
  final VoidCallback onTap;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    final restante = pago.cuentaRegresiva;
    final vencido = restante != null && restante <= Duration.zero;
    final urgente = restante != null && restante.inHours < 1 && !vencido;
    final colorEstado = vencido
        ? AppColors.error
        : pago.requiereAccion
        ? AppColors.success
        : AppColors.warning;
    final colorContador = vencido
        ? AppColors.error
        : urgente
        ? AppColors.warning
        : AppColors.textSecondary;
    final referencia = referenciaCorta(pago.uuidOrden ?? pago.uuidPago);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorEstado.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  pago.requiereAccion
                      ? Icons.credit_card
                      : Icons.schedule_outlined,
                  color: colorEstado,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pedido #$referencia',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorEstado.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            etiquetaEstadoPago(pago.estado),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colorEstado,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pago.monto.toStringAsFixed(2)} ${pago.moneda}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: colorContador,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            vencido
                                ? 'Vencido'
                                : 'Vence en ${CountdownFormat.legible(restante)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorContador,
                              fontWeight: urgente || vencido
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (pago.ultimoError != null &&
                        pago.ultimoError!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 14,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              pago.ultimoError!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onReintentar != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.refresh,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Reintentar el pago',
                  onPressed: onReintentar,
                ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}