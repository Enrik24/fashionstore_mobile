import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../core/models/product_model.dart';
import '../../core/providers/ai_provider.dart';
import '../../core/providers/catalog_provider.dart';
import '../../core/widgets/custom_app_bar.dart';

class ArFittingPage extends StatefulWidget {
  final int? initialProductId;

  const ArFittingPage({
    super.key,
    this.initialProductId,
  });

  @override
  State<ArFittingPage> createState() => _ArFittingPageState();
}

class _ArFittingPageState extends State<ArFittingPage> {
  final ImagePicker _picker = ImagePicker();
  ProductModel? _selectedProduct;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final catalog = context.read<CatalogProvider>();
      if (catalog.products.isEmpty) {
        catalog.loadCatalog();
      }
      if (widget.initialProductId != null) {
        _setInitialProduct(widget.initialProductId!);
      }
    });
  }

  void _setInitialProduct(int id) {
    final catalog = context.read<CatalogProvider>();
    final match = catalog.products.where((p) => p.id == id);
    if (match.isNotEmpty) {
      setState(() => _selectedProduct = match.first);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked != null) {
        final file = File(picked.path);
        if (mounted) {
          context.read<AiProvider>().setSelectedImage(file);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showImageSourceModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Selecciona tu Foto',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toma una foto de cuerpo entero o selecciona una imagen de tu galería para la simulación de ajuste.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textLight),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                ),
                title: Text('Tomar Foto con Cámara', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
                ),
                title: Text('Elegir de la Galería', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProductSelectorModal() {
    final catalog = context.read<CatalogProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = _searchCtrl.text.toLowerCase();
          final filtered = catalog.products.where((p) {
            return p.nombre.toLowerCase().contains(query) ||
                (p.categoriaNombre?.toLowerCase().contains(query) ?? false);
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Elige la prenda para probar',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setModalState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Buscar en el catálogo...',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No se encontraron prendas'))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (ctx, i) {
                            final p = filtered[i];
                            final isSelected = _selectedProduct?.id == p.id;
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: CachedNetworkImage(
                                    imageUrl: p.primaryImage,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(Icons.checkroom),
                                  ),
                                ),
                              ),
                              title: Text(p.nombre, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                'Bs. ${p.precio.toStringAsFixed(2)} • ${p.categoriaNombre ?? ''}',
                                style: GoogleFonts.inter(fontSize: 12),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: AppColors.accent)
                                  : null,
                              onTap: () {
                                setState(() => _selectedProduct = p);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleSimulateFitting() {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona una prenda a probar'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final ai = context.read<AiProvider>();
    ai.tryOnItem(productoId: _selectedProduct!.id);
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        title: 'Vestidor Virtual',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInstructionCard(),
            const SizedBox(height: 20),
            _buildPhotoSection(ai),
            const SizedBox(height: 20),
            _buildProductSection(),
            const SizedBox(height: 24),
            _buildActionButtons(ai),
            if (ai.isFittingLoading) ...[
              const SizedBox(height: 32),
              _buildLoadingState(),
            ],
            if (ai.fittingResult != null) ...[
              const SizedBox(height: 24),
              _buildFittingResult(ai),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.08),
            AppColors.accent.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: AppColors.accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prueba con Inteligencia Artificial',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sube una foto tuya y elige una prenda de nuestra colección para analizar el entalle, corte y compatibilidad.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(AiProvider ai) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                '1. Tu Fotografía',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              if (ai.selectedImage != null)
                TextButton.icon(
                  onPressed: () => ai.setSelectedImage(null),
                  icon: const Icon(Icons.close, size: 16, color: AppColors.error),
                  label: const Text('Quitar', style: TextStyle(color: AppColors.error, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (ai.selectedImage == null)
            InkWell(
              onTap: _showImageSourceModal,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.accent.withOpacity(0.4),
                    style: BorderStyle.solid,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_a_photo_outlined, color: AppColors.accent, size: 28),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tocar para tomar o subir foto',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '(Opcional: si no subes foto, se usará un maniquí virtual)',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            )
          else
            Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: Image.file(
                      ai.selectedImage!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.edit, size: 18, color: AppColors.primary),
                      onPressed: _showImageSourceModal,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildProductSection() {
    return Container(
      padding: const EdgeInsets.all(18),
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
          Text(
            '2. Prenda a Probar',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedProduct == null)
            InkWell(
              onTap: _showProductSelectorModal,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.checkroom_outlined, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Seleccionar una prenda del catálogo...',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textLight),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CachedNetworkImage(
                        imageUrl: _selectedProduct!.primaryImage,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(Icons.checkroom),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedProduct!.nombre,
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bs. ${_selectedProduct!.precio.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _showProductSelectorModal,
                    child: const Text('Cambiar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(AiProvider ai) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
        onPressed: ai.isFittingLoading ? null : _handleSimulateFitting,
        icon: const Icon(Icons.auto_awesome, color: AppColors.accent),
        label: Text(
          'Simular en Vestidor Virtual',
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.accent),
          const SizedBox(height: 16),
          Text(
            'Procesando simulación virtual con IA...',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            'Ajustando corte, proporciones y estilo sobre tu figura.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildFittingResult(AiProvider ai) {
    final res = ai.fittingResult!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Resultado de Simulación',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Preview image if result_url is available
          if (res.resultadoUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 240,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: res.resultadoUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: Colors.grey.shade100,
                    child: const Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.background,
                    child: const Center(
                      child: Icon(Icons.checkroom, color: AppColors.accent, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            res.productoNombre,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark),
          ),
          const SizedBox(height: 6),
          Text(
            res.mensaje,
            style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
          ),

          if (res.detallesAjuste != null && res.detallesAjuste!.isNotEmpty) ...[
            const Divider(height: 28),
            Text(
              'Detalles del Ajuste:',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            ...res.detallesAjuste!.entries.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_right, size: 18, color: AppColors.accent),
                      Text(
                        '${entry.key}: ',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Expanded(
                        child: Text(
                          '${entry.value}',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textDark),
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    context.push('/reservations/create?productId=${res.productoId}');
                  },
                  icon: const Icon(Icons.event_seat_outlined, size: 16),
                  label: const Text('Apartar en Tienda', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    context.push('/catalog/${res.productoId}');
                  },
                  icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                  label: const Text('Ver Prenda', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
