import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/comprobante_model.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/payment_transaction_model.dart';
import '../../../core/providers/checkout_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/order_service.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../returns/request_return_page.dart' show kPlazoDevolucionDias;

class OrderDetailPage extends StatefulWidget {
  final int orderId;

  const OrderDetailPage({
    super.key,
    required this.orderId,
  });

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  OrderModel? _order;
  bool _isLoading = true;
  String? _error;
  ComprobanteModel? _comprobante;
  bool _isLoadingComprobante = false;
  List<PaymentTransactionModel> _transacciones = [];
  bool _isLoadingTx = false;
  bool _isRetryingPayment = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final orderService = OrderService(apiService: context.read<ApiService>());
      final order = await orderService.getOrdenDetalle(widget.orderId);
      if (mounted) {
        setState(() {
          _order = order;
          // El detalle ya puede traer el comprobante anidado.
          _comprobante = order.comprobante;
          _isLoading = false;
        });
        // Si la orden no está pagada, consultar el estado del pago (CU18).
        if (!order.isPaid && !order.isCancelled) {
          _loadTransacciones();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Historial de transacciones de pago de la orden (CU18).
  Future<void> _loadTransacciones() async {
    if (!mounted) return;
    setState(() => _isLoadingTx = true);
    try {
      final orderService = OrderService(apiService: context.read<ApiService>());
      final txs = await orderService.getTransacciones(widget.orderId);
      if (mounted) {
        setState(() {
          _transacciones = txs;
          _isLoadingTx = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingTx = false);
      }
    }
  }

  /// Reintenta el pago con la pasarela original (CU18).
  Future<void> _retryPayment(OrderModel order) async {
    final metodo = (order.metodoPago ?? '').toUpperCase();
    if (!metodo.contains('STRIPE') && !metodo.contains('PAYPAL')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Este método de pago se completa en tienda o con QR'),
        ),
      );
      return;
    }
    setState(() => _isRetryingPayment = true);
    try {
      final checkout = context.read<CheckoutProvider>();
      final ok = metodo.contains('STRIPE')
          ? await checkout.launchStripeCheckout(order.id)
          : await checkout.launchPayPalCheckout(order.id);
      if (!mounted) return;
      setState(() => _isRetryingPayment = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(checkout.errorMessage ??
                'No se pudo reintentar el pago'),
            backgroundColor: AppColors.error,
          ),
        );
      } else {
        // Al volver del portal externo, refrescar orden y transacciones.
        await _loadDetail();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRetryingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Obtiene (o genera en el backend) el comprobante de la orden.
  Future<void> _fetchComprobante() async {
    setState(() => _isLoadingComprobante = true);
    try {
      final orderService = OrderService(apiService: context.read<ApiService>());
      final comp = await orderService.getComprobante(widget.orderId);
      if (mounted) {
        setState(() {
          _comprobante = comp;
          _isLoadingComprobante = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingComprobante = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  bool _isOpeningPdf = false;

  /// Descarga el PDF con el cliente autenticado y lo abre en el visor
  /// del sistema. Muestra el motivo real si algo falla.
  Future<void> _openComprobantePdf() async {
    if (_isOpeningPdf) return;
    setState(() => _isOpeningPdf = true);
    try {
      final orderService = OrderService(apiService: context.read<ApiService>());
      final bytes = await orderService.descargarComprobantePdf(widget.orderId);
      final dir = await getTemporaryDirectory();
      final numero = _comprobante?.numero
              .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_') ??
          'orden_${widget.orderId}';
      final file = File('${dir.path}/comprobante_$numero.pdf');
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path, type: 'application/pdf');
      if (mounted && result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'PDF guardado pero no se pudo abrir: ${result.message} (${file.path})'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir el comprobante: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningPdf = false);
    }
  }

  /// La orden permite valorar sus prendas (CU26: compradas o en curso).
  bool _orderAllowsReview(OrderModel order) {
    return {
      'PAGADO',
      'EN_PROCESO',
      'ENVIADO',
      'ENTREGADO',
      'COMPLETADO',
    }.contains(order.estado.toUpperCase());
  }

  Color _getStatusColor(String status) {    switch (status.toUpperCase()) {
      case 'PAGADO':
      case 'COMPLETADO':
        return AppColors.success;
      case 'PENDIENTE':
        return AppColors.warning;
      case 'CANCELADO':
        return AppColors.error;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: _order?.numeroOrden ?? 'Detalle del Pedido',
        showBackButton: true,
      ),
      body: _isLoading && _order == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null && _order == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 60, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadDetail,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _loadDetail,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatusHeader(_order!, dateFormat),
                        const SizedBox(height: 20),
                        if (!_order!.isPaid && !_order!.isCancelled)
                          _buildPaymentSection(_order!),
                        if (!_order!.isPaid && !_order!.isCancelled)
                          const SizedBox(height: 20),
                        _buildItemsSection(_order!),
                        const SizedBox(height: 20),
                        _buildSummaryCard(_order!),
                        const SizedBox(height: 20),
                        _buildComprobanteSection(_order!),
                        const SizedBox(height: 20),
                        _buildShippingInfo(_order!),
                        const SizedBox(height: 20),
                        _buildReturnAction(_order!),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatusHeader(OrderModel order, DateFormat dateFormat) {
    final statusColor = _getStatusColor(order.estado);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order.numeroOrden,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  order.estado.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textLight),
              const SizedBox(width: 6),
              Text(
                order.createdAt != null ? dateFormat.format(order.createdAt!) : 'N/A',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textLight),
              ),
              if (order.metodoPago != null) ...[
                const SizedBox(width: 16),
                const Icon(Icons.payment_outlined, size: 14, color: AppColors.textLight),
                const SizedBox(width: 6),
                Text(
                  order.metodoPago!,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textLight),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection(OrderModel order) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Artículos (${order.items.length})',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...order.items.map((item) => _buildItemRow(
              item, _orderAllowsReview(order))),
        ],
      ),
    );
  }

  Widget _buildItemRow(OrderItemModel item, bool allowsReview) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 50,
              height: 50,
              child: item.productoImagen != null && item.productoImagen!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.productoImagen!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.checkroom),
                    )
                  : const Icon(Icons.checkroom, color: AppColors.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productoNombre,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.cantidad}x  Bs. ${item.precioUnitario.toStringAsFixed(2)}  ${item.talla != null ? '• Talla ${item.talla}' : ''}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight),
                ),
                // Botón Valorar (CU26): abre el detalle con la sección de valoraciones.
                if (allowsReview && item.productoId > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          context.push('/catalog/${item.productoId}'),
                      icon: const Icon(Icons.star_outline,
                          size: 14, color: AppColors.accent),
                      label: const Text('Valorar',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'Bs. ${item.subtotal.toStringAsFixed(2)}',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(OrderModel order) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de Pago',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow('Subtotal', 'Bs. ${order.subtotal.toStringAsFixed(2)}'),
          if (order.costoEnvio > 0)
            _buildSummaryRow('Envío', 'Bs. ${order.costoEnvio.toStringAsFixed(2)}'),
          if (order.impuestos > 0)
            _buildSummaryRow(
                'Impuestos', 'Bs. ${order.impuestos.toStringAsFixed(2)}'),
          if (order.descuento > 0)
            _buildSummaryRow(
              'Descuento',
              '- Bs. ${order.descuento.toStringAsFixed(2)}',
              isDiscount: true,
            ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Pagado',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                'Bs. ${order.total.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDiscount ? AppColors.success : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  /// Botón "Solicitar devolución/cambio" (CU28): visible solo dentro del plazo.
  Widget _buildReturnAction(OrderModel order) {
    final created = order.createdAt;
    final withinPlazo = created == null ||
        DateTime.now().difference(created).inDays <=
            kPlazoDevolucionDias;

    if (!withinPlazo) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                size: 20, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Esta orden superó el plazo de $kPlazoDevolucionDias días para devoluciones.',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    // Solo órdenes compradas/en curso pueden devolverse.
    final eligible = {
      'PAGADO',
      'EN_PROCESO',
      'ENVIADO',
      'ENTREGADO',
      'COMPLETADO',
    }.contains(order.estado.toUpperCase());
    if (!eligible) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () =>
            context.push('/profile/orders/${order.id}/return'),
        icon: const Icon(Icons.assignment_return_outlined, size: 18),
        label: const Text('Solicitar devolución o cambio'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.accent),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Sección de estado del pago con reintento (CU18).
  Widget _buildPaymentSection(OrderModel order) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    Color txColor(PaymentTransactionModel tx) {
      if (tx.isConfirmed) return AppColors.success;
      if (tx.isRejected) return AppColors.error;
      if (tx.isRefunded) return AppColors.primary;
      return AppColors.warning;
    }

    String txLabel(PaymentTransactionModel tx) {
      if (tx.isConfirmed) return 'Confirmado';
      if (tx.isRejected) return 'Rechazado';
      if (tx.isRefunded) return 'Reembolsado';
      return 'Pendiente';
    }

    final metodo = (order.metodoPago ?? '').toUpperCase();
    final retryable =
        metodo.contains('STRIPE') || metodo.contains('PAYPAL');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payment_outlined,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Estado del pago',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh,
                    size: 18, color: AppColors.textSecondary),
                tooltip: 'Verificar estado',
                onPressed:
                    _isLoadingTx ? null : _loadTransacciones,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoadingTx)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent),
              ),
            )
          else if (_transacciones.isEmpty)
            Text(
              'Aún no hay transacciones registradas para esta orden.',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary),
            )
          else
            ..._transacciones.map((tx) {
              final color = txColor(tx);
              return Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.receipt_long_outlined,
                          size: 18, color: color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tx.metodoPago} • Bs. ${tx.monto.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                          if (tx.fecha != null)
                            Text(
                              dateFormat.format(tx.fecha!),
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.textLight),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        txLabel(tx),
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (retryable) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isRetryingPayment
                    ? null
                    : () => _retryPayment(order),
                icon: _isRetryingPayment
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar pago'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side:
                      const BorderSide(color: AppColors.accent),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Sección del comprobante / factura de la orden.
  Widget _buildComprobanteSection(OrderModel order) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_outlined,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Comprobante',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_comprobante != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _comprobante!.numero,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _comprobante!.tipoLabel,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_comprobante!.fechaEmision != null ? dateFormat.format(_comprobante!.fechaEmision!) : ''}'
              '  •  Bs. ${_comprobante!.montoTotal.toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isOpeningPdf ? null : _openComprobantePdf,
                icon: _isOpeningPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined,
                        size: 18, color: Colors.white),
                label: Text(_isOpeningPdf ? 'Abriendo PDF...' : 'Ver / Descargar PDF',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else ...[
            Text(
              'Obtén tu factura o ticket de compra en PDF.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _isLoadingComprobante ? null : _fetchComprobante,
                icon: _isLoadingComprobante
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2),
                      )
                    : const Icon(Icons.receipt_long_outlined,
                        size: 18),
                label: const Text('Obtener comprobante'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side:
                      const BorderSide(color: AppColors.accent),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShippingInfo(OrderModel order) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detalles de Entrega & Contacto',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (order.direccionEnvio != null && order.direccionEnvio!.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.local_shipping_outlined, size: 20, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dirección de Envío', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight)),
                      Text(
                        '${order.direccionEnvio!}${order.ciudadEnvio != null ? ', ${order.ciudadEnvio}' : ''}',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (order.sucursalNombre != null) ...[
            Row(
              children: [
                const Icon(Icons.store_outlined, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Retiro en Tienda', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight)),
                      Text(order.sucursalNombre!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (order.telefonoContacto != null) ...[
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Teléfono de Contacto', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight)),
                      Text(order.telefonoContacto!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
