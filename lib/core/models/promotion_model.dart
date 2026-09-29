/// Promoción pública activa (CU24, solo informativa en móvil).
/// Backend: `GET /public/promociones/activas` -> PromocionPublicaResponse
/// {id?, nombre?, tipo, valor?, fecha_fin?, producto_ids, categoria_ids}
class PromotionModel {
  final int? id;
  final String? nombre;
  final String tipo;
  final double? valor;
  final List<int> productoIds;
  final List<int> categoriaIds;

  PromotionModel({
    this.id,
    this.nombre,
    required this.tipo,
    this.valor,
    this.productoIds = const [],
    this.categoriaIds = const [],
  });

  bool get isPorcentaje =>
      tipo.toUpperCase() == 'PORCENTAJE' && (valor ?? 0) > 0;
  bool get is2x1 => tipo.toUpperCase() == 'DOS_POR_UNO';

  static int _parseInt(dynamic raw, [int fallback = 0]) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static List<int> _parseIds(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => _parseInt(e)).toList();
    }
    return [];
  }

  factory PromotionModel.fromJson(Map<String, dynamic> json) {
    final rawValor = json['valor'];
    return PromotionModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? ''),
      nombre: json['nombre']?.toString(),
      tipo: json['tipo']?.toString() ?? '',
      valor: rawValor == null
          ? null
          : (rawValor is num
              ? rawValor.toDouble()
              : double.tryParse(rawValor.toString())),
      productoIds: _parseIds(json['producto_ids']),
      categoriaIds: _parseIds(json['categoria_ids']),
    );
  }
}
