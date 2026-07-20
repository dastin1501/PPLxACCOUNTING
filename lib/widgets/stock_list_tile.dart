import 'package:flutter/material.dart';

import '../models/stock_item.dart';

class StockListTile extends StatelessWidget {
  const StockListTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final StockItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lowStock = item.isLowStock;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: selected ? theme.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: lowStock ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer,
          child: Icon(
            lowStock ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
            color: lowStock ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          item.name,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('SKU: ${item.sku}  •  ${item.category}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.quantity} ${item.unit}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: lowStock ? theme.colorScheme.error : null,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '\u20b1${item.price.toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
