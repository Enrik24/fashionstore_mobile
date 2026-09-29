import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/models/ai_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/favorites_provider.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(List<dynamic>)? onAddOutfitToCart;
  final Function(dynamic)? onAddProductToCart;
  final bool isAddingToCart;

  const ChatBubble({
    super.key,
    required this.message,
    this.onAddOutfitToCart,
    this.onAddProductToCart,
    this.isAddingToCart = false,
  });

  /// Guarda o quita un producto del chat en favoritos (CU21/CU25).
  static Future<void> _toggleFavorite(
      BuildContext context, int productoId, bool isFav) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Inicia sesión para guardar tus favoritos'),
          action: SnackBarAction(
            label: 'Ingresar',
            textColor: Colors.white,
            onPressed: () => context.push('/login'),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }
    final favs = context.read<FavoritesProvider>();
    await favs.toggle(productoId);
    if (!context.mounted) return;
    if (favs.errorMessage != null &&
        favs.isFavorite(productoId) == isFav) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(favs.errorMessage!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String? _extractImageUrl(dynamic p) {    if (p is! Map) return null;
    if (p['imagen_url'] != null && p['imagen_url'].toString().isNotEmpty) {
      return p['imagen_url'].toString();
    }
    if (p['imagen'] != null && p['imagen'].toString().isNotEmpty) {
      return p['imagen'].toString();
    }
    if (p['imagen_principal'] != null && p['imagen_principal'].toString().isNotEmpty) {
      return p['imagen_principal'].toString();
    }
    final imgs = p['imagenes'];
    if (imgs is List && imgs.isNotEmpty) {
      return imgs.first.toString();
    }
    return null;
  }

  double _calculateTotal(List<dynamic> products) {
    double total = 0.0;
    for (final p in products) {
      if (p is Map && p['precio'] != null) {
        final price = p['precio'];
        if (price is num) {
          total += price.toDouble();
        } else if (price is String) {
          total += double.tryParse(price) ?? 0.0;
        }
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final timeFormat = DateFormat('HH:mm');
    final prods = message.productosMencionados;
    final hasProducts = prods != null && prods.isNotEmpty;
    final isOutfit = message.tipoRespuesta == 'outfit' ||
        (hasProducts && prods.length >= 2 && message.content.toLowerCase().contains('look') ||
            message.content.toLowerCase().contains('outfit'));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.accent : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
                      bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          height: 1.4,
                          color: isUser ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeFormat.format(message.timestamp),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: isUser ? Colors.white.withOpacity(0.7) : AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isUser && hasProducts) ...[
                  const SizedBox(height: 10),
                  if (isOutfit)
                    _buildOutfitCard(context, prods)
                  else if (prods.length == 1)
                    _buildSingleProductCard(context, prods.first)
                  else
                    _buildMentionedProductsList(context, prods),
                ],
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- OUTFIT LOOK CARD ---
  Widget _buildOutfitCard(BuildContext context, List<dynamic> products) {
    final total = _calculateTotal(products);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.06),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.checkroom, color: AppColors.accent, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Look completo sugerido por tu estilista',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Carrusel de prendas del look
          SizedBox(
            height: 145,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final p = products[index];
                final isMap = p is Map;
                final rawId = isMap ? p['id'] : null;
                final int? id = rawId is int ? rawId : (rawId != null ? int.tryParse(rawId.toString()) : null);
                final nombre = isMap ? (p['nombre']?.toString() ?? '') : '';
                final precio = isMap ? ((p['precio'] as num?) ?? 0) : 0;
                final img = _extractImageUrl(p);

                return InkWell(
                  onTap: id != null ? () => context.push('/catalog/$id') : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 105,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          child: SizedBox(
                            height: 75,
                            width: double.infinity,
                            child: img != null && img.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: img,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(Icons.checkroom, color: AppColors.accent),
                                  )
                                : const Icon(Icons.checkroom, color: AppColors.accent),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Bs. ${precio.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total del look:',
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textLight),
                  ),
                  Text(
                    'Bs. ${total.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: isAddingToCart ? null : () => onAddOutfitToCart?.call(products),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: isAddingToCart
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.shopping_cart_outlined, size: 16),
                label: Text(
                  isAddingToCart ? 'Agregando...' : 'Agregar Look',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- SINGLE PRODUCT CARD ---
  Widget _buildSingleProductCard(BuildContext context, dynamic p) {
    final isMap = p is Map;
    final rawId = isMap ? p['id'] : null;
    final int? id = rawId is int ? rawId : (rawId != null ? int.tryParse(rawId.toString()) : null);
    final nombre = isMap ? (p['nombre']?.toString() ?? '') : '';
    final categoria = isMap ? (p['categoria']?.toString() ?? '') : '';
    final descripcion = isMap ? (p['descripcion']?.toString() ?? '') : '';
    final precio = isMap ? ((p['precio'] as num?) ?? 0) : 0;
    final img = _extractImageUrl(p);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: img != null && img.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(Icons.checkroom, color: AppColors.accent),
                        )
                      : const Icon(Icons.checkroom, color: AppColors.accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (categoria.isNotEmpty)
                      Text(
                        categoria.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent,
                        ),
                      ),
                    Text(
                      nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (descripcion.isNotEmpty)
                      Text(
                        descripcion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Bs. ${precio.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Guardar en favoritos (CU21/CU25)
              if (id != null)
                Consumer<FavoritesProvider>(
                  builder: (context, favs, _) {
                    final isFav = favs.isFavorite(id);
                    return IconButton(
                      icon: Icon(
                        isFav
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 20,
                        color: isFav
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      tooltip: isFav
                          ? 'Quitar de favoritos'
                          : 'Guardar en favoritos',
                      onPressed: () =>
                          _toggleFavorite(context, id, isFav),
                    );
                  },
                ),
              Expanded(
                child: OutlinedButton(
                  onPressed: id != null ? () => context.push('/catalog/$id') : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Ver detalle', style: GoogleFonts.inter(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => onAddProductToCart?.call(p),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.add_shopping_cart, size: 15),
                  label: Text('+ Carrito', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- MULTIPLE PRODUCTS HORIZONTAL LIST ---
  Widget _buildMentionedProductsList(BuildContext context, List<dynamic> products) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final p = products[index];
          final isMap = p is Map;
          final rawId = isMap ? p['id'] : null;
          final int? id = rawId is int ? rawId : (rawId != null ? int.tryParse(rawId.toString()) : null);
          final nombre = isMap ? (p['nombre']?.toString() ?? '') : '';
          final categoria = isMap ? (p['categoria']?.toString() ?? '') : '';
          final precio = isMap ? ((p['precio'] as num?) ?? 0) : 0;
          final img = _extractImageUrl(p);

          return Container(
            width: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: id != null ? () => context.push('/catalog/$id') : null,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    child: SizedBox(
                      height: 85,
                      width: double.infinity,
                      child: img != null && img.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: img,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(Icons.checkroom, color: AppColors.accent),
                            )
                          : const Icon(Icons.checkroom, color: AppColors.accent),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (categoria.isNotEmpty)
                        Text(
                          categoria,
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accent),
                        ),
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textDark),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Bs. ${precio.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                          InkWell(
                            onTap: () => onAddProductToCart?.call(p),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.add_shopping_cart, size: 14, color: AppColors.primary),
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
        },
      ),
    );
  }
}
