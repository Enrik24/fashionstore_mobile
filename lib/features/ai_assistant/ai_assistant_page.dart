import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../config/theme.dart';
import '../../core/providers/ai_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/services/catalog_service.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/recommendations_section.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _showRecommendations = true;
  bool _isAddingToCart = false;
  bool _speechAvailable = false;
  bool _isListening = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final clienteId = auth.clienteProfile?.id;
      context.read<AiProvider>().loadRecommendations(clienteId: clienteId);
    });
  }

  void _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
              if (_lastWords.trim().isNotEmpty) {
                final query = _lastWords.trim();
                _lastWords = '';
                _handleSend(query);
              }
            }
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _isListening = false);
          }
        },
      );
      if (mounted) setState(() {});
    } catch (_) {
      _speechAvailable = false;
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reconocimiento de voz no disponible o permisos no concedidos.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      if (_lastWords.trim().isNotEmpty) {
        final query = _lastWords.trim();
        _lastWords = '';
        _handleSend(query);
      }
    } else {
      _lastWords = '';
      setState(() => _isListening = true);

      await _speech.listen(
        localeId: 'es_BO',
        listenFor: const Duration(seconds: 25),
        pauseFor: const Duration(seconds: 3),
        onResult: (result) {
          if (mounted) {
            setState(() {
              _lastWords = result.recognizedWords;
              _textController.text = result.recognizedWords;
            });
            if (result.finalResult && _lastWords.trim().isNotEmpty) {
              final query = _lastWords.trim();
              _lastWords = '';
              _handleSend(query);
            }
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend([String? presetText]) async {
    final text = presetText ?? _textController.text;
    if (text.trim().isEmpty) return;

    final aiProvider = context.read<AiProvider>();
    _textController.clear();
    _scrollToBottom();

    final response = await aiProvider.sendMessage(text);
    _scrollToBottom();

    // Manejar acción conversacional devuelta por la IA (ej: agregar outfit al carrito)
    if (response != null && response.accion == 'agregar_carrito') {
      final prods = response.productosMencionados;
      if (prods.isNotEmpty) {
        await _addOutfitToCart(prods, silent: false);
      } else {
        // Buscar el último look con productos en el historial
        final lastMsgWithProds = aiProvider.chatMessages.reversed.firstWhere(
          (m) => m.productosMencionados != null && m.productosMencionados!.isNotEmpty,
          orElse: () => aiProvider.chatMessages.first,
        );
        if (lastMsgWithProds.productosMencionados != null &&
            lastMsgWithProds.productosMencionados!.isNotEmpty) {
          await _addOutfitToCart(lastMsgWithProds.productosMencionados!, silent: false);
        }
      }
    }
  }

  /// Agrega todas las prendas de un outfit sugerido al carrito
  Future<void> _addOutfitToCart(List<dynamic> products, {bool silent = false}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Inicia sesión para añadir productos a tu carrito'),
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

    if (products.isEmpty) return;

    setState(() => _isAddingToCart = true);

    final cartProvider = context.read<CartProvider>();
    final catalogService = context.read<CatalogService>();
    int addedCount = 0;

    for (final p in products) {
      if (p is! Map) continue;

      int? variantId;
      if (p['variante_id'] != null) {
        variantId = p['variante_id'] is int
            ? p['variante_id']
            : int.tryParse(p['variante_id'].toString());
      }

      final rawId = p['id'] ?? p['producto_id'];
      final int? prodId = rawId is int ? rawId : (rawId != null ? int.tryParse(rawId.toString()) : null);

      if (variantId == null && prodId != null) {
        try {
          final prodDetail = await catalogService.getProductoDetalle(prodId);
          if (prodDetail.variantes.isNotEmpty) {
            variantId = prodDetail.variantes.first.id;
          }
        } catch (_) {}
      }

      if (variantId != null) {
        final ok = await cartProvider.addToCart(variantId: variantId, quantity: 1);
        if (ok) addedCount++;
      }
    }

    if (!mounted) return;
    setState(() => _isAddingToCart = false);

    if (addedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡Se añadieron $addedCount prendas de tu look al carrito! 🛍️'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Ver Carrito',
            textColor: Colors.white,
            onPressed: () => context.push('/cart'),
          ),
        ),
      );

      if (!silent) {
        context.read<AiProvider>().addAssistantFeedback(
          '🛍️ ¡Listo! He añadido las $addedCount prendas de este look a tu carrito de compras.',
        );
        _scrollToBottom();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron agregar las prendas. Revisa la disponibilidad.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Agrega un producto individual sugerido al carrito
  Future<void> _addProductToCart(dynamic product) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Inicia sesión para añadir productos a tu carrito'),
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

    if (product is! Map) return;

    final nombre = product['nombre']?.toString() ?? 'Producto';
    int? variantId;
    if (product['variante_id'] != null) {
      variantId = product['variante_id'] is int
          ? product['variante_id']
          : int.tryParse(product['variante_id'].toString());
    }

    final rawId = product['id'] ?? product['producto_id'];
    final int? prodId = rawId is int ? rawId : (rawId != null ? int.tryParse(rawId.toString()) : null);

    final cartProvider = context.read<CartProvider>();
    final catalogService = context.read<CatalogService>();

    if (variantId == null && prodId != null) {
      try {
        final prodDetail = await catalogService.getProductoDetalle(prodId);
        if (prodDetail.variantes.isNotEmpty) {
          variantId = prodDetail.variantes.first.id;
        }
      } catch (_) {}
    }

    if (variantId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Producto sin stock o variantes disponibles.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final ok = await cartProvider.addToCart(variantId: variantId, quantity: 1);

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡"$nombre" añadido al carrito!'),
          backgroundColor: AppColors.success,
          action: SnackBarAction(
            label: 'Ver Carrito',
            textColor: Colors.white,
            onPressed: () => context.push('/cart'),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo añadir el producto al carrito.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiProvider = context.watch<AiProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Asesor de Moda IA',
        showLogo: false,
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.accessibility_new, color: AppColors.accent),
            tooltip: 'Vestidor Virtual',
            onPressed: () => context.push('/ar-fitting'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              if (val == 'clear') {
                aiProvider.clearChat();
              } else if (val == 'toggle_recs') {
                setState(() => _showRecommendations = !_showRecommendations);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'toggle_recs',
                child: Row(
                  children: [
                    Icon(
                      _showRecommendations ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(_showRecommendations ? 'Ocultar sugerencias' : 'Ver sugerencias'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined, size: 20, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Reiniciar conversación'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: aiProvider.chatMessages.length,
              itemBuilder: (context, index) {
                final msg = aiProvider.chatMessages[index];
                return ChatBubble(
                  message: msg,
                  onAddOutfitToCart: (products) => _addOutfitToCart(products),
                  onAddProductToCart: (product) => _addProductToCart(product),
                  isAddingToCart: _isAddingToCart,
                );
              },
            ),
          ),

          // Listening banner when recording
          if (_isListening)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🎙️ Escuchando... Di tu consulta de moda',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _toggleListening,
                    child: Text(
                      'Detener',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Loading indicator
          if (aiProvider.isChatLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Tu estilista virtual está pensando...',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textLight,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          // Suggested prompts chips
          if (aiProvider.currentSuggestions.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: aiProvider.currentSuggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final suggestion = aiProvider.currentSuggestions[index];
                  return ActionChip(
                    backgroundColor: Colors.white,
                    side: BorderSide(color: AppColors.accent.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    label: Text(
                      suggestion,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textDark),
                    ),
                    onPressed: () => _handleSend(suggestion),
                  );
                },
              ),
            ),

          const SizedBox(height: 8),

          // Input bar with Voice Recognition button
          _buildInputBar(aiProvider.isChatLoading),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isChatLoading) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Voice Mic Button
          Container(
            decoration: BoxDecoration(
              color: _isListening ? Colors.red.shade50 : AppColors.surfaceVariant.withOpacity(0.7),
              shape: BoxShape.circle,
              border: Border.all(
                color: _isListening ? Colors.red : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: IconButton(
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none_outlined,
                color: _isListening ? Colors.red : AppColors.primary,
                size: 22,
              ),
              tooltip: 'Hablar por voz',
              onPressed: isChatLoading ? null : _toggleListening,
            ),
          ),
          const SizedBox(width: 8),

          // Text Field
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _isListening ? Colors.red.shade300 : Colors.grey.shade200),
              ),
              child: TextField(
                controller: _textController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                decoration: InputDecoration(
                  hintText: _isListening ? 'Escuchando tu voz...' : 'Pregúntale a tu estilista IA...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13,
                    color: _isListening ? Colors.red.shade400 : AppColors.textLight,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send Button
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: isChatLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: isChatLoading ? null : () => _handleSend(),
            ),
          ),
        ],
      ),
    );
  }
}
