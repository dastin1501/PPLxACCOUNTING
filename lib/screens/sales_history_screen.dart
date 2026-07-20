import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sale.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/file_share_helper.dart';

/// Read-only log of completed sales, most recent first, with a running
/// total for "today" so a cashier can see end-of-shift revenue at a glance.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, this.onSaleDeleted});

  /// Called after a sale is deleted/voided, so other screens (e.g.
  /// inventory, whose stock quantities get restored) can refresh.
  final VoidCallback? onSaleDeleted;

  @override
  State<SalesHistoryScreen> createState() => SalesHistoryScreenState();
}

class SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _db = DatabaseHelper.instance;
  final _dateFormat = DateFormat('MMM d, y  h:mm a');

  List<Sale> _sales = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() => _loading = true);
    final sales = await _db.getAllSales();
    setState(() {
      _sales = sales;
      _loading = false;
    });
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final file = await ExportService.exportSalesCsv(_sales);
      if (!mounted) return;
      await shareOrRevealFile(context, file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _confirmDelete(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this sale?'),
        content: Text(
          'This will void the sale from ${_dateFormat.format(sale.createdAt)} '
          '(\u20b1${sale.total.toStringAsFixed(2)}) and restore the ${sale.itemCount} '
          'item(s) back into stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.deleteSale(sale.id);
      await refresh();
      widget.onSaleDeleted?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sale deleted and stock restored')),
      );
    }
  }

  double get _todaysTotal {
    final now = DateTime.now();
    return _sales
        .where((s) => s.createdAt.year == now.year && s.createdAt.month == now.month && s.createdAt.day == now.day)
        .fold(0.0, (sum, s) => sum + s.total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales history'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(Icons.today, size: 18, color: Theme.of(context).colorScheme.onTertiaryContainer),
              label: Text(
                'Today: \u20b1${_todaysTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            ),
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            tooltip: 'Export sales history as CSV',
            onPressed: _exporting || _sales.isEmpty ? null : _exportCsv,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        'No sales recorded yet.\nCompleted sales from the Sell tab will show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    itemCount: _sales.length,
                    itemBuilder: (context, index) {
                      final sale = _sales[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          title: Text(
                            _dateFormat.format(sale.createdAt),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            sale.hasDiscount
                                ? '${sale.itemCount} item(s)  •  Discount -\u20b1${sale.discountAmount.toStringAsFixed(2)}'
                                : '${sale.itemCount} item(s)',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '\u20b1${sale.total.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete sale',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _confirmDelete(sale),
                              ),
                            ],
                          ),
                          children: [
                            ...sale.items.map(
                              (line) => ListTile(
                                dense: true,
                                title: Text(line.name),
                                subtitle: Text(
                                  'SKU: ${line.sku}'
                                  '${line.hasVariant ? '  •  ${_variantLabel(line.size, line.color)}' : ''}'
                                  '  •  \u20b1${line.unitPrice.toStringAsFixed(2)} x ${line.quantity}',
                                ),
                                trailing: Text('\u20b1${line.subtotal.toStringAsFixed(2)}'),
                              ),
                            ),
                            if (sale.hasDiscount) ...[
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Subtotal'),
                                    Text('\u20b1${sale.subtotal.toStringAsFixed(2)}'),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      sale.discountType == DiscountType.percent
                                          ? 'Discount (${sale.discountValue.toStringAsFixed(0)}%)'
                                          : 'Discount',
                                    ),
                                    Text(
                                      '-\u20b1${sale.discountAmount.toStringAsFixed(2)}',
                                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// Formats a sold item's size/color snapshot for display, e.g. "M, Grey".
String _variantLabel(String size, String color) {
  return [size, color].where((v) => v.isNotEmpty).join(', ');
}
