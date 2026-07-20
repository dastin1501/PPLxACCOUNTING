import 'package:flutter/material.dart';

import '../models/stock_item.dart';

/// A tappable product card used in the POS "Sell" screen to add an item
/// to the cart. Shows how many units are already in the cart (if any) and
/// disables itself once stock is exhausted.
class ProductPickerTile extends StatelessWidget {
  const ProductPickerTile({
    super.key,
    required this.item,
    required this.cartQuantity,
    required this.onTap,
  });

  final StockItem item;
  final int cartQuantity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = item.quantity - cartQuantity;
    final outOfStock = remaining <= 0;
    final inCart = cartQuantity > 0;

    return Material(
      color: outOfStock ? theme.colorScheme.surfaceContainerLow : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: outOfStock ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: inCart ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: inCart ? 2 : 1,
            ),
          ),
          child: Opacity(
            opacity: outOfStock ? 0.55 : 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (inCart)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$cartQuantity',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.category,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '\u20b1${item.price.toStringAsFixed(2)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Text(
                        outOfStock ? 'Out of stock' : '$remaining ${item.unit} left',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: outOfStock ? theme.colorScheme.error : theme.colorScheme.outline,
                          fontWeight: outOfStock ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
