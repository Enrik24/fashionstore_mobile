import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/theme.dart';
import '../../../core/models/product_model.dart';

/// Disponibilidad por sucursal (CU10).
///
/// Permite seleccionar una sucursal con stock y reservar directamente en
/// ella, muestra "Sin stock" con sugerencias cuando la combinación no tiene
/// existencias, recarga bajo demanda y ofrece "Cómo llegar" con el mapa
/// externo cuando hay coordenadas.
class AvailabilitySection extends StatefulWidget {
  final List<DisponibilidadItem> availabilityList;
  final bool isLoading;
  final bool variantSelected;
  final VoidCallback? onRefresh;
  final void Function(DisponibilidadItem sucursal)? onReservarEnSucursal;

  const AvailabilitySection({
    super.key,
    required this.availabilityList,
    this.isLoading = false,
    this.variantSelected = true,
    this.onRefresh,
    this.onReservarEnSucursal,
  });

  @override
  State<AvailabilitySection> createState() => _AvailabilitySectionState();
}

class _AvailabilitySectionState extends State<AvailabilitySection> {
  int? _selectedSucursalId;

  Future<void> _comoLlegar(
      BuildContext context, DisponibilidadItem item) async {
    if (item.latitud == null || item.longitud == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Esta sucursal no tiene ubicación registrada en el mapa'),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${item.latitud},${item.longitud}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No se pudo abrir el mapa en este dispositivo'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No se pudo abrir el mapa en este dispositivo'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child:
              CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
        ),
      );
    }

    if (widget.availabilityList.isEmpty) {
      // Sin datos: si ya se eligió variante, es falta de stock.
      if (widget.variantSelected) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.warning.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Sin stock disponible para esta combinación. Prueba con otra talla o color.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              if (widget.onRefresh != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Reintentar',
                  onPressed: widget.onRefresh,
                ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Selecciona una talla y un color para ver la disponibilidad por sucursal.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    final conStock =
        widget.availabilityList.where((e) => e.stock > 0).toList();
    final sinStock =
        widget.availabilityList.where((e) => e.stock <= 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Disponibilidad en Sucursales',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'En tiempo real',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.onRefresh != null)
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 18, color: AppColors.textSecondary),
                    tooltip: 'Actualizar disponibilidad',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onRefresh,
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (conStock.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.error.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.remove_shopping_cart_outlined,
                    color: AppColors.error, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sin stock en ninguna sucursal para esta combinación. Prueba con otra talla o color.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ...conStock.map((item) => _buildBranchRow(context, item, true)),
        ...sinStock.map((item) => _buildBranchRow(context, item, false)),
      ],
    );
  }

  Widget _buildBranchRow(
      BuildContext context, DisponibilidadItem item, bool hasStock) {
    final selected = _selectedSucursalId == item.sucursalId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? AppColors.accent
              : (hasStock
                  ? AppColors.border
                  : AppColors.error.withOpacity(0.3)),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: hasStock
                ? () => setState(() {
                      _selectedSucursalId =
                          selected ? null : item.sucursalId;
                    })
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasStock)
                  Radio<int>(
                    value: item.sucursalId,
                    groupValue: _selectedSucursalId,
                    activeColor: AppColors.accent,
                    onChanged: (v) =>
                        setState(() => _selectedSucursalId = v),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.remove_shopping_cart_outlined,
                      color: AppColors.error,
                      size: 20,
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.sucursalNombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (item.direccion != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.direccion!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 12),
                        ),
                      ],
                      if (item.telefono != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Tel: ${item.telefono}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      hasStock
                          ? '${item.stock} disponibles'
                          : 'Agotado',
                      style: TextStyle(
                        color: hasStock
                            ? AppColors.success
                            : AppColors.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (item.cantidadReservada > 0)
                      Text(
                        '${item.cantidadReservada} reserv.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 10, color: AppColors.warning),
                      ),
                    if (item.cantidadVendida > 0)
                      Text(
                        '${item.cantidadVendida} vend.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 10, color: AppColors.textSecondary),
                      ),
                    if (item.talla != null || item.color != null)
                      Text(
                        '${item.talla ?? ''} ${item.color != null ? '• ${item.color}' : ''}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 10),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (hasStock) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (item.latitud != null && item.longitud != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _comoLlegar(context, item),
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('Cómo llegar',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                if (item.latitud != null && item.longitud != null)
                  const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onReservarEnSucursal == null
                        ? null
                        : () =>
                            widget.onReservarEnSucursal!(item),
                    icon: const Icon(Icons.bookmark_add_outlined,
                        size: 16, color: Colors.white),
                    label: const Text('Reservar aquí',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
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
