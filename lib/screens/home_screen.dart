import 'package:flutter/material.dart';

import '../models/stock_item.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/file_share_helper.dart';
import '../widgets/stock_form.dart';
import '../widgets/stock_list_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseHelper.instance;

  List<StockItem> _stocks = [];
  bool _loading = true;
  String _query = '';

  // Null selected item + formOpen=false -> no form shown.
  // Null selected item + formOpen=true -> "add new" form shown.
  // Non-null selected item -> "edit" form shown.
  StockItem? _selected;
  bool _formOpen = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadStocks();
  }

  /// Reloads stock data from the database. Called externally (e.g. by the
  /// navigation shell) whenever another screen may have changed quantities,
  /// such as after completing a sale.
  Future<void> refresh() => _loadStocks();

  Future<void> _loadStocks() async {
    setState(() => _loading = true);
    final stocks = await _db.getAllStocks();
    setState(() {
      _stocks = stocks;
      _loading = false;
    });
  }

  List<StockItem> get _filteredStocks {
    if (_query.trim().isEmpty) return _stocks;
    final q = _query.trim().toLowerCase();
    return _stocks.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.sku.toLowerCase().contains(q) ||
          s.category.toLowerCase().contains(q);
    }).toList();
  }

  void _openAddForm() {
    setState(() {
      _selected = null;
      _formOpen = true;
    });
  }

  void _openEditForm(StockItem item) {
    setState(() {
      _selected = item;
      _formOpen = true;
    });
  }

  void _closeForm() {
    setState(() {
      _selected = null;
      _formOpen = false;
    });
  }

  Future<void> _saveStock(StockItem item) async {
    final isNew = !_stocks.any((s) => s.id == item.id);
    if (isNew) {
      await _db.insertStock(item);
    } else {
      await _db.updateStock(item);
    }
    await _loadStocks();
    if (!mounted) return;
    setState(() {
      _selected = item;
      _formOpen = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isNew ? 'Added "${item.name}"' : 'Updated "${item.name}"')),
    );
  }

  Future<void> _confirmDelete(StockItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete stock item?'),
        content: Text('This will permanently remove "${item.name}" from your inventory.'),
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
      await _db.deleteStock(item.id);
      if (_selected?.id == item.id) {
        _closeForm();
      }
      await _loadStocks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${item.name}"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCount = _stocks.where((s) => s.isLowStock).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Inventory'),
        actions: [
          if (lowStockCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                label: Text('$lowStockCount low stock'),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
              ),
            ),
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            tooltip: 'Export stock list as CSV',
            onPressed: _exporting || _stocks.isEmpty ? null : _exportCsv,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final listPane = _buildListPane(isWide: isWide);

          if (!isWide) {
            // Narrow (phone / portrait tablet): show form as a full page when open.
            return _formOpen
                ? StockForm(
                    initial: _selected,
                    onSubmit: _saveStock,
                    onCancel: _closeForm,
                    skuValidator: _validateSku,
                  )
                : listPane;
          }

          // Wide (tablet landscape): master-detail, two panes side by side.
          return Row(
            children: [
              SizedBox(width: constraints.maxWidth * 0.42, child: listPane),
              const VerticalDivider(width: 1),
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: _formOpen
                      ? StockForm(
                          initial: _selected,
                          onSubmit: _saveStock,
                          onCancel: _closeForm,
                          skuValidator: _validateSku,
                        )
                      : _buildEmptyDetail(),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddForm,
        icon: const Icon(Icons.add),
        label: const Text('Add stock'),
      ),
    );
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final file = await ExportService.exportStocksCsv(_stocks);
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

  String? _validateSku(String sku) {
    final excludingId = _selected?.id;
    final duplicate = _stocks.any((s) => s.sku.toLowerCase() == sku.toLowerCase() && s.id != excludingId);
    return duplicate ? 'This SKU is already used by another item' : null;
  }

  Widget _buildEmptyDetail() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Select an item to edit,\nor tap "Add stock" to create one.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildListPane({required bool isWide}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search by name, SKU, or category',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filteredStocks.isEmpty
                  ? _buildEmptyList()
                  : RefreshIndicator(
                      onRefresh: _loadStocks,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: _filteredStocks.length,
                        itemBuilder: (context, index) {
                          final item = _filteredStocks[index];
                          return StockListTile(
                            item: item,
                            selected: isWide && _selected?.id == item.id,
                            onTap: () => _openEditForm(item),
                            onDelete: () => _confirmDelete(item),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyList() {
    final hasStocks = _stocks.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasStocks ? Icons.search_off : Icons.inventory_2_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            hasStocks ? 'No items match your search' : 'No stock items yet.\nTap "Add stock" to get started.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
