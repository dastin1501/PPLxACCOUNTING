import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/adjustment.dart';
import '../models/sale.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/file_share_helper.dart';
import '../widgets/return_exchange_dialog.dart';
import '../widgets/sheet_sync_button.dart';

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
  Map<String, List<StockAdjustment>> _adjustments = {};
  bool _loading = true;
  bool _exporting = false;

  /// Null means every day. Otherwise only sales from this calendar day.
  DateTime? _selectedDay;
  String _saleQuery = '';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() => _loading = true);
    final sales = await _db.getAllSales();
    final adjustments = await _db.getAdjustmentsGroupedBySale();
    setState(() {
      _sales = sales;
      _adjustments = adjustments;
      _loading = false;
    });
  }

  List<StockAdjustment> _adjustmentsFor(Sale sale) => _adjustments[sale.id] ?? const [];

  int _returnedQty(Sale sale, String saleItemId) {
    var total = 0;
    for (final adjustment in _adjustmentsFor(sale)) {
      for (final line in adjustment.lines) {
        if (line.saleItemId == saleItemId && line.direction == AdjustmentDirection.inbound) {
          total += line.quantity;
        }
      }
    }
    return total;
  }

  bool _canReturn(Sale sale) {
    return sale.items.any((line) => _returnedQty(sale, line.id) < line.quantity);
  }

  String _saleSubtitle(Sale sale) {
    final parts = <String>[
      '${sale.itemCount} item(s)',
      sale.paymentMethod.label,
    ];
    if (sale.hasDiscount) {
      parts.add('Discount -\u20b1${sale.discountAmount.toStringAsFixed(2)}');
    }
    return parts.join('  •  ');
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final file = await ExportService.exportSalesCsv(_visibleSales);
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
          _adjustmentsFor(sale).isEmpty
              ? 'This will void the sale from ${_dateFormat.format(sale.createdAt)} '
                  '(\u20b1${sale.total.toStringAsFixed(2)}) and restore the ${sale.itemCount} '
                  'item(s) back into stock.'
              : 'This sale has a return or exchange on record. Deleting it undoes those '
                  'stock changes too, then puts the original items back.',
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
      try {
        await _db.deleteSale(sale.id);
        await refresh();
        widget.onSaleDeleted?.call();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale deleted and stock restored')),
        );
      } on AdjustmentException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _openReturn(Sale sale) async {
    final saved = await showReturnExchangeDialog(
      context: context,
      sale: sale,
      adjustments: _adjustmentsFor(sale),
    );
    if (!saved || !mounted) return;
    await refresh();
    widget.onSaleDeleted?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved on the Returns tab and stock updated')),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<Sale> get _visibleSales {
    final day = _selectedDay;
    final byDay = day == null ? _sales : _sales.where((sale) => _sameDay(sale.createdAt, day)).toList();
    final query = _saleQuery.trim().toLowerCase();
    if (query.isEmpty) return byDay;
    return byDay.where((sale) {
      if (sale.receiptNumber.toLowerCase().contains(query)) return true;
      if (sale.paymentMethod.label.toLowerCase().contains(query)) return true;
      return sale.items.any(
        (line) => line.name.toLowerCase().contains(query) || line.sku.toLowerCase().contains(query),
      );
    }).toList();
  }

  /// Money that came back to the customer for this sale.
  double _refunded(Sale sale) {
    return _adjustmentsFor(sale).fold<double>(0, (sum, adjustment) => sum + adjustment.refundAmount);
  }

  /// What is still a sale after returns. A ₱1,500 sale with a ₱900 refund is ₱600.
  double _netTotal(Sale sale) {
    final net = sale.total - _refunded(sale);
    return net < 0 ? 0 : net;
  }

  double get _periodTotal {
    return _visibleSales.fold<double>(0, (sum, sale) => sum + _netTotal(sale));
  }

  String get _periodLabel {
    final day = _selectedDay;
    if (day == null) return 'All';
    if (_sameDay(day, DateTime.now())) return 'Today';
    return DateFormat('MMM d').format(day);
  }

  bool get _canGoForward {
    final day = _selectedDay;
    if (day == null) return false;
    return !_sameDay(day, DateTime.now());
  }

  void _shiftDay(int delta) {
    final today = DateUtils.dateOnly(DateTime.now());
    final base = _selectedDay ?? today;
    final next = DateUtils.dateOnly(base).add(Duration(days: delta));
    if (next.isAfter(today)) return;
    setState(() => _selectedDay = next);
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _selectedDay = DateUtils.dateOnly(picked));
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
                '$_periodLabel: \u20b1${_periodTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            ),
          ),
          SheetSyncButton(
            onSynced: () {
              refresh();
              widget.onSaleDeleted?.call();
            },
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            tooltip: 'Export sales history as CSV',
            onPressed: _exporting || _visibleSales.isEmpty ? null : _exportCsv,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildDateFilter(),
          _buildSaleSearch(),
          Expanded(
            child: _loading
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
              : _visibleSales.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            _saleQuery.trim().isNotEmpty
                                ? 'No sales match "${_saleQuery.trim()}"'
                                : 'No sales on ${DateFormat('MMM d, y').format(_selectedDay!)}.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.outline),
                          ),
                          if (_selectedDay != null && _saleQuery.trim().isEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(() => _selectedDay = null),
                              child: const Text('Show all dates'),
                            ),
                          ],
                        ],
                      ),
                    )
              : RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    itemCount: _visibleSales.length,
                    itemBuilder: (context, index) {
                      final sale = _visibleSales[index];
                      final canReturn = _canReturn(sale);
                      final refunded = _refunded(sale);
                      final net = _netTotal(sale);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          title: Text(
                            sale.receiptNumber.isEmpty
                                ? _dateFormat.format(sale.createdAt)
                                : '${sale.receiptNumber}   ${_dateFormat.format(sale.createdAt)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(_saleSubtitle(sale)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '\u20b1${net.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (canReturn)
                                IconButton(
                                  icon: const Icon(Icons.swap_horiz),
                                  tooltip: 'Return or exchange',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _openReturn(sale),
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
                              (line) {
                                final returned = _returnedQty(sale, line.id);
                                return ListTile(
                                  dense: true,
                                  title: Text(line.name),
                                  subtitle: Text(
                                    'SKU: ${line.sku}'
                                    '${line.hasVariant ? '  •  ${_variantLabel(line.size, line.color)}' : ''}'
                                    '  •  \u20b1${line.unitPrice.toStringAsFixed(2)} x ${line.quantity}'
                                    '${returned > 0 ? '  •  $returned returned' : ''}',
                                  ),
                                  trailing: Text('\u20b1${line.subtotal.toStringAsFixed(2)}'),
                                );
                              },
                            ),
                            if (sale.hasDiscount || refunded > 0) ...[
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
                              if (sale.hasDiscount)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
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
                              if (refunded > 0)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Returned'),
                                      Text(
                                        '-\u20b1${refunded.toStringAsFixed(2)}',
                                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                                      ),
                                    ],
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      '\u20b1${net.toStringAsFixed(2)}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: canReturn ? () => _openReturn(sale) : null,
                                  icon: const Icon(Icons.swap_horiz),
                                  label: Text(canReturn ? 'Return or exchange' : 'Fully returned'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Find a receipt, product, or SKU',
          prefixIcon: Icon(Icons.search),
          isDense: true,
        ),
        onChanged: (value) => setState(() => _saleQuery = value),
      ),
    );
  }

  Widget _buildDateFilter() {
    final day = _selectedDay;
    final label = day == null
        ? 'All dates'
        : _sameDay(day, DateTime.now())
            ? 'Today, ${DateFormat('MMM d, y').format(day)}'
            : DateFormat('EEEE, MMM d, y').format(day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(label),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: _canGoForward ? () => _shiftDay(1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: day == null ? null : () => setState(() => _selectedDay = null),
            child: const Text('All'),
          ),
          TextButton(
            onPressed: day != null && _sameDay(day, DateTime.now())
                ? null
                : () => setState(() => _selectedDay = DateUtils.dateOnly(DateTime.now())),
            child: const Text('Today'),
          ),
        ],
      ),
    );
  }
}

/// Formats a sold item's size/color snapshot for display, e.g. "M, Grey".
String _variantLabel(String size, String color) {
  return [size, color].where((v) => v.isNotEmpty).join(', ');
}
