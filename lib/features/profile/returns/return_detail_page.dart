import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/return_request_model.dart';
import '../../../core/providers/return_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/return_service.dart';
import '../../../core/widgets/custom_app_bar.dart';

/// Detalle de una solicitud con línea de tiempo del estado (CU28).
class ReturnDetailPage extends StatefulWidget {
  final int solicitudId;

  const ReturnDetailPage({super.key, required this.solicitudId});

  @override
  State<ReturnDetailPage> createState() => _ReturnDetailPageState();
}

class _ReturnDetailPageState extends State<ReturnDetailPage> {
  ReturnRequestModel? _request;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Reutilizar caché del provider si ya la tiene.
      final cached = context
          .read<ReturnProvider>()
          .requests
          .where((r) => r.id == widget.solicitudId);
      if (cached.isNotEmpty) {
        _request = cached.first;
      }
      final service =
          ReturnService(apiService: context.read<ApiService>());
      final fresh = await service.getSolicitud(widget.solicitudId);
      if (!mounted) return;
      setState(() {
        _request = fresh;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Si había caché, conservarla y mostrar el error como aviso.
        if (_request == null) _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String estado) {
    switch (estado.toUpperCase()) {
      case EstadosDevolucion.pendiente:
        return Colors.amber.shade700;
      case EstadosDevolucion.enRevision:
        return Colors.blue;
      case EstadosDevolucion.aprobada:
        return Colors.lightBlue.shade700;
      case EstadosDevolucion.completada:
        return AppColors.success;
      case EstadosDevolucion.rechazada:
        return AppColors.error;
      case EstadosDevolucion.pendienteReembolso:
        return Colors.deepOrange;
      default:
        return AppColors.textSecondary;
    }
  }

  /// Pasos de la línea de tiempo según el estado actual.
  List<_TimelineStep> _steps(ReturnRequestModel r) {
    final estado = r.estado.toUpperCase();

    _TimelineStep done(String s) => _TimelineStep(label: s, done: true);
    _TimelineStep todo(String s) => _TimelineStep(label: s, done: false);
    _TimelineStep current(String s) =>
        _TimelineStep(label: s, done: false, isCurrent: true);

    if (estado == EstadosDevolucion.rechazada) {
      return [
        done('Pendiente'),
        done('En revisión'),
        _TimelineStep(
            label: 'Rechazada', done: true, isRejected: true),
      ];
    }
    final steps = <_TimelineStep>[
      done('Pendiente'),
      estado == EstadosDevolucion.pendiente
          ? current('En revisión')
          : done('En revisión'),
    ];
    if (estado == EstadosDevolucion.aprobada ||
        estado == EstadosDevolucion.pendienteReembolso ||
        estado == EstadosDevolucion.completada) {
      steps.add(done('Aprobada'));
    } else {
      steps.add(current('Aprobada'));
    }
    if (estado == EstadosDevolucion.pendienteReembolso) {
      steps.add(current('Pendiente de reembolso'));
    } else if (estado == EstadosDevolucion.completada) {
      steps.add(done('Completada'));
    } else {
      steps.add(todo('Completada'));
    }
    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: _request?.numeroSolicitud ?? 'Detalle de solicitud',
        showBackButton: true,
      ),
      body: _isLoading && _request == null
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppColors.accent))
          : _error != null && _request == null
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
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        _buildHeader(_request!, dateFormat),
                        const SizedBox(height: 16),
                        _buildTimeline(_request!),
                        const SizedBox(height: 16),
                        _buildItems(_request!),
                        if (_request!.observacionesStaff !=
                                null &&
                            _request!.observacionesStaff!
                                .isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildStaffNotes(_request!),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeader(
      ReturnRequestModel r, DateFormat dateFormat) {
    final color = _statusColor(r.estado);
    return Container(
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Text(r.numeroSolicitud,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: color.withOpacity(0.4)),
                ),
                child: Text(
                  EstadosDevolucion.label(r.estado),
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${r.isCambio ? 'Cambio' : 'Devolución'} • ${MotivosDevolucion.label(r.motivo)}',
            style: const TextStyle(
                color: AppColors.textSecondary),
          ),
          if (r.motivoDetalle != null &&
              r.motivoDetalle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('“${r.motivoDetalle}”',
                  style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 13)),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                r.fechaSolicitud != null
                    ? 'Solicitado: ${dateFormat.format(r.fechaSolicitud!)}'
                    : '',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted),
              ),
              if (r.montoReembolso != null)
                Text(
                  'Bs. ${r.montoReembolso!.toStringAsFixed(2)}',
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

  Widget _buildTimeline(ReturnRequestModel r) {
    final steps = _steps(r);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Seguimiento',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            final isLast = i == steps.length - 1;
            final color = s.isRejected
                ? AppColors.error
                : (s.done || s.isCurrent
                    ? AppColors.success
                    : AppColors.textMuted);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.done || s.isCurrent
                            ? color
                            : Colors.transparent,
                        border: Border.all(color: color),
                      ),
                      child: (s.done || s.isCurrent)
                          ? Icon(
                              s.isRejected
                                  ? Icons.close
                                  : Icons.check,
                              size: 14,
                              color: Colors.white)
                          : null,
                    ),
                    if (!isLast)
                      Container(
                          width: 2, height: 18, color: color),
                  ],
                ),
                const SizedBox(width: 10),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 2),
                  child: Text(s.label,
                      style: TextStyle(
                          fontWeight: s.isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: s.isCurrent
                              ? AppColors.textPrimary
                              : AppColors.textSecondary)),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildItems(ReturnRequestModel r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prendas (${r.items.length})',
              style:
                  const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...r.items.map((it) => Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.checkroom,
                        color: AppColors.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('Ítem #${it.detalleOrdenId} • '
                              'Cant. ${it.cantidad}'),
                          if (it.varianteCambioId != null)
                            Text(
                              'Cambio a variante #${it.varianteCambioId}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.accent),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      'Bs. ${(it.precioUnitario * it.cantidad).toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStaffNotes(ReturnRequestModel r) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: AppColors.warning),
              SizedBox(width: 6),
              Text('Observaciones de la tienda',
                  style: TextStyle(
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.observacionesStaff!),
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final bool done;
  final bool isCurrent;
  final bool isRejected;

  _TimelineStep({
    required this.label,
    this.done = false,
    this.isCurrent = false,
    this.isRejected = false,
  });
}
