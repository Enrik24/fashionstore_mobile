class RecomendacionItem {
  final int productoId;
  final String nombre;
  final String razon;
  final String? imagenUrl;
  final List<String> imagenes;
  final double? precio;
  final String? categoria;
  final String? genero;
  final String? sku;

  RecomendacionItem({
    required this.productoId,
    required this.nombre,
    required this.razon,
    this.imagenUrl,
    this.imagenes = const [],
    this.precio,
    this.categoria,
    this.genero,
    this.sku,
  });

  factory RecomendacionItem.fromJson(Map<String, dynamic> json) {
    var rawImgs = json['imagenes'];
    List<String> imgs = [];
    if (rawImgs is List) {
      imgs = rawImgs.map((e) => e.toString()).toList();
    }
    final single = json['imagen_url']?.toString();
    if (imgs.isEmpty && single != null && single.isNotEmpty) {
      imgs = [single];
    }
    var pid = json['producto_id'];
    return RecomendacionItem(
      productoId: pid is int ? pid : int.tryParse(pid?.toString() ?? '') ?? 0,
      nombre: json['nombre'] as String? ?? '',
      razon: json['razon'] as String? ?? '',
      imagenUrl: single,
      imagenes: imgs,
      precio: (json['precio'] as num?)?.toDouble(),
      categoria: json['categoria'] as String?,
      genero: json['genero']?.toString(),
      sku: json['sku']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'producto_id': productoId,
    'nombre': nombre,
    'razon': razon,
    'imagen_url': imagenUrl,
    'imagenes': imagenes,
    'precio': precio,
    'categoria': categoria,
    'genero': genero,
    'sku': sku,
  };
}

class RecomendacionResponse {
  final int? clienteId;
  final String? estiloDetectado;
  final String mensajePersonalizado;
  final List<RecomendacionItem> recomendaciones;

  RecomendacionResponse({
    this.clienteId,
    this.estiloDetectado,
    required this.mensajePersonalizado,
    required this.recomendaciones,
  });

  factory RecomendacionResponse.fromJson(Map<String, dynamic> json) {
    var rawList = json['recomendaciones'];
    List<RecomendacionItem> items = [];
    if (rawList is List) {
      items = rawList
          .map((i) => RecomendacionItem.fromJson(i as Map<String, dynamic>))
          .toList();
    }
    return RecomendacionResponse(
      clienteId: json['cliente_id'] as int?,
      estiloDetectado: json['estilo_detectado'] as String?,
      mensajePersonalizado: json['mensaje_personalizado'] as String? ?? '',
      recomendaciones: items,
    );
  }
}

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final List<dynamic>? productosMencionados;
  final String? tipoRespuesta;
  final List<String>? sugerencias;
  final String? accion;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.productosMencionados,
    this.tipoRespuesta,
    this.sugerencias,
    this.accion,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    var rawProds = json['productos_mencionados'] ?? json['productos'] ?? json['productos_sugeridos'];
    List<dynamic>? prods;
    if (rawProds is List) {
      prods = rawProds;
    }

    var rawSugerencias = json['sugerencias'] ?? json['sugerencias_rapidas'];
    List<String>? sugs;
    if (rawSugerencias is List) {
      sugs = rawSugerencias.map((e) => e.toString()).toList();
    }

    return ChatMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())
          : null,
      productosMencionados: prods,
      tipoRespuesta: json['tipo_respuesta'] as String?,
      sugerencias: sugs,
      accion: json['accion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AsistenteChatResponse {
  final String respuesta;
  final List<String> sugerencias;
  final List<dynamic> productosMencionados;
  final String tipoRespuesta;
  final String? accion;

  AsistenteChatResponse({
    required this.respuesta,
    this.sugerencias = const [],
    this.productosMencionados = const [],
    this.tipoRespuesta = 'texto',
    this.accion,
  });

  factory AsistenteChatResponse.fromJson(Map<String, dynamic> json) {
    var rawSugerencias = json['sugerencias'] ?? json['sugerencias_rapidas'];
    List<String> sugs = [];
    if (rawSugerencias is List) {
      sugs = rawSugerencias.map((e) => e.toString()).toList();
    }

    var rawProds = json['productos_mencionados'] ?? json['productos'] ?? json['productos_sugeridos'];
    List<dynamic> prods = [];
    if (rawProds is List) {
      prods = rawProds;
    }

    return AsistenteChatResponse(
      respuesta: json['respuesta'] as String? ?? '',
      sugerencias: sugs,
      productosMencionados: prods,
      tipoRespuesta: json['tipo_respuesta'] as String? ?? 'texto',
      accion: json['accion'] as String?,
    );
  }
}

class VestidorVirtualResponse {
  final String resultadoUrl;
  final int productoId;
  final String productoNombre;
  final String mensaje;
  final Map<String, dynamic>? detallesAjuste;

  VestidorVirtualResponse({
    required this.resultadoUrl,
    required this.productoId,
    required this.productoNombre,
    required this.mensaje,
    this.detallesAjuste,
  });

  factory VestidorVirtualResponse.fromJson(Map<String, dynamic> json) {
    return VestidorVirtualResponse(
      resultadoUrl: json['resultado_url'] as String? ?? '',
      productoId: json['producto_id'] as int? ?? 0,
      productoNombre: json['producto_nombre'] as String? ?? '',
      mensaje: json['mensaje'] as String? ?? '',
      detallesAjuste: json['detalles_ajuste'] as Map<String, dynamic>?,
    );
  }
}

class TendenciaItem {
  final String tendencia;
  final String impacto;
  final String recomendacion;

  TendenciaItem({
    required this.tendencia,
    required this.impacto,
    required this.recomendacion,
  });

  factory TendenciaItem.fromJson(Map<String, dynamic> json) {
    return TendenciaItem(
      tendencia: json['tendencia'] as String? ?? '',
      impacto: json['impacto'] as String? ?? '',
      recomendacion: json['recomendacion'] as String? ?? '',
    );
  }
}

class TendenciasResponse {
  final DateTime fechaAnalisis;
  final List<TendenciaItem> tendenciasDestacadas;
  final List<String> categoriasEnAlza;
  final String prediccionDemanda;

  TendenciasResponse({
    required this.fechaAnalisis,
    required this.tendenciasDestacadas,
    required this.categoriasEnAlza,
    required this.prediccionDemanda,
  });

  factory TendenciasResponse.fromJson(Map<String, dynamic> json) {
    var rawTendencias = json['tendencias_destacadas'];
    List<TendenciaItem> tens = [];
    if (rawTendencias is List) {
      tens = rawTendencias
          .map((t) => TendenciaItem.fromJson(t as Map<String, dynamic>))
          .toList();
    }

    var rawCats = json['categorias_en_alza'];
    List<String> cats = [];
    if (rawCats is List) {
      cats = rawCats.map((c) => c.toString()).toList();
    }

    return TendenciasResponse(
      fechaAnalisis: json['fecha_analisis'] != null
          ? DateTime.tryParse(json['fecha_analisis'].toString()) ??
                DateTime.now()
          : DateTime.now(),
      tendenciasDestacadas: tens,
      categoriasEnAlza: cats,
      prediccionDemanda: json['prediccion_demanda'] as String? ?? '',
    );
  }
}
