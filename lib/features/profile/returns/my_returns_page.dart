import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/return_request_model.dart';
import '../../../core/providers/return_provider.dart';
import '../../../core/widgets/custom_app_bar.dart';

/// Lista "Mis Devoluciones" del cliente (CU28).
class MyReturnsPage extends StatefulWidget {
  const MyReturnsPage({super.key});

  @override
  State<MyReturnsPage> createState() => _MyReturnsPageState();
}

class _MyReturnsPageState extends State<MyReturnsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReturnProvider>().loadMyRequests(refresh: true);
    });
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

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
          title: 'Mis Devoluciones', showBackButton: true),
      body: Consumer<ReturnProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.requests.isEmpty) {
            return const Center(
              child:
                  CircularProgressIndicator(color: AppColors.accent),
            );
          }

          if (provider.errorMessage != null &&
              provider.requests.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 56, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(provider.errorMessage!,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          provider.loadMyRequests(refresh: true),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.requests.isEmpty) {
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
                          Icons.assignment_return_outlined,
                          size: 56,
                          color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    Text('Sin solicitudes',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Aquí verás el seguimiento de tus devoluciones y cambios.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () =>
                          context.push('/profile/orders'),
                      icon: const Icon(Icons.receipt_long_outlined,
                          color: Colors.white),
                      label: const Text('Ver mis compras',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () =>
                provider.loadMyRequests(refresh: true),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: provider.requests.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = provider.requests[i];
                final color = _statusColor(r.estado);
                return InkWell(
                  onTap: () =>
                      context.push('/profile/returns/${r.id}'),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(r.numeroSolicitud,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius:
                                    BorderRadius.circular(10),
                                border: Border.all(
                                    color: color.withOpacity(0.4)),
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
                        const SizedBox(height: 6),
                        Text(
                          '${r.isCambio ? 'Cambio' : 'Devolución'} • ${MotivosDevolucion.label(r.motivo)}',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              r.fechaSolicitud != null
                                  ? dateFormat.format(
                                      r.fechaSolicitud!)
                                  : '',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted),
                            ),
                            const Spacer(),
                            if (r.montoReembolso != null)
                              Text(
                                'Bs. ${r.montoReembolso!.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
