import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/adjustment.dart';
import '../models/sale.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/file_share_helper.dart';
import '../widgets/sheet_sync_button.dart';

/// Returns, size exchanges, and the refunds that go with them.
/// Kept off the Sales tab so accounting can total them on their own.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => ReturnsScreenState();
}

class _ReturnRecord {
  const _ReturnRecord({required this.adjustment, required this.sale});

  final StockAdjustment adjustment;
  final Sale? sale;
}

class ReturnsScreenState extends State<ReturnsScreen> {
  final _db = DatabaseHelper.instance;
  final _dateFormat = DateFormat('MMM d, y  h:mm a');

  List<_ReturnRecord> _records = [];
  bool _loading = true;
  bool _exporting = false;
  DateTime? _selectedDay;
  String _query = '';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() => _loading = true);
    final sales = await _db.getAllSales();
    final adjustments = await _db.getAdjustmentsGroupedBySale();
    final salesById = {for (final sale in sales) sale.id: sale};
    final records = <_ReturnRecord>[
      for (final entry in adjustments.entries)
        for (final adjustment in entry.value)
          _ReturnRecord(adjustment: adjustment, sale: salesById[entry.key]),
    ]..sort((a, b) => b.adjustment.createdAt.compareTo(a.adjustment.createdAt));
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<_ReturnRecord> get _visible {
    final day = _selectedDay;
    final byDay = day == null ? _records : _records.where((r) => _sameDay(r.adjustment.createdAt, day)).toList();
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return byDay;
    return byDay.where((record) {
      final receipt = record.sale?.receiptNumber.toLowerCase() ?? '';
      if (receipt.contains(query)) return true;
      final type = [
        record.adjustment.isExchange ? 'exchange' : 'return',
        if (record.adjustment.refundAmount > 0) 'refund',
      ].join(' ');
      if (type.contains(query)) return true;
      return record.adjustment.lines.any(
        (line) => line.name.toLowerCase().contains(query) || line.sku.toLowerCase().contains(query),
      );
    }).toList();
  }

  double get _refundTotal => _visible.fold<double>(0, (sum, record) => sum + record.adjustment.refundAmount);

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

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final file = await ExportService.exportReturnsCsv([
        for (final record in _visible) (adjustment: record.adjustment, sale: record.sale),
      ]);
      if (!mounted) return;
      await shareOrRevealFile(context, file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Returns'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: Icon(Icons.undo, size: 18, color: Theme.of(context).colorScheme.onTertiaryContainer),
              label: Text(
                '$_periodLabel: \u20b1${_refundTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            ),
          ),
          const SheetSyncButton(),
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            tooltip: 'Export returns as CSV',
            onPressed: _exporting || visible.isEmpty ? null : _exportCsv,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildDateFilter(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Find a receipt, product, or SKU',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? _empty(
                        Icons.undo,
                        'No returns or exchanges yet.\nUse Return or exchange on a sale to record one here.',
                      )
                    : visible.isEmpty
                        ? _empty(
                            Icons.search_off,
                            _query.trim().isNotEmpty
                                ? 'No returns match "${_query.trim()}"'
                                : 'No returns on ${DateFormat('MMM d, y').format(_selectedDay!)}.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            itemCount: visible.length,
                            itemBuilder: (context, index) => _buildCard(visible[index]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(_ReturnRecord record) {
    final adjustment = record.adjustment;
    final receipt = record.sale?.receiptNumber;
    final refund = adjustment.refundAmount;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        leading: Icon(adjustment.isExchange ? Icons.swap_horiz : Icons.undo),
        title: Text(
          adjustment.isExchange ? 'Size exchange' : 'Return',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (receipt != null && receipt.isNotEmpty) receipt,
            _dateFormat.format(adjustment.createdAt),
          ].join('   '),
        ),
        trailing: Text(
          refund > 0 ? '-\u20b1${refund.toStringAsFixed(2)}' : '\u20b10.00',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: refund > 0 ? Theme.of(context).colorScheme.error : null,
              ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(adjustment.summary),
            ),
          ),
        ],
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
