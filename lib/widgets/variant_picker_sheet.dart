import 'dart:io';

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/image_storage_service.dart';

/// Opens the "choose a variant, then how many" bottom sheet for [product],
/// used by the Sell screen whenever a product has more than one variant.
Future<void> showVariantPickerSheet({
  required BuildContext context,
  required Product product,
  required int Function(ProductVariant variant) cartQuantityForVariant,
  required void Function(ProductVariant variant, int quantity) onAddToCart,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _VariantPickerSheet(
      product: product,
      cartQuantityForVariant: cartQuantityForVariant,
      onAddToCart: onAddToCart,
    ),
  );
}

class _VariantPickerSheet extends StatefulWidget {
  const _VariantPickerSheet({
    required this.product,
    required this.cartQuantityForVariant,
    required this.onAddToCart,
  });

  final Product product;
  final int Function(ProductVariant variant) cartQuantityForVariant;
  final void Function(ProductVariant variant, int quantity) onAddToCart;

  @override
  State<_VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends State<_VariantPickerSheet> {
  late ProductVariant _selected;
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    final variants = widget.product.variants;
    _selected = variants.firstWhere((v) => _remaining(v) > 0, orElse: () => variants.first);
    _qty = _remaining(_selected) > 0 ? 1 : 0;
  }

  int _remaining(ProductVariant v) => v.quantity - widget.cartQuantityForVariant(v);

  void _selectVariant(ProductVariant v) {
    setState(() {
      _selected = v;
      _qty = _remaining(v) > 0 ? 1 : 0;
    });
  }

  void _changeQty(int delta) {
    final remaining = _remaining(_selected);
    setState(() => _qty = (_qty + delta).clamp(0, remaining));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    final remaining = _remaining(_selected);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: ImageStorageService.exists(product.imagePath)
                        ? Image.file(File(product.imagePath!), fit: BoxFit.cover, gaplessPlayback: true)
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.inventory_2_outlined, color: theme.colorScheme.outline),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '\u20b1${product.price.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Choose a variant', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: product.variants.map((v) {
                final vRemaining = _remaining(v);
                final selected = v.id == _selected.id;
                final label = v.hasVariantLabel ? v.label : 'Standard';
                return ChoiceChip(
                  label: Text(vRemaining <= 0 ? '$label (out of stock)' : '$label \u00b7 $vRemaining left'),
                  selected: selected,
                  onSelected: vRemaining <= 0 ? null : (_) => _selectVariant(v),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Quantity', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _qty > 0 ? () => _changeQty(-1) : null,
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '$_qty',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _qty < remaining ? () => _changeQty(1) : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _qty > 0
                  ? () {
                      widget.onAddToCart(_selected, _qty);
                      Navigator.pop(context);
                    }
                  : null,
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(remaining <= 0 ? 'Out of stock' : 'Add to cart'),
            ),
          ],
        ),
      ),
    );
  }
}
