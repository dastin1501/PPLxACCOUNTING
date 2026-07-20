class StockItem {
  final String id;
  final String name;
  final String sku;
  final String category;
  final int quantity;
  final String unit;
  final double price;
  final double costPrice;
  final int lowStockThreshold;
  final DateTime updatedAt;

  const StockItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.costPrice,
    required this.lowStockThreshold,
    required this.updatedAt,
  });

  bool get isLowStock => quantity <= lowStockThreshold;

  StockItem copyWith({
    String? name,
    String? sku,
    String? category,
    int? quantity,
    String? unit,
    double? price,
    double? costPrice,
    int? lowStockThreshold,
    DateTime? updatedAt,
  }) {
    return StockItem(
      id: id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'sku': sku,
      'category': category,
      'quantity': quantity,
      'unit': unit,
      'price': price,
      'costPrice': costPrice,
      'lowStockThreshold': lowStockThreshold,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory StockItem.fromMap(Map<String, Object?> map) {
    return StockItem(
      id: map['id'] as String,
      name: map['name'] as String,
      sku: map['sku'] as String,
      category: map['category'] as String,
      quantity: map['quantity'] as int,
      unit: map['unit'] as String,
      price: (map['price'] as num).toDouble(),
      costPrice: (map['costPrice'] as num).toDouble(),
      lowStockThreshold: map['lowStockThreshold'] as int,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
