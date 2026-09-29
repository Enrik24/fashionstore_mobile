import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/promotions_provider.dart';
import '../../core/providers/recommendations_provider.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../catalog/widgets/product_card.dart';
import '../catalog/widgets/skeleton_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool? _wasAuthenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecommendations();
      // Promociones activas para los badges de descuento (una sola vez).
      context.read<PromotionsProvider>().load();
      // Recargar al cambiar la sesión (personalizadas vs novedades).
      context.read<AuthProvider>().addListener(_onAuthChanged);
    });
  }

  @override
  void dispose() {
    try {
      context.read<AuthProvider>().removeListener(_onAuthChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final isAuth = context.read<AuthProvider>().isAuthenticated;
    if (_wasAuthenticated != null && _wasAuthenticated != isAuth) {
      _wasAuthenticated = isAuth;
      context
          .read<RecommendationsProvider>()
          .load(isAuthenticated: isAuth, refresh: true);
    }
  }

  void _loadRecommendations({bool refresh = false}) {
    final auth = context.read<AuthProvider>();
    _wasAuthenticated = auth.isAuthenticated;
    context
        .read<RecommendationsProvider>()
        .load(isAuthenticated: auth.isAuthenticated, refresh: refresh);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: const CustomAppBar(),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () async => _loadRecommendations(refresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero Banner
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                      ),
                      child: const Text(
                        'Colección Nueva Temporada',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user != null
                          ? '¡Hola, ${user.nombre}!\nDescubre tu estilo'
                          : 'Encuentra las mejores prendas y reserva en tienda',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Explora nuestro catálogo exclusivo, verifica disponibilidad por sucursal y reserva para probarte en tienda.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.go('/catalog'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(140, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Ver Catálogo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Quick Actions Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Servicios FashionStore',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.4,
                      children: [
                        _buildActionCard(
                          context,
                          title: 'Catálogo',
                          subtitle: 'Prendas y stock',
                          icon: Icons.grid_view_rounded,
                          color: AppColors.primary,
                          onTap: () => context.go('/catalog'),
                        ),
                        _buildActionCard(
                          context,
                          title: 'Reservas',
                          subtitle: 'Probar en tienda',
                          icon: Icons.bookmark_added_rounded,
                          color: AppColors.secondary,
                          onTap: () => context.go('/reservations'),
                        ),
                        _buildActionCard(
                          context,
                          title: 'Carrito',
                          subtitle: 'Compras directas',
                          icon: Icons.shopping_cart_rounded,
                          color: AppColors.accent,
                          onTap: () => context.go('/cart'),
                        ),
                        _buildActionCard(
                          context,
                          title: 'Mi Cuenta',
                          subtitle: user != null ? user.nombre : 'Iniciar sesión',
                          icon: Icons.person_rounded,
                          color: AppColors.info,
                          onTap: () => context.go('/profile'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Recommendations (espejo de la landing web)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recomendaciones',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go('/catalog'),
                      child: const Text('Ver todas',
                          style: TextStyle(color: AppColors.accent)),
                    ),
                  ],
                ),
              ),
              Consumer<RecommendationsProvider>(
                builder: (context, recs, _) {
                  if (recs.badge != null) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: recs.isPersonalized
                                ? AppColors.accent.withOpacity(0.12)
                                : AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: recs.isPersonalized
                                  ? AppColors.accent.withOpacity(0.4)
                                  : AppColors.primary.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                recs.isPersonalized
                                    ? Icons.auto_awesome
                                    : Icons.star_outline,
                                size: 14,
                                color: recs.isPersonalized
                                    ? AppColors.accent
                                    : AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  recs.badge!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: recs.isPersonalized
                                        ? AppColors.accent
                                        : AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              Consumer<RecommendationsProvider>(
                builder: (context, recs, _) {
                  if (recs.message != null &&
                      recs.message!.isNotEmpty) {
                    return Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        recs.message!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 8),

              Consumer<RecommendationsProvider>(
                builder: (context, recs, _) {
                  if (recs.isLoading && recs.products.isEmpty) {
                    return SizedBox(
                      height: 240,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: 3,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 14),
                        itemBuilder: (_, __) => const SizedBox(
                          width: 160,
                          child: SkeletonProductCard(),
                        ),
                      ),
                    );
                  }

                  if (recs.products.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                                Icons.recommend_outlined,
                                size: 40,
                                color: AppColors.textMuted),
                            const SizedBox(height: 8),
                            Text(
                              recs.errorMessage ??
                                  'No hay recomendaciones por ahora',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _loadRecommendations(
                                      refresh: true),
                              icon: const Icon(Icons.refresh,
                                  size: 16),
                              label:
                                  const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SizedBox(
                    height: 250,
                    child: ListView.separated(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: recs.products.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        return SizedBox(
                          width: 165,
                          child: ProductCard(
                              product: recs.products[index]),
                        );
                      },
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Highlights
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded, color: AppColors.accent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Sucursales y Disponibilidad',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Consulta en tiempo real las existencias por talla y color en cada sucursal antes de visitarnos.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
