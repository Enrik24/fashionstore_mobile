import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../core/providers/catalog_provider.dart';
import '../../../core/models/product_model.dart';

class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({super.key});

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  int? _tempCategoryId;
  String? _tempCategoryName;
  int? _tempTemporadaId;
  String? _tempTemporadaName;
  int? _tempTallaId;
  String? _tempTallaValor;
  int? _tempColorId;
  String? _tempColorNombre;
  RangeValues _priceRange = const RangeValues(0, 1500);
  String? _tempOrdering;
  String? _tempGenero; // null = Todos, 'HOMBRE', 'MUJER', 'UNISEX'

  static const List<Map<String, String?>> _genderOptions = [
    {'id': null, 'label': 'Todos'},
    {'id': 'HOMBRE', 'label': 'Hombre'},
    {'id': 'MUJER', 'label': 'Mujer'},
    {'id': 'UNISEX', 'label': 'Unisex'},
  ];

  final List<Map<String, String>> _sortOptions = [
    {'id': 'recientes', 'label': 'Más recientes'},
    {'id': 'precio_asc', 'label': 'Precio: Menor a Mayor'},
    {'id': 'precio_desc', 'label': 'Precio: Mayor a Menor'},
    {'id': 'nombre', 'label': 'Nombre A-Z'},
  ];

  @override
  void initState() {
    super.initState();
    final provider = context.read<CatalogProvider>();
    _tempCategoryId = provider.selectedCategoryId;
    _tempCategoryName = provider.selectedCategoryName;
    _tempTemporadaId = provider.selectedTemporadaId;
    _tempTemporadaName = provider.selectedTemporadaName;
    _tempTallaId = provider.selectedTallaId;
    _tempTallaValor = provider.selectedTallaValor;
    _tempColorId = provider.selectedColorId;
    _tempColorNombre = provider.selectedColorNombre;
    _tempOrdering = provider.ordering ?? 'recientes';
    _tempGenero = provider.selectedGenero;

    final min = provider.minPrice ?? 0.0;
    final max = provider.maxPrice ?? 1500.0;
    _priceRange = RangeValues(min, max > 1500 ? 1500 : max);

    // Make sure filter options are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.loadFilterOptions();
    });
  }

  Color _parseHex(String? hexString) {
    if (hexString == null || hexString.isEmpty) return const Color(0xFFCBD5E1);
    String hex = hexString.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return Color(int.tryParse(hex, radix: 16) ?? 0xFFCBD5E1);
  }

  bool _isColorDark(Color color) {
    return color.computeLuminance() < 0.5;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogProvider>(
      builder: (context, provider, child) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle & Header
              Padding(
                padding: const EdgeInsets.only(top: 14, left: 20, right: 20, bottom: 8),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.filter_list_rounded, color: AppColors.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Filtros de Búsqueda',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _tempCategoryId = null;
                              _tempCategoryName = null;
                              _tempTemporadaId = null;
                              _tempTemporadaName = null;
                              _tempTallaId = null;
                              _tempTallaValor = null;
                              _tempColorId = null;
                              _tempColorNombre = null;
                              _priceRange = const RangeValues(0, 1500);
                              _tempOrdering = 'recientes';
                              _tempGenero = null;
                            });
                          },
                          icon: const Icon(Icons.refresh, size: 16, color: AppColors.accent),
                          label: const Text(
                            'Limpiar',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Scrollable Filters Form
              Flexible(
                child: provider.isLoadingFilterOptions && provider.categories.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(color: AppColors.accent),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        children: [
                          // 0. Género (espejo del sidebar web)
                          _buildSectionTitle('Género'),
                          const SizedBox(height: 8),
                          _buildGenderChips(),
                          const SizedBox(height: 20),

                          // 1. Categorías
                          _buildSectionTitle('Categoría'),
                          const SizedBox(height: 8),
                          _buildCategoryChips(provider.categories),
                          const SizedBox(height: 20),

                          // 2. Rango de Precio
                          _buildPriceRangeSection(),
                          const SizedBox(height: 20),

                          // 3. Tallas
                          if (provider.sizes.isNotEmpty) ...[
                            _buildSectionTitle('Talla'),
                            const SizedBox(height: 8),
                            _buildSizeChips(provider.sizes),
                            const SizedBox(height: 20),
                          ],

                          // 4. Colores
                          if (provider.colors.isNotEmpty) ...[
                            _buildSectionTitle(
                              _tempColorNombre != null
                                  ? 'Color: $_tempColorNombre'
                                  : 'Color',
                            ),
                            const SizedBox(height: 8),
                            _buildColorGrid(provider.colors),
                            const SizedBox(height: 20),
                          ],

                          // 5. Temporadas
                          if (provider.seasons.isNotEmpty) ...[
                            _buildSectionTitle('Temporada'),
                            const SizedBox(height: 8),
                            _buildSeasonChips(provider.seasons),
                            const SizedBox(height: 20),
                          ],

                          // 6. Ordenar Por
                          _buildSectionTitle('Ordenar Por'),
                          const SizedBox(height: 8),
                          _buildSortChips(),
                          const SizedBox(height: 16),
                        ],
                      ),
              ),

              // Footer Apply Button
              Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(context).padding.bottom + 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    context.read<CatalogProvider>().applyFilters(
                          categoryId: _tempCategoryId,
                          categoryName: _tempCategoryName,
                          temporadaId: _tempTemporadaId,
                          temporadaName: _tempTemporadaName,
                          tallaId: _tempTallaId,
                          tallaValor: _tempTallaValor,
                          colorId: _tempColorId,
                          colorNombre: _tempColorNombre,
                          minPrice: _priceRange.start > 0 ? _priceRange.start : null,
                          maxPrice: _priceRange.end < 1500 ? _priceRange.end : null,
                          ordering: _tempOrdering,
                          genero: _tempGenero,
                        );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Aplicar Filtros',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGenderChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _genderOptions.map((opt) {
        final id = opt['id'];
        final isSelected = _tempGenero == id;
        return ChoiceChip(
          label: Text(opt['label']!),
          selected: isSelected,
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceVariant,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: isSelected ? AppColors.primary : AppColors.border),
          ),
          onSelected: (_) {
            setState(() {
              _tempGenero = id;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(String title) {    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: 0.3,
          ),
    );
  }

  Widget _buildCategoryChips(List<CategoryModel> categories) {
    final isAll = _tempCategoryId == null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Todas'),
          selected: isAll,
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceVariant,
          labelStyle: TextStyle(
            color: isAll ? Colors.white : AppColors.textPrimary,
            fontWeight: isAll ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: isAll ? AppColors.primary : AppColors.border),
          ),
          onSelected: (_) {
            setState(() {
              _tempCategoryId = null;
              _tempCategoryName = null;
            });
          },
        ),
        ...categories.map((cat) {
          final isSelected = _tempCategoryId == cat.id;
          return ChoiceChip(
            label: Text(cat.nombre),
            selected: isSelected,
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surfaceVariant,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
            ),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _tempCategoryId = cat.id;
                  _tempCategoryName = cat.nombre;
                } else {
                  _tempCategoryId = null;
                  _tempCategoryName = null;
                }
              });
            },
          );
        }),
      ],
    );
  }

  Widget _buildPriceRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Rango de Precio'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Bs. ${_priceRange.start.round()} - Bs. ${_priceRange.end.round()}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RangeSlider(
          values: _priceRange,
          min: 0,
          max: 1500,
          divisions: 30,
          activeColor: AppColors.accent,
          inactiveColor: AppColors.border,
          labels: RangeLabels(
            'Bs. ${_priceRange.start.round()}',
            'Bs. ${_priceRange.end.round()}',
          ),
          onChanged: (RangeValues values) {
            setState(() {
              _priceRange = values;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSizeChips(List<TallaModel> sizes) {
    final isAll = _tempTallaId == null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Todas'),
          selected: isAll,
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceVariant,
          labelStyle: TextStyle(
            color: isAll ? Colors.white : AppColors.textPrimary,
            fontWeight: isAll ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: isAll ? AppColors.primary : AppColors.border),
          ),
          onSelected: (_) {
            setState(() {
              _tempTallaId = null;
              _tempTallaValor = null;
            });
          },
        ),
        ...sizes.map((sz) {
          final isSelected = _tempTallaId == sz.id;
          return ChoiceChip(
            label: Text(sz.valor),
            selected: isSelected,
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surfaceVariant,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
            ),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _tempTallaId = sz.id;
                  _tempTallaValor = sz.valor;
                } else {
                  _tempTallaId = null;
                  _tempTallaValor = null;
                }
              });
            },
          );
        }),
      ],
    );
  }

  Widget _buildColorGrid(List<ColorFilterModel> colors) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: colors.map((col) {
        final isSelected = _tempColorId == col.id;
        final colorValue = _parseHex(col.codigoHex);
        final isDark = _isColorDark(colorValue);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _tempColorId = null;
                _tempColorNombre = null;
              } else {
                _tempColorId = col.id;
                _tempColorNombre = col.nombre;
              }
            });
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorValue,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.accent : AppColors.border,
                    width: isSelected ? 3 : 1.5,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 20,
                        color: isDark ? Colors.white : Colors.black87,
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 44,
                child: Text(
                  col.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.accent : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSeasonChips(List<TemporadaModel> seasons) {
    final isAll = _tempTemporadaId == null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Todas'),
          selected: isAll,
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceVariant,
          labelStyle: TextStyle(
            color: isAll ? Colors.white : AppColors.textPrimary,
            fontWeight: isAll ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: isAll ? AppColors.primary : AppColors.border),
          ),
          onSelected: (_) {
            setState(() {
              _tempTemporadaId = null;
              _tempTemporadaName = null;
            });
          },
        ),
        ...seasons.map((seas) {
          final isSelected = _tempTemporadaId == seas.id;
          return ChoiceChip(
            label: Text(seas.nombre),
            selected: isSelected,
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surfaceVariant,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
            ),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _tempTemporadaId = seas.id;
                  _tempTemporadaName = seas.nombre;
                } else {
                  _tempTemporadaId = null;
                  _tempTemporadaName = null;
                }
              });
            },
          );
        }),
      ],
    );
  }

  Widget _buildSortChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _sortOptions.map((opt) {
        final isSelected = _tempOrdering == opt['id'];
        return ChoiceChip(
          label: Text(opt['label']!),
          selected: isSelected,
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceVariant,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
          ),
          onSelected: (selected) {
            setState(() {
              _tempOrdering = selected ? opt['id'] : 'recientes';
            });
          },
        );
      }).toList(),
    );
  }
}
