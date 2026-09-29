import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/providers/return_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/catalog_service.dart';
import '../../../core/services/order_service.dart';
import '../../../core/services/return_service.dart';
import '../../../core/models/return_request_model.dart';
import '../../../core/widgets/custom_app_bar.dart';

/// Plazo de devolución en días (espejo de `PLAZO_DEVOLUCION_DIAS` del backend).
const int kPlazoDevolucionDias = 30;

/// Página para solicitar una devolución o cambio desde una orden (CU28).
///
/// Flujo: selección de prendas (checkbox + cantidad) → tipo (Cambio /
/// Devolución) + motivo + detalle → (si es cambio) nueva variante con
/// stock → confirmación con monto estimado → `POST /devoluciones/`.
class RequestReturnPage extends StatefulWidget {
  final int orderId;

  const RequestReturnPage({super.key, required this.orderId});

  @override
  State<RequestReturnPage> createState() => _RequestReturnPageState();
}

class _ItemSelection {
  final OrderItemModel item;
  bool selected = false;
  int cantidad;
  int? varianteCambioId;

  _ItemSelection({required this.item})
      : cantidad = item.cantidad > 0 ? 1 : 1;
}

class _RequestReturnPageState extends State<RequestReturnPage> {
  OrderModel? _order;
  bool _isLoading = true;
  String? _error;
  List<_ItemSelection> _selections = [];

  bool _isCambio = false;
  String _motivo = MotivosDevolucion.tallaIncorrecta;
  final _detalleController = TextEditingController();

