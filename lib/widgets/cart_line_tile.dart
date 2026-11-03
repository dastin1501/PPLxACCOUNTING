import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/sale.dart';
import 'variant_badges.dart';

/// A single line in the checkout cart, with +/- quantity controls and a
/// discount that applies to this item only.
class CartLineTile extends StatelessWidget {
  const CartLineTile({
    super.key,
    required this.cartLine,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onDiscountType,
    this.discountController,
  });

  final CartLine cartLine;
  final VoidCallback? onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final ValueChanged<DiscountType> onDiscountType;
  final TextEditingController? discountController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variant = cartLine.variant;
    final quantity = cartLine.quantity;
    final discounted = cartLine.discountAmount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cartLine.product.name,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (variant.hasVariantLabel) ...[
                      const SizedBox(height: 3),
                      VariantBadges(size: variant.size, color: variant.color, dense: true),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      '\u20b1${cartLine.unitPrice.toStringAsFixed(2)} x $quantity',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (discounted)
                      Text(
                        'Discount -\u20b1${cartLine.discountAmount.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: onDecrement,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$quantity',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: onIncrement,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  '\u20b1${cartLine.net.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: discountController == null ? 1 : 3,
                child: SegmentedButton<DiscountType>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: DiscountType.none, label: Text('None')),
                    ButtonSegment(value: DiscountType.fixed, label: Text('\u20b1')),
                    ButtonSegment(value: DiscountType.percent, label: Text('%')),
                  ],
                  selected: {cartLine.discountType},
                  onSelectionChanged: (selected) => onDiscountType(selected.first),
                ),
              ),
              if (discountController != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: discountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      labelText: cartLine.discountType == DiscountType.percent ? 'Percent' : 'Amount',
                      prefixText: cartLine.discountType == DiscountType.fixed ? '\u20b1 ' : null,
                      suffixText: cartLine.discountType == DiscountType.percent ? '%' : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
