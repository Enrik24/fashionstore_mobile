import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/ai_model.dart';
import '../services/ai_service.dart';

class AiProvider with ChangeNotifier {
  final AiService _aiService;

  AiProvider({required AiService aiService}) : _aiService = aiService {
    // Inicializar chat con saludo de bienvenida
    _chatMessages.add(
      ChatMessage(
        role: 'assistant',
        content: '¡Hola! Soy tu estilista y asesor virtual de FashionStore. ¿En qué puedo ayudarte hoy? Puedes preguntarme por combinaciones, ocasiones especiales, tendencias o tallas.',
      ),
    );
    _currentSuggestions = [
      '¿Qué vestir para una boda de día?',
      'Tendencias de esta temporada',
      'Prendas casuales elegantes',
      '¿Cómo saber mi talla ideal?',
    ];
  }

  // --- RECOMENDACIONES ---
  RecomendacionResponse? _recommendations;
  bool _isLoadingRecommendations = false;
  String? _recommendationsError;

  RecomendacionResponse? get recommendations => _recommendations;
  bool get isLoadingRecommendations => _isLoadingRecommendations;
  String? get recommendationsError => _recommendationsError;

  Future<void> loadRecommendations({int? clienteId, String? preferencias}) async {
    _isLoadingRecommendations = true;
    _recommendationsError = null;
    notifyListeners();

    try {
      _recommendations = await _aiService.getRecomendaciones(
        clienteId: clienteId,
        preferencias: preferencias,
      );
    } catch (e) {
      _recommendationsError = e.toString();
    } finally {
      _isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  // --- ASISTENTE DE CHAT ---
  final List<ChatMessage> _chatMessages = [];
  bool _isChatLoading = false;
  String? _chatError;
  List<String> _currentSuggestions = [];

  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
  bool get isChatLoading => _isChatLoading;
  String? get chatError => _chatError;
  List<String> get currentSuggestions => _currentSuggestions;

  Future<AsistenteChatResponse?> sendMessage(String text, {String? categoriaInteres}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Agregar mensaje del usuario
    final userMsg = ChatMessage(role: 'user', content: trimmed);
    _chatMessages.add(userMsg);
    _isChatLoading = true;
    _chatError = null;
    notifyListeners();

    try {
      // Filtrar historial para enviar a Groq (máximo últimos 6 mensajes)
      final historyList = _chatMessages
          .where((m) => m != userMsg)
          .toList();
      final historyToSend = historyList.length > 6
          ? historyList.sublist(historyList.length - 6)
          : historyList;

      final response = await _aiService.chatAsistente(
        mensaje: trimmed,
        historial: historyToSend,
        categoriaInteres: categoriaInteres,
      );

      _chatMessages.add(
        ChatMessage(
          role: 'assistant',
          content: response.respuesta,
          productosMencionados: response.productosMencionados,
          tipoRespuesta: response.tipoRespuesta,
          sugerencias: response.sugerencias,
          accion: response.accion,
        ),
      );
      if (response.sugerencias.isNotEmpty) {
        _currentSuggestions = response.sugerencias;
      }
      return response;
    } catch (e) {
      _chatError = e.toString();
      _chatMessages.add(
        ChatMessage(
          role: 'assistant',
          content: 'Lo siento, tuve un problema al procesar tu solicitud. Por favor intenta de nuevo.',
        ),
      );
      return null;
    } finally {
      _isChatLoading = false;
      notifyListeners();
    }
  }

  void addAssistantFeedback(String content) {
    _chatMessages.add(
      ChatMessage(
        role: 'assistant',
        content: content,
      ),
    );
    notifyListeners();
  }

  void clearChat() {
    _chatMessages.clear();
    _chatMessages.add(
      ChatMessage(
        role: 'assistant',
        content: '¡Hola de nuevo! ¿En qué otra consulta de moda puedo asistirte?',
      ),
    );
    _currentSuggestions = [
      '¿Qué vestir para una cena formal?',
      'Ver recomendaciones para mí',
      'Prendas de nueva colección',
    ];
    notifyListeners();
  }

  // --- VESTIDOR VIRTUAL ---
  VestidorVirtualResponse? _fittingResult;
  bool _isFittingLoading = false;
  String? _fittingError;
  File? _selectedImage;

  VestidorVirtualResponse? get fittingResult => _fittingResult;
  bool get isFittingLoading => _isFittingLoading;
  String? get fittingError => _fittingError;
  File? get selectedImage => _selectedImage;

  void setSelectedImage(File? file) {
    _selectedImage = file;
    _fittingResult = null;
    _fittingError = null;
    notifyListeners();
  }

  Future<void> tryOnItem({
    required int productoId,
    int? varianteId,
  }) async {
    _isFittingLoading = true;
    _fittingError = null;
    notifyListeners();

    try {
      String? base64Image;
      if (_selectedImage != null && await _selectedImage!.exists()) {
        final bytes = await _selectedImage!.readAsBytes();
        base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      _fittingResult = await _aiService.vestidorVirtual(
        productoId: productoId,
        varianteId: varianteId,
        imagenUsuarioBase64: base64Image,
      );
    } catch (e) {
      _fittingError = e.toString();
    } finally {
      _isFittingLoading = false;
      notifyListeners();
    }
  }

  void resetFitting() {
    _selectedImage = null;
    _fittingResult = null;
    _fittingError = null;
    notifyListeners();
  }

  // --- TENDENCIAS DE MODA ---
  TendenciasResponse? _trendsResult;
  bool _isTrendsLoading = false;
  String? _trendsError;

  TendenciasResponse? get trendsResult => _trendsResult;
  bool get isTrendsLoading => _isTrendsLoading;
  String? get trendsError => _trendsError;

  Future<void> loadTrends() async {
    _isTrendsLoading = true;
    _trendsError = null;
    notifyListeners();

    try {
      _trendsResult = await _aiService.getTendencias();
    } catch (e) {
      _trendsError = e.toString();
    } finally {
      _isTrendsLoading = false;
      notifyListeners();
    }
  }
}
