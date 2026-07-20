/// A single line within a completed sale, capturing a snapshot of the
/// product's name/SKU/price at the time of sale (so later edits to a stock
/// item don't rewrite history).
class SaleLineItem {
  final String id;
  final String saleId;
  final String stockId;
  final String name;
  final String sku;
  final double unitPrice;
  final int quantity;

  const SaleLineItem({
    required this.id,
    required this.saleId,
    required this.stockId,
    required this.name,
    required this.sku,
    required this.unitPrice,
    required this.quantity,
  });

  double get subtotal => unitPrice * quantity;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'saleId': saleId,
      'stockId': stockId,
      'name': name,
      'sku': sku,
      'unitPrice': unitPrice,
      'quantity': quantity,
    };
  }

  factory SaleLineItem.fromMap(Map<String, Object?> map) {
    return SaleLineItem(
      id: map['id'] as String,
      saleId: map['saleId'] as String,
      stockId: map['stockId'] as String,
      name: map['name'] as String,
      sku: map['sku'] as String,
      unitPrice: (map['unitPrice'] as num).toDouble(),
      quantity: map['quantity'] as int,
    );
  }
}

/// How a discount was specified when a sale was completed.
enum DiscountType {
  none,
  /// A flat peso amount taken off the subtotal.
  fixed,
  /// A percentage of the subtotal.
  percent;

  String get dbValue => name;

  static DiscountType fromDb(String? value) {
    return DiscountType.values.firstWhere(
      (t) => t.dbValue == value,
      orElse: () => DiscountType.none,
    );
  }
}

/// Computes the peso amount a discount removes from [subtotal], clamped so
/// it never exceeds the subtotal (and is never negative).
double computeDiscountAmount(double subtotal, DiscountType type, double value) {
  if (subtotal <= 0 || value <= 0) return 0;
  final raw = switch (type) {
    DiscountType.none => 0.0,
    DiscountType.fixed => value,
    DiscountType.percent => subtotal * (value / 100),
  };
  return raw.clamp(0, subtotal);
}

/// A completed sale/transaction made up of one or more [SaleLineItem]s,
/// with an optional discount applied at checkout.
class Sale {
  final String id;
  final DateTime createdAt;
  final List<SaleLineItem> items;

  /// How the discount was entered (none/fixed amount/percentage).
  final DiscountType discountType;

  /// The raw value entered by the cashier (a peso amount if [discountType]
  /// is [DiscountType.fixed], or a 0-100 percentage if [DiscountType.percent]).
  final double discountValue;

  /// The actual peso amount deducted from the subtotal, already clamped so
  /// it never exceeds the subtotal.
  final double discountAmount;

  const Sale({
    required this.id,
    required this.createdAt,
    required this.items,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.discountAmount = 0,
  });

  double get subtotal => items.fold(0, (sum, item) => sum + item.subtotal);

  double get total => subtotal - discountAmount;

  bool get hasDiscount => discountType != DiscountType.none && discountAmount > 0;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'discountType': discountType.dbValue,
      'discountValue': discountValue,
      'discountAmount': discountAmount,
    };
  }

  factory Sale.fromMap(Map<String, Object?> map, List<SaleLineItem> items) {
    return Sale(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      items: items,
      discountType: DiscountType.fromDb(map['discountType'] as String?),
      discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0,
    );
  }
}
