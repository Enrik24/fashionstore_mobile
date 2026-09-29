import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../core/models/reservation_model.dart';

class ReservationCard extends StatelessWidget {
  final ReservationModel reservation;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  const ReservationCard({
    super.key,
    required this.reservation,
    this.onCancel,
    this.onTap,
  });

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'CONFIRMADA':
        return AppColors.success;
      case 'PENDIENTE':
        return AppColors.warning;
      case 'COMPLETADA':
        return AppColors.info;
      case 'CANCELADA':
      case 'EXPIRADA':
      default:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final formattedDate = dateFormat.format(reservation.fechaReserva);
    final statusColor = _getStatusColor(reservation.estado);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Code & Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                reservation.numeroReserva,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.primary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  reservation.estado.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // Branch & Date Info
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reservation.sucursalNombre ?? 'Sucursal FashionStore',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
          if (reservation.sucursalDireccion != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                reservation.sucursalDireccion!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Fecha: $formattedDate',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (reservation.horarioAproximado != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.access_time, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  reservation.horarioAproximado!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Reserved Items list
          if (reservation.items.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: reservation.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '• ${item.productoNombre ?? 'Prenda'} (${item.talla ?? ''} ${item.color != null ? '- ${item.color}' : ''})',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${item.cantidad} un.',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Cancel button if pending
          if (reservation.isPending && onCancel != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
                label: const Text('Cancelar Reserva', style: TextStyle(color: AppColors.error, fontSize: 13)),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
