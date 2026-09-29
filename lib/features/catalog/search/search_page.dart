import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../core/providers/catalog_provider.dart';
import '../widgets/product_card.dart';
import '../widgets/skeleton_card.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<CatalogProvider>().searchProducts(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Buscar ropa, calzados, vestidos...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintStyle: const TextStyle(color: AppColors.textMuted),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                    onPressed: () {
                      _searchController.clear();
                      context.read<CatalogProvider>().clearSearch();
                      setState(() {});
                    },
                  )
                : null,
          ),
          style: Theme.of(context).textTheme.bodyLarge,
          onChanged: (val) {
            setState(() {});
            _onSearchChanged(val);
          },
        ),
      ),
      body: Consumer<CatalogProvider>(
        builder: (context, provider, child) {
          if (provider.isSearching) {
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.65,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: 4,
              itemBuilder: (context, index) => const SkeletonProductCard(),
            );
          }

          if (_searchController.text.trim().isEmpty) {
            return _buildPopularKeywords(context);
          }

          if (provider.searchResults.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off_outlined, size: 64, color: AppColors.textMuted),
                    const SizedBox(height: 16),
                    Text(
                      'No encontramos resultados',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Intenta buscar con otras palabras clave.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.65,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: provider.searchResults.length,
            itemBuilder: (context, index) {
              return ProductCard(product: provider.searchResults[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildPopularKeywords(BuildContext context) {
    final suggestions = ['Vestidos', 'Camisas', 'Pantalones', 'Jeans', 'Chaquetas', 'Blusas', 'Zapatos'];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Búsquedas Populares',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((keyword) {
              return ActionChip(
                label: Text(keyword),
                avatar: const Icon(Icons.trending_up, size: 16, color: AppColors.accent),
                backgroundColor: AppColors.surfaceVariant,
                onPressed: () {
                  _searchController.text = keyword;
                  setState(() {});
                  _onSearchChanged(keyword);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
