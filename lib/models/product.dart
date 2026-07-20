import 'package:uuid/uuid.dart';

/// A specific sellable size/color combination under a [Product], with its
/// own SKU, quantity, and low-stock threshold. A product with no real
/// variations still has exactly one variant, with blank [size]/[color].
class ProductVariant {
  final String id;
  final String productId;
  final String sku;
  final String size;
  final String color;
  final int quantity;
  final int lowStockThreshold;
  final DateTime updatedAt;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.sku,
    required this.quantity,
    required this.lowStockThreshold,
    required this.updatedAt,
    this.size = '',
    this.color = '',
  });

  factory ProductVariant.blank({required String productId}) {
    return ProductVariant(
      id: const Uuid().v4(),
      productId: productId,
      sku: '',
      quantity: 0,
      lowStockThreshold: 5,
      updatedAt: DateTime.now(),
    );
  }

  bool get isLowStock => quantity <= lowStockThreshold;

  bool get hasVariantLabel => size.isNotEmpty || color.isNotEmpty;

  /// Formats this variant's size/color for display, e.g. "M, Grey".
  String get label => [size, color].where((v) => v.isNotEmpty).join(', ');

  ProductVariant copyWith({
    String? sku,
    String? size,
    String? color,
    int? quantity,
    int? lowStockThreshold,
    DateTime? updatedAt,
  }) {
    return ProductVariant(
      id: id,
      productId: productId,
      sku: sku ?? this.sku,
      size: size ?? this.size,
      color: color ?? this.color,
      quantity: quantity ?? this.quantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'productId': productId,
      'sku': sku,
      'size': size,
      'color': color,
      'quantity': quantity,
      'lowStockThreshold': lowStockThreshold,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ProductVariant.fromMap(Map<String, Object?> map) {
    return ProductVariant(
      id: map['id'] as String,
      productId: map['productId'] as String,
      sku: map['sku'] as String,
      size: map['size'] as String? ?? '',
      color: map['color'] as String? ?? '',
      quantity: map['quantity'] as int,
      lowStockThreshold: map['lowStockThreshold'] as int,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}

/// A product browsable in the Sell/Inventory screens, made up of one or
/// more [ProductVariant]s (e.g. different sizes/colors). Price and cost
/// price are shared across all of a product's variants.
class Product {
  final String id;
  final String name;
  final String category;
  final String unit;
  final double price;
  final double costPrice;

  /// Absolute path to a locally-stored photo for this product, or null.
  final String? imagePath;

  final DateTime updatedAt;
  final List<ProductVariant> variants;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.price,
    required this.costPrice,
    required this.updatedAt,
    required this.variants,
    this.imagePath,
  });

  int get totalQuantity => variants.fold(0, (sum, v) => sum + v.quantity);

  bool get isLowStock => variants.any((v) => v.isLowStock);

  /// True when this product has more than one variant, or its single
  /// variant carries a size/color label (as opposed to a plain product).
  bool get hasVariants => variants.length > 1 || variants.any((v) => v.hasVariantLabel);

  Product copyWith({
    String? name,
    String? category,
    String? unit,
    double? price,
    double? costPrice,
    String? imagePath,
    bool clearImage = false,
    DateTime? updatedAt,
    List<ProductVariant>? variants,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      updatedAt: updatedAt ?? this.updatedAt,
      variants: variants ?? this.variants,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'unit': unit,
      'price': price,
      'costPrice': costPrice,
      'imagePath': imagePath,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, Object?> map, List<ProductVariant> variants) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      unit: map['unit'] as String,
      price: (map['price'] as num).toDouble(),
      costPrice: (map['costPrice'] as num).toDouble(),
      imagePath: map['imagePath'] as String?,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      variants: variants,
    );
  }
}

/// A single line in the Sell screen's cart: a specific product + variant
/// combination and how many units of it are being purchased.
class CartLine {
  final Product product;
  final ProductVariant variant;
  final int quantity;

  const CartLine({required this.product, required this.variant, required this.quantity});

  double get unitPrice => product.price;

  double get subtotal => unitPrice * quantity;

  CartLine copyWith({int? quantity}) {
    return CartLine(product: product, variant: variant, quantity: quantity ?? this.quantity);
  }
}
