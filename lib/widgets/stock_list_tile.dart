import 'dart:io';

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/image_storage_service.dart';
import 'variant_badges.dart';

class StockListTile extends StatelessWidget {
  const StockListTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final Product item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lowStock = item.isLowStock;
    final hasVariants = item.hasVariants;

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
        leading: ImageStorageService.exists(item.imagePath)
            ? CircleAvatar(radius: 26, backgroundImage: FileImage(File(item.imagePath!)))
            : CircleAvatar(
                radius: 26,
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasVariants
                  ? '${item.variants.length} variants  •  ${item.category}'
                  : 'SKU: ${item.variants.first.sku}  •  ${item.category}',
            ),
            if (hasVariants) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.variants
                    .map((v) => VariantBadges(size: v.size, color: v.color, dense: true))
                    .toList(),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.totalQuantity} ${item.unit}',
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