  /// Variantes con stock por producto (para cambios).
  final Map<int, List<DisponibilidadItem>> _availabilityByProduct = {};
  final Set<int> _loadingAvailability = {};

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  @override
  void dispose() {
    _detalleController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final service = OrderService(apiService: context.read<ApiService>());
      final order = await service.getOrdenDetalle(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _selections =
            order.items.map((e) => _ItemSelection(item: e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  bool get _withinPlazo {
    final created = _order?.createdAt;
    if (created == null) return true;
    return DateTime.now().difference(created).inDays <=
        kPlazoDevolucionDias;
  }

  Future<void> _loadAvailability(int productoId) async {
    if (_availabilityByProduct.containsKey(productoId) ||
        _loadingAvailability.contains(productoId)) {
      return;
    }
    setState(() => _loadingAvailability.add(productoId));
    try {
      final catalog =
          CatalogService(apiService: context.read<ApiService>());
      final list = await catalog.getDisponibilidad(productoId);
      if (!mounted) return;
      setState(() {
        _availabilityByProduct[productoId] =
            list.where((e) => e.stock > 0).toList();
        _loadingAvailability.remove(productoId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAvailability.remove(productoId));
    }
  }

  double get _estimatedRefund {
    return _selections
        .where((s) => s.selected)
        .fold(0.0, (sum, s) => sum + s.item.precioUnitario * s.cantidad);
  }

  bool get _canSubmit {
    final selected = _selections.where((s) => s.selected).toList();
    if (selected.isEmpty) return false;
    if (_isCambio) {
      // Todo ítem seleccionado requiere nueva variante.
      for (final s in selected) {
        if (s.varianteCambioId == null) return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    final selected = _selections.where((s) => s.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una prenda')),
      );
      return;
    }
    if (_isCambio &&
        selected.any((s) => s.varianteCambioId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Elige la nueva variante para cada prenda a cambiar'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isCambio ? 'Confirmar cambio' : 'Confirmar devolución'),
        content: Text(
          '${selected.length} prenda(s) • Monto estimado: Bs. ${_estimatedRefund.toStringAsFixed(2)}\n\n'
          'Motivo: ${MotivosDevolucion.label(_motivo)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = context.read<ReturnProvider>();
    final created = await provider.createRequest(
      ordenId: widget.orderId,
      sucursalId: _order?.sucursalId,
      tipo: _isCambio ? 'CAMBIO' : 'DEVOLUCION',
      motivo: _motivo,
      motivoDetalle: _detalleController.text,
      items: selected
          .map((s) => ReturnItemCreate(
                detalleOrdenId: s.item.id,
                cantidad: s.cantidad,
                varianteCambioId:
                    _isCambio ? s.varianteCambioId : null,
              ))
          .toList(),
    );

    if (!mounted) return;
    if (created != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Solicitud ${created.numeroSolicitud} enviada'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/profile/returns');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              provider.errorMessage ?? 'No se pudo enviar la solicitud'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
          title: 'Solicitar devolución', showBackButton: true),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppColors.accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 56, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadOrder,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : !_withinPlazo
                  ? _buildOutOfPlazo()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _buildStepTitle('1', 'Selecciona las prendas'),
                          ..._selections
                              .map((s) => _buildItemSelector(s)),
                          const SizedBox(height: 16),
                          _buildStepTitle('2', 'Tipo y motivo'),
                          _buildTypeAndReason(),
                          const SizedBox(height: 16),
                          _buildStepTitle('3', 'Confirmación'),
                          _buildSummary(),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: Consumer<ReturnProvider>(
                              builder: (context, provider, _) {
                                return ElevatedButton.icon(
                                  onPressed: !_canSubmit ||
                                          provider.isSubmitting
                                      ? null
                                      : _submit,
                                  icon: provider.isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child:
                                              CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send_outlined,
                                          color: Colors.white),
                                  label: Text(
                                    _isCambio
                                        ? 'Enviar solicitud de cambio'
                                        : 'Enviar solicitud de devolución',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    minimumSize:
                                        const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildOutOfPlazo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.schedule_outlined,
                size: 64, color: AppColors.warning),
            const SizedBox(height: 16),
            Text('Plazo vencido',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Esta orden superó el plazo de $kPlazoDevolucionDias días para devoluciones y cambios.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepTitle(String number, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.primary,
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildItemSelector(_ItemSelection sel) {
    final item = sel.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sel.selected
              ? AppColors.accent
              : AppColors.border,
          width: sel.selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: sel.selected,
            onChanged: (v) {
              setState(() => sel.selected = v ?? false);
              if ((v ?? false) &&
                  _isCambio &&
                  item.productoId > 0) {
                _loadAvailability(item.productoId);
              }
            },
            title: Text(item.productoNombre,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              '${item.cantidad}x  Bs. ${item.precioUnitario.toStringAsFixed(2)}'
              '${item.talla != null ? ' • Talla ${item.talla}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            secondary: item.productoImagen != null &&
                    item.productoImagen!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(item.productoImagen!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.checkroom)),
                  )
                : const Icon(Icons.checkroom,
                    color: AppColors.accent),
          ),
          if (sel.selected) ...[
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Text('Cantidad:',
                      style: TextStyle(fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: sel.cantidad > 1
                        ? () => setState(
                            () => sel.cantidad--)
                        : null,
                  ),
                  Text('${sel.cantidad}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: sel.cantidad < item.cantidad
                        ? () => setState(
                            () => sel.cantidad++)
                        : null,
                  ),
                  Text('de ${item.cantidad}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
            // Selector de nueva variante (solo CAMBIO con stock).
            if (_isCambio) _buildVariantChangeSelector(sel),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantChangeSelector(_ItemSelection sel) {
    final productoId = sel.item.productoId;
    if (productoId <= 0) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          'No se pudo determinar el producto: considera pedir DEVOLUCIÓN.',
          style: TextStyle(fontSize: 12, color: AppColors.warning),
        ),
      );
    }
    if (_loadingAvailability.contains(productoId)) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final options = (_availabilityByProduct[productoId] ?? [])
        .where((e) => e.varianteId != sel.item.varianteProductoId)
        .toList();
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          'Sin stock para cambio en otras variantes: considera pedir DEVOLUCIÓN.',
          style: TextStyle(fontSize: 12, color: AppColors.warning),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DropdownButtonFormField<int>(
        value: sel.varianteCambioId,
        decoration: InputDecoration(
          labelText: 'Nueva variante',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
        ),
        items: options.map((o) {
          return DropdownMenuItem<int>(
            value: o.varianteId,
            child: Text(
              '${o.talla ?? ''} ${o.color ?? ''} (stock: ${o.stock})',
              style: const TextStyle(fontSize: 13),
            ),
          );
        }).toList(),
        onChanged: (v) =>
            setState(() => sel.varianteCambioId = v),
      ),
    );
  }

  Widget _buildTypeAndReason() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text('Devolución'),
                  icon: Icon(Icons.undo_outlined, size: 18)),
              ButtonSegment(
                  value: true,
                  label: Text('Cambio'),
                  icon: Icon(Icons.swap_horiz_outlined, size: 18)),
            ],
            selected: {_isCambio},
            onSelectionChanged: (s) {
              setState(() => _isCambio = s.first);
              if (_isCambio) {
                for (final sel in _selections.where((e) => e.selected)) {
                  if (sel.item.productoId > 0) {
                    _loadAvailability(sel.item.productoId);
                  }
                }
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _motivo,
            decoration: InputDecoration(
              labelText: 'Motivo',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            items: MotivosDevolucion.todos
                .map((m) => DropdownMenuItem(
                      value: m,
                      child:
                          Text(MotivosDevolucion.label(m)),
                    ))
                .toList(),
            onChanged: (v) =>
                setState(() => _motivo = v ?? _motivo),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detalleController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Detalle del motivo (opcional)',
              hintText: 'Ej. La talla M me quedó pequeña...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final count =
        _selections.where((s) => s.selected).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Prendas seleccionadas'),
              Text('$count',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Monto estimado'),
              Text(
                'Bs. ${_estimatedRefund.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                    fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
