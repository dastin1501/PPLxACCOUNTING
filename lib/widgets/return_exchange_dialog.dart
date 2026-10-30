import 'package:flutter/material.dart';

import '../models/adjustment.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../services/database_helper.dart';

/// Opens the return / size-exchange dialog for [sale].
/// Returns true when a return or exchange was saved.
Future<bool> showReturnExchangeDialog({
  required BuildContext context,
  required Sale sale,
  required List<StockAdjustment> adjustments,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => ReturnExchangeDialog(sale: sale, adjustments: adjustments),
  );
  return saved ?? false;
}

class ReturnExchangeDialog extends StatefulWidget {
  const ReturnExchangeDialog({
    super.key,
    required this.sale,
    required this.adjustments,
  });

  final Sale sale;
  final List<StockAdjustment> adjustments;

  @override
  State<ReturnExchangeDialog> createState() => _ReturnExchangeDialogState();
}

class _LineDraft {
  int quantity = 0;
  String? exchangeVariantId;
}

class _ReturnExchangeDialogState extends State<ReturnExchangeDialog> {
  final _db = DatabaseHelper.instance;
  final _drafts = <String, _LineDraft>{};

  Map<String, Product?> _productsByVariant = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final line in widget.sale.items) {
      _drafts[line.id] = _LineDraft();
    }
    _loadProducts();
  }

  int _alreadyReturned(String saleItemId) {
    var total = 0;
    for (final adjustment in widget.adjustments) {
      for (final line in adjustment.lines) {
        if (line.saleItemId == saleItemId && line.direction == AdjustmentDirection.inbound) {
          total += line.quantity;
        }
      }
    }
    return total;
  }

  Future<void> _loadProducts() async {
    final loaded = <String, Product?>{};
    for (final line in widget.sale.items) {
      if (loaded.containsKey(line.stockId)) continue;
      loaded[line.stockId] = await _db.getProductByVariantId(line.stockId);
    }
    if (!mounted) return;
    setState(() {
      _productsByVariant = loaded;
      _loading = false;
    });
  }

  bool get _hasSelection => _drafts.values.any((d) => d.quantity > 0);

  String? get _stockProblem {
    final demand = <String, int>{};
    for (final line in widget.sale.items) {
      final draft = _drafts[line.id]!;
      final variantId = draft.exchangeVariantId;
      if (draft.quantity <= 0 || variantId == null) continue;
      demand[variantId] = (demand[variantId] ?? 0) + draft.quantity;
    }
    for (final entry in demand.entries) {
      final variant = _variantById(entry.key);
      if (variant == null) return 'That size is no longer in inventory';
      if (variant.quantity < entry.value) {
        final label = variant.label.isEmpty ? variant.sku : variant.label;
        return 'Only ${variant.quantity} of $label in stock';
      }
    }
    return null;
  }

  ProductVariant? _variantById(String id) {
    for (final product in _productsByVariant.values) {
      if (product == null) continue;
      for (final variant in product.variants) {
        if (variant.id == id) return variant;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _stockProblem;
    if (problem != null || !_hasSelection || _saving) {
      setState(() => _error = problem);
      return;
    }

    final requests = <ReturnLineRequest>[];
    for (final line in widget.sale.items) {
      final draft = _drafts[line.id]!;
      if (draft.quantity <= 0) continue;
      final product = _productsByVariant[line.stockId];
      final exchange = draft.exchangeVariantId == null ? null : _variantById(draft.exchangeVariantId!);
      requests.add(ReturnLineRequest(
        saleLine: line,
        quantity: draft.quantity,
        exchangeTo: exchange,
        exchangeUnitPrice: product?.price ?? line.unitPrice,
        exchangeName: product?.name ?? line.name,
      ));
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _db.recordReturnOrExchange(saleId: widget.sale.id, lines: requests);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AdjustmentException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on InsufficientStockException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _stockProblem;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Return or exchange', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'The original sale stays in history. Stock updates when you save.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        itemCount: widget.sale.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _buildLine(theme, widget.sale.items[index]),
                      ),
              ),
              if (_error != null || problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error ?? problem!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: !_hasSelection || problem != null || _saving || _loading ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.swap_horiz),
                    label: Text(_saving ? 'Saving...' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLine(ThemeData theme, SaleLineItem line) {
    final returned = _alreadyReturned(line.id);
    final remaining = line.quantity - returned;
    final draft = _drafts[line.id]!;
    final product = _productsByVariant[line.stockId];
    final missing = product == null;
    final others = product?.variants.where((v) => v.id != line.stockId).toList() ?? const <ProductVariant>[];
    final variantLabel = [line.size, line.color].where((v) => v.isNotEmpty).join(', ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            [
              if (variantLabel.isNotEmpty) variantLabel,
              'Sold ${line.quantity}',
              if (returned > 0) '$returned already back',
              if (missing) 'No longer in inventory',
            ].join('  •  '),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: draft.quantity <= 0
                    ? null
                    : () => setState(() {
                          draft.quantity -= 1;
                          if (draft.quantity == 0) draft.exchangeVariantId = null;
                          _error = null;
                        }),
                icon: const Icon(Icons.remove),
              ),
              Text('${draft.quantity}', style: theme.textTheme.titleMedium),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: missing || draft.quantity >= remaining
                    ? null
                    : () => setState(() {
                          draft.quantity += 1;
                          _error = null;
                        }),
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remaining <= 0
                      ? 'Nothing left to return'
                      : draft.quantity == 0
                          ? 'How many are they bringing back?'
                          : draft.exchangeVariantId == null
                              ? 'Back to stock'
                              : 'Exchange for another size',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ),
          if (draft.quantity > 0 && others.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Return to stock'),
                  selected: draft.exchangeVariantId == null,
                  onSelected: (_) => setState(() {
                    draft.exchangeVariantId = null;
                    _error = null;
                  }),
                ),
                for (final variant in others)
                  FilterChip(
                    label: Text(
                      variant.quantity <= 0
                          ? '${variant.label.isEmpty ? variant.sku : variant.label} · out'
                          : '${variant.label.isEmpty ? variant.sku : variant.label} · ${variant.quantity}',
                    ),
                    selected: draft.exchangeVariantId == variant.id,
                    onSelected: variant.quantity <= 0
                        ? null
                        : (_) => setState(() {
                              draft.exchangeVariantId = variant.id;
                              _error = null;
                            }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
