import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/coupon_model.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/coupon_service.dart';

/// Tarjeta "Cupón de descuento" del carrito (CU27).
///
/// Permite aplicar un código (`POST /carrito/aplicar-cupon`), muestra el
/// chip con el código aplicado y el monto, y permite quitarlo. Incluye el
/// bottom sheet "Mis cupones disponibles".
class CouponCard extends StatefulWidget {
  const CouponCard({super.key});

  @override
  State<CouponCard> createState() => _CouponCardState();
}

class _CouponCardState extends State<CouponCard> {
  final _controller = TextEditingController();
  bool _isApplying = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String codigo) async {
    final code = codigo.trim();
    if (code.isEmpty) return;
    setState(() => _isApplying = true);
    final cart = context.read<CartProvider>();
    final ok = await cart.applyCoupon(code);
    if (!mounted) return;
    setState(() => _isApplying = false);
    if (ok) {
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cupón $code aplicado: descuento de Bs. '
              '${cart.discount.toStringAsFixed(2)}'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Mensaje del backend (expirado, agotado, no aplicable, mínimo).
          content: Text(cart.errorMessage ?? 'No se pudo aplicar el cupón'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _remove() async {
    final cart = context.read<CartProvider>();
    final ok = await cart.removeCoupon();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Cupón eliminado'
            : (cart.errorMessage ?? 'No se pudo quitar el cupón')),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _showAvailable() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _AvailableCouponsSheet(
        onUse: (codigo) {
          Navigator.of(sheetContext).pop();
          _controller.text = codigo;
          _apply(codigo);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CartProvider>(
      builder: (context, cart, _) {
        final applied = cart.cuponCodigo;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_offer_outlined,
                      color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Cupón de descuento',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (applied == null)
                    TextButton(
                      onPressed: _showAvailable,
                      child: const Text('Ver disponibles',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (applied != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.success.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(applied,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success)),
                            Text(
                              'Descuento: Bs. ${cart.discount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.success),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: AppColors.textSecondary),
                        tooltip: 'Quitar cupón',
                        onPressed:
                            cart.isUpdating ? null : _remove,
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textCapitalization:
                            TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'Ej. BIENVENIDA10',
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                        ),
                        onSubmitted: (_) =>
                            _isApplying ? null : _apply(_controller.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isApplying || cart.isUpdating
                          ? null
                          : () => _apply(_controller.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: _isApplying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Aplicar',
                              style:
                                  TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Bottom sheet "Mis cupones disponibles" (CU27).
class _AvailableCouponsSheet extends StatefulWidget {
  final ValueChanged<String> onUse;

  const _AvailableCouponsSheet({required this.onUse});

  @override
  State<_AvailableCouponsSheet> createState() =>
      _AvailableCouponsSheetState();
}

class _AvailableCouponsSheetState extends State<_AvailableCouponsSheet> {
  List<CouponModel>? _coupons;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service =
          CouponService(apiService: context.read<ApiService>());
      final list = await service.getDisponibles();
      if (mounted) setState(() => _coupons = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 12),
            Text('Mis cupones disponibles',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_coupons == null && _error == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                      color: AppColors.accent),
                ),
              )
            else if (_error != null)
              Text(_error!,
                  style: const TextStyle(color: AppColors.error))
            else if (_coupons!.isEmpty)
              const Text(
                'No tienes cupones disponibles por ahora.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _coupons!.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = _coupons![i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppColors.accent
                                .withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(c.codigo,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(c.valorLabel,
                                    style: const TextStyle(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w600)),
                                if (c.descripcion != null)
                                  Text(c.descripcion!,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors
                                              .textSecondary)),
                                if (c.fechaFin != null)
                                  Text(
                                    'Válido hasta ${dateFormat.format(c.fechaFin!)}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color:
                                            AppColors.textMuted),
                                  ),
                                if (!c.aplicaATodo)
                                  const Text(
                                    'Aplica a productos seleccionados',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            AppColors.warning),
                                  ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => widget.onUse(c.codigo),
                            child: const Text('Usar',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
