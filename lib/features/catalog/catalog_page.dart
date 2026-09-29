import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../core/providers/catalog_provider.dart';
import '../../core/providers/promotions_provider.dart';
import 'widgets/product_card.dart';
import 'widgets/skeleton_card.dart';
import 'widgets/filter_bottom_sheet.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CatalogProvider>();
      if (provider.products.isEmpty) {
        provider.loadCatalog(refresh: true);
      }
      // Promociones activas para los badges de descuento (una sola vez).
      context.read<PromotionsProvider>().load();
    });

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<CatalogProvider>().loadCatalog();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FilterBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Catálogo'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.tune_outlined),
                Consumer<CatalogProvider>(
                  builder: (context, prov, _) {
                    if (prov.hasActiveFilters) {
                      return Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
            onPressed: _showFilterModal,
          ),
        ],
      ),
      body: Consumer<CatalogProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => provider.loadCatalog(refresh: true),
            child: Column(
              children: [
                // Search bar fake button to quickly jump into search
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: InkWell(
                    onTap: () => context.push('/search'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'Buscar prendas, marcas o estilos...',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Gender tabs (como la landing web: Todos / Hombre / Mujer / Unisex)
                _GenderTabs(
                  selected: provider.selectedGenero,
                  onSelected: (g) => provider.setGenero(g),
                ),
                // Contador de resultados (progreso del scroll infinito)
                if (provider.totalItems > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        provider.hasMore
                            ? 'Mostrando ${provider.products.length} de ${provider.totalItems} productos'
                            : '${provider.totalItems} productos',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),

                // Active Filters Chips Bar
                if (provider.hasActiveFilters)
                  Container(
                    height: 40,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (provider.selectedGenero != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(
                                  'Género: ${_genderLabel(provider.selectedGenero)}'),
                              deleteIcon:
                                  const Icon(Icons.close, size: 16),
                              onDeleted: () =>
                                  provider.setGenero(null),
                              backgroundColor:
                                  AppColors.surfaceVariant,
                            ),
                          ),
                        if (provider.selectedCategoryName != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text('Cat: ${provider.selectedCategoryName}'),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => provider.setCategory(null),
                              backgroundColor: AppColors.surfaceVariant,
                            ),
                          ),
                        if (provider.selectedTemporadaName != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text('Temp: ${provider.selectedTemporadaName}'),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => provider.setTemporada(null),
                              backgroundColor: AppColors.surfaceVariant,
                            ),
                          ),
                        if (provider.selectedTallaValor != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text('Talla: ${provider.selectedTallaValor}'),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => provider.setTalla(null),
                              backgroundColor: AppColors.surfaceVariant,
                            ),
                          ),
                        if (provider.selectedColorNombre != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text('Color: ${provider.selectedColorNombre}'),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => provider.setColor(null),
                              backgroundColor: AppColors.surfaceVariant,
                            ),
                          ),
                        if (provider.minPrice != null || provider.maxPrice != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(
                                  'Bs. ${provider.minPrice?.round() ?? 0} - ${provider.maxPrice?.round() ?? 1500}'),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => provider.setPriceRange(null, null),
                              backgroundColor: AppColors.surfaceVariant,
                            ),
                          ),
                        if (provider.ordering != null && provider.ordering != 'recientes')
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text('Orden: ${provider.ordering}'),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => provider.setOrdering('recientes'),
                              backgroundColor: AppColors.surfaceVariant,
                            ),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.clear_all, size: 16, color: AppColors.accent),
                          label: const Text('Limpiar todo', style: TextStyle(color: AppColors.accent)),
                          onPressed: () => provider.clearFilters(),
                          backgroundColor: Colors.transparent,
                          side: const BorderSide(color: AppColors.accent),
                        ),
                      ],
                    ),
                  ),

                // Main Content
                Expanded(
                  child: _buildContent(context, provider),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, CatalogProvider provider) {    if (provider.isLoading && provider.products.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.65,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => const SkeletonProductCard(),
      );
    }

    if (provider.errorMessage != null && provider.products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(
                'No se pudo cargar el catálogo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                provider.errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => provider.loadCatalog(refresh: true),
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Reintentar', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(160, 44),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(
                'No hay productos disponibles',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba ajustando los filtros de búsqueda.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => provider.clearFilters(),
                child: const Text('Restablecer Filtros'),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: provider.products.length + (provider.isLoadingMore ? 2 : 0),
      itemBuilder: (context, index) {
        if (index >= provider.products.length) {
          return const SkeletonProductCard();
        }
        return ProductCard(product: provider.products[index]);
      },
    );
  }
}

/// Etiqueta legible del género seleccionado.
String _genderLabel(String? genero) {
  switch (genero?.toUpperCase()) {
    case 'HOMBRE':
      return 'Hombre';
    case 'MUJER':
      return 'Mujer';
    case 'UNISEX':
      return 'Unisex';
    default:
      return genero ?? 'Todos';
  }
}

/// Tabs de género (Todos / Hombre / Mujer / Unisex), espejo de la web.
class _GenderTabs extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _GenderTabs({required this.selected, required this.onSelected});

  static const _options = <String?>[null, 'HOMBRE', 'MUJER', 'UNISEX'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final value = _options[i];
          final isSelected = (selected == null && value == null) ||
              (selected != null &&
                  value != null &&
                  selected!.toUpperCase() == value);
          return ChoiceChip(
            label: Text(value == null ? 'Todos' : _genderLabel(value)),
            selected: isSelected,
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.border),
            ),
            onSelected: (_) => onSelected(value),
          );
        },
      ),
    );
  }
}
