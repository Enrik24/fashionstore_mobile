import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../core/models/order_model.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/order_service.dart';
import '../../../core/widgets/custom_app_bar.dart';

class OrdersHistoryPage extends StatefulWidget {
  const OrdersHistoryPage({super.key});

  @override
  State<OrdersHistoryPage> createState() => _OrdersHistoryPageState();
}

class _OrdersHistoryPageState extends State<OrdersHistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<OrderModel> _orders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final orderService = OrderService(apiService: context.read<ApiService>());
      final list = await orderService.getHistorialCompras();
      if (mounted) {
        setState(() {
          _orders = list;
          _isLoading = false;
        });
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

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        title: 'Historial de Compras',
        showBackButton: true,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.accent,
              indicatorWeight: 3,
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'Todas'),
                Tab(text: 'Pagadas'),
                Tab(text: 'Pendientes'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _error != null
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
                                onPressed: _loadOrders,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.accent,
                        onRefresh: _loadOrders,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOrderList(_orders),
                            _buildOrderList(_orders.where((o) => o.isPaid).toList()),
                            _buildOrderList(_orders.where((o) => o.isPending).toList()),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderList(List<OrderModel> list) {
    if (list.isEmpty) {
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
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No tienes compras registradas',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tus pedidos realizados en línea aparecerán aquí para que sigas su estado.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => context.go('/catalog'),
                child: const Text('Comenzar a Comprar'),
              ),
            ],
          ),
        ),
      );
    }

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final order = list[index];
        final statusColor = _getStatusColor(order.estado);

        return InkWell(
          onTap: () => context.push('/profile/orders/${order.id}'),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
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
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        order.estado.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textLight),
                    const SizedBox(width: 6),
                    Text(
                      order.createdAt != null ? dateFormat.format(order.createdAt!) : 'Fecha no disponible',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textLight),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.items.length} ${order.items.length == 1 ? 'prenda' : 'prendas'}',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (order.metodoPago != null)
                          Text(
                            'Pago: ${order.metodoPago}',
                            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight),
                          ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Total',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight),
                        ),
                        Text(
                          'Bs. ${order.total.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
