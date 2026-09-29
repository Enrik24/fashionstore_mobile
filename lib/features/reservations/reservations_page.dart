import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../core/models/reservation_model.dart';
import '../../core/providers/reservation_provider.dart';
import '../../core/providers/auth_provider.dart';
import 'widgets/reservation_card.dart';

class ReservationsPage extends StatefulWidget {
  const ReservationsPage({super.key});

  @override
  State<ReservationsPage> createState() => _ReservationsPageState();
}

class _ReservationsPageState extends State<ReservationsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.isAuthenticated) {
        context.read<ReservationProvider>().loadReservations();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _cancelReservation(ReservationModel res) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Reserva'),
        content: Text('¿Estás seguro de que deseas cancelar la reserva ${res.numeroReserva}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<ReservationProvider>().cancelReservation(res.id);
            },
            child: const Text('Sí, Cancelar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mis Reservas')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today_outlined, size: 72, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(
                  'Inicia sesión para ver tus reservas',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Reserva prendas exclusivas y pruébatelas en tu sucursal más cercana sin compromiso de compra previa.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('Iniciar Sesión'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mis Reservas'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.accent,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Todas'),
            Tab(text: 'Pendientes'),
            Tab(text: 'Completadas'),
          ],
        ),
      ),
      body: Consumer<ReservationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.reservations.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => provider.loadReservations(),
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildList(provider.reservations, provider),
                _buildList(
                  provider.reservations.where((r) => r.isPending || r.isConfirmed).toList(),
                  provider,
                ),
                _buildList(
                  provider.reservations.where((r) => r.isCompleted || r.isCancelled || r.isExpired).toList(),
                  provider,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(List<ReservationModel> list, ReservationProvider provider) {
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
                  Icons.event_available_outlined,
                  size: 64,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No tienes reservas en esta sección',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Puedes apartar prendas desde el catálogo para probártelas en tienda física.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go('/catalog'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Explorar Catálogo', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final res = list[index];
        return ReservationCard(
          reservation: res,
          onTap: () => context.push('/reservations/${res.id}'),
          onCancel: res.isPending ? () => _cancelReservation(res) : null,
        );
      },
    );
  }
}
