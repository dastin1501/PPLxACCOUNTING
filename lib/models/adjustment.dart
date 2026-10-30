import 'product.dart';
import 'sale.dart';

/// Whether stock moved back into the shop or out to the customer.
enum AdjustmentDirection {
  inbound,
  outbound;

  String get dbValue => this == AdjustmentDirection.inbound ? 'in' : 'out';

  static AdjustmentDirection fromDb(String? value) {
    return value == 'out' ? AdjustmentDirection.outbound : AdjustmentDirection.inbound;
  }
}

/// One size/color line inside a return or exchange.
class AdjustmentLine {
  final String id;
  final String adjustmentId;

  /// The original sale line this movement belongs to, when there is one.
  final String? saleItemId;
  final String stockId;
  final String name;
  final String sku;
  final String size;
  final String color;
  final int quantity;
  final AdjustmentDirection direction;
  final double unitPrice;

  const AdjustmentLine({
    required this.id,
    required this.adjustmentId,
    required this.saleItemId,
    required this.stockId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.direction,
    required this.unitPrice,
    this.size = '',
    this.color = '',
  });

  double get subtotal => unitPrice * quantity;

  String get variantLabel => [size, color].where((v) => v.isNotEmpty).join(', ');

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'adjustmentId': adjustmentId,
      'saleItemId': saleItemId,
      'stockId': stockId,
      'name': name,
      'sku': sku,
      'size': size,
      'color': color,
      'quantity': quantity,
      'direction': direction.dbValue,
      'unitPrice': unitPrice,
    };
  }

  factory AdjustmentLine.fromMap(Map<String, Object?> map) {
    return AdjustmentLine(
      id: map['id'] as String,
      adjustmentId: map['adjustmentId'] as String,
      saleItemId: map['saleItemId'] as String?,
      stockId: map['stockId'] as String,
      name: map['name'] as String,
      sku: map['sku'] as String,
      size: map['size'] as String? ?? '',
      color: map['color'] as String? ?? '',
      quantity: map['quantity'] as int,
      direction: AdjustmentDirection.fromDb(map['direction'] as String?),
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// A return or size/color exchange recorded against an existing sale.
/// The original sale is kept; this is the later history of what came back.
class StockAdjustment {
  final String id;
  final String saleId;
  final DateTime createdAt;

  /// `return` when items only came back to stock, `exchange` when at least
  /// one of them was swapped for a different size or color.
  final String kind;
  final List<AdjustmentLine> lines;

  const StockAdjustment({
    required this.id,
    required this.saleId,
    required this.createdAt,
    required this.kind,
    required this.lines,
  });

  bool get isExchange => kind == 'exchange';

  /// Peso amount that came back to the customer. A same-price size exchange
  /// is zero; a straight return is the value of the items brought back.
  double get refundAmount {
    final inbound = lines
        .where((l) => l.direction == AdjustmentDirection.inbound)
        .fold<double>(0, (sum, line) => sum + line.subtotal);
    final outbound = lines
        .where((l) => l.direction == AdjustmentDirection.outbound)
        .fold<double>(0, (sum, line) => sum + line.subtotal);
    final net = inbound - outbound;
    return net > 0 ? net : 0;
  }

  String get summary {
    final inbound = lines.where((l) => l.direction == AdjustmentDirection.inbound);
    final outbound = lines.where((l) => l.direction == AdjustmentDirection.outbound).toList();
    final parts = <String>[];
    for (final line in inbound) {
      final from = line.variantLabel.isEmpty ? line.name : '${line.name} (${line.variantLabel})';
      final given = outbound.where((o) => o.saleItemId == line.saleItemId).toList();
      if (given.isEmpty) {
        parts.add('$from x${line.quantity} returned');
      } else {
        final to = given
            .map((o) => '${o.variantLabel.isEmpty ? o.name : o.variantLabel} x${o.quantity}')
            .join(', ');
        parts.add('$from x${line.quantity} → $to');
      }
    }
    return parts.join('\n');
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'saleId': saleId,
      'createdAt': createdAt.toIso8601String(),
      'kind': kind,
    };
  }

  factory StockAdjustment.fromMap(Map<String, Object?> map, List<AdjustmentLine> lines) {
    return StockAdjustment(
      id: map['id'] as String,
      saleId: map['saleId'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      kind: map['kind'] as String? ?? 'return',
      lines: lines,
    );
  }
}

/// What the cashier asked to do with one sold line: bring some of it back,
/// and optionally hand out a different size or color instead.
class ReturnLineRequest {
  const ReturnLineRequest({
    required this.saleLine,
    required this.quantity,
    this.exchangeTo,
    this.exchangeUnitPrice = 0,
    this.exchangeName = '',
  });

  final SaleLineItem saleLine;
  final int quantity;

  /// The size/color handed to the customer. Null means the items only
  /// came back to stock.
  final ProductVariant? exchangeTo;
  final double exchangeUnitPrice;
  final String exchangeName;
}
