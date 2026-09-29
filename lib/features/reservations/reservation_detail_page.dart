import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../core/models/reservation_model.dart';
import '../../core/providers/reservation_provider.dart';
import '../../core/widgets/custom_app_bar.dart';

class ReservationDetailPage extends StatefulWidget {
  final int reservationId;

  const ReservationDetailPage({
    super.key,
    required this.reservationId,
  });

  @override
  State<ReservationDetailPage> createState() => _ReservationDetailPageState();
}

class _ReservationDetailPageState extends State<ReservationDetailPage> {
  ReservationModel? _reservation;
  BranchModel? _branch;
  bool _isLoading = true;
  String? _error;
  bool _isCancelling = false;

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

    final provider = context.read<ReservationProvider>();

    // GET /reservas/{id} only returns sucursal_id (not the nested sucursal),
    // so load the branch catalog to resolve the sucursal name/address locally.
    if (provider.branches.isEmpty) {
      await provider.loadBranches();
    }

    // First try to find in existing list
    final existing = provider.reservations.where((r) => r.id == widget.reservationId);
    if (existing.isNotEmpty) {
      _reservation = existing.first;
    }

    // Then fetch fresh detail
    final detail = await provider.getReservationDetail(widget.reservationId);
    if (mounted) {
      setState(() {
        if (detail != null) {
          _reservation = detail;
        } else if (_reservation == null) {
          _error = 'No se pudo cargar el detalle de la reserva';
        }
        _resolveBranch(provider);
        _isLoading = false;
      });
    }
  }

  void _resolveBranch(ReservationProvider provider) {
    if (_reservation == null) return;
    final matches = provider.branches.where((b) => b.id == _reservation!.sucursalId);
    if (matches.isNotEmpty) {
      _branch = matches.first;
    }
  }

  Future<void> _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '¿Cancelar Reserva?',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '¿Estás seguro de que deseas cancelar esta reserva? Las prendas volverán a estar disponibles para otros clientes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, mantener'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isCancelling = true);
    final success = await context.read<ReservationProvider>().cancelReservation(widget.reservationId);
    if (mounted) {
      setState(() => _isCancelling = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reserva cancelada exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadDetail();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cancelar la reserva'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String estado) {
    switch (estado.toUpperCase()) {
      case 'CONFIRMADA':
        return AppColors.success;
      case 'PENDIENTE':
        return AppColors.warning;
      case 'CANCELADA':
        return AppColors.error;
      case 'EXPIRADA':
        return AppColors.textLight;
      case 'COMPLETADA':
        return AppColors.primary;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: _reservation?.numeroReserva ?? 'Detalle de Reserva',
        showBackButton: true,
      ),
      body: _isLoading && _reservation == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null && _reservation == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                        const SizedBox(height: 16),
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
                  onRefresh: _loadDetail,
                  color: AppColors.accent,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatusHeader(_reservation!),
                        const SizedBox(height: 20),
                        _buildTimeline(_reservation!),
                        const SizedBox(height: 24),
                        _buildBranchInfo(_reservation!, dateFormat),
                        const SizedBox(height: 24),
                        _buildItemsSection(_reservation!),
                        if (_reservation!.notas != null && _reservation!.notas!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildNotesCard(_reservation!.notas!),
                        ],
                        const SizedBox(height: 32),
                        if (_reservation!.isPending) _buildCancelButton(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatusHeader(ReservationModel res) {
    final statusColor = _getStatusColor(res.estado);
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Código de Reserva',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  res.numeroReserva,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  res.estado.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(ReservationModel res) {
    final isCancelled = res.isCancelled;
    final isExpired = res.isExpired;

    final steps = isCancelled || isExpired
        ? [
            {'title': 'Creada', 'done': true},
            {'title': isCancelled ? 'Cancelada' : 'Expirada', 'done': true, 'isBad': true},
          ]
        : [
            {'title': 'Pendiente', 'done': true},
            {'title': 'Confirmada', 'done': res.isConfirmed || res.isCompleted},
            {'title': 'Completada', 'done': res.isCompleted},
          ];

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
          Text(
            'Estado de la Reserva',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(steps.length * 2 - 1, (index) {
              if (index.isOdd) {
                final prevDone = steps[index ~/ 2]['done'] as bool;
                final nextDone = steps[(index ~/ 2) + 1]['done'] as bool;
                return Expanded(
                  child: Container(
                    height: 3,
                    color: prevDone && nextDone ? AppColors.accent : Colors.grey.shade200,
                  ),
                );
              }
              final stepIndex = index ~/ 2;
              final step = steps[stepIndex];
              final isDone = step['done'] as bool;
              final isBad = step['isBad'] == true;
              final color = isBad
                  ? AppColors.error
                  : isDone
                      ? AppColors.accent
                      : Colors.grey.shade300;

              return Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isDone ? color : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Icon(
                      isBad
                          ? Icons.close
                          : isDone
                              ? Icons.check
                              : Icons.circle,
                      size: 14,
                      color: isDone ? Colors.white : Colors.transparent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step['title'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isDone ? FontWeight.w600 : FontWeight.normal,
                      color: isDone ? AppColors.primary : AppColors.textLight,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchInfo(ReservationModel res, DateFormat dateFormat) {
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
          Text(
            'Información de Sucursal & Cita',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.store_mall_directory_outlined, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _branch?.nombre ?? res.sucursalNombre ?? 'Sucursal FashionStore',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (_branch?.direccion != null || res.sucursalDireccion != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _branch?.direccion ?? res.sucursalDireccion ?? '',
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textLight),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_today_outlined, color: AppColors.accent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fecha',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight),
                        ),
                        Text(
                          dateFormat.format(res.fechaReserva),
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.access_time_outlined, color: AppColors.accent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Horario',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight),
                        ),
                        Text(
                          res.horarioAproximado ?? 'A coordinar',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection(ReservationModel res) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Prendas Reservadas (${res.items.length})',
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (res.items.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                'No hay prendas detalladas para esta reserva',
                style: GoogleFonts.inter(color: AppColors.textLight),
              ),
            ),
          )
        else
          ...res.items.map((item) => _buildItemCard(item)),
      ],
    );
  }

  Widget _buildItemCard(ReservationItemModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              child: item.productoImagen != null && item.productoImagen!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.productoImagen!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.checkroom, color: AppColors.accent),
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.checkroom, color: AppColors.accent),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productoNombre ?? 'Prenda de Moda',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    if (item.talla != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Talla: ${item.talla}',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textDark),
                        ),
                      ),
                    if (item.color != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Color: ${item.color}',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textDark),
                        ),
                      ),
                    Text(
                      'Cant: ${item.cantidad}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesCard(String notas) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes_outlined, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notas adicionales',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notas,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error),
          foregroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _isCancelling ? null : _handleCancel,
        icon: _isCancelling
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
              )
            : const Icon(Icons.cancel_outlined),
        label: Text(
          _isCancelling ? 'Cancelando...' : 'Cancelar esta Reserva',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}
