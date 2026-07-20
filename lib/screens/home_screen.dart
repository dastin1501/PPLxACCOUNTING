import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/file_share_helper.dart';
import '../services/image_storage_service.dart';
import '../widgets/stock_form.dart';
import '../widgets/stock_list_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseHelper.instance;

  List<Product> _products = [];
  bool _loading = true;
  String _query = '';

  // Null selected item + formOpen=false -> no form shown.
  // Null selected item + formOpen=true -> "add new" form shown.
  // Non-null selected item -> "edit" form shown.
  Product? _selected;
  bool _formOpen = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  /// Reloads product data from the database. Called externally (e.g. by the
  /// navigation shell) whenever another screen may have changed quantities,
  /// such as after completing a sale.
  Future<void> refresh() => _loadProducts();

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final products = await _db.getAllProducts();
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  List<Product> get _filteredProducts {
    if (_query.trim().isEmpty) return _products;
    final q = _query.trim().toLowerCase();
    return _products.where((p) {
      if (p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q)) return true;
      return p.variants.any(
        (v) => v.sku.toLowerCase().contains(q) || v.size.toLowerCase().contains(q) || v.color.toLowerCase().contains(q),
      );
    }).toList();
  }

  void _openAddForm() {
    setState(() {
      _selected = null;
      _formOpen = true;
    });
  }

  void _openEditForm(Product item) {
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

  Future<void> _saveProduct(Product product) async {
    final isNew = !_products.any((p) => p.id == product.id);
    await _db.saveProduct(product);
    await _loadProducts();
    if (!mounted) return;
    setState(() {
      _selected = product;
      _formOpen = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isNew ? 'Added "${product.name}"' : 'Updated "${product.name}"')),
    );
  }

  Future<void> _confirmDelete(Product item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          'This will permanently remove "${item.name}"'
          '${item.hasVariants ? ' and all ${item.variants.length} of its variants' : ''} from your inventory.',
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
      await _db.deleteProduct(item.id);
      await ImageStorageService.deleteImage(item.imagePath);
      if (_selected?.id == item.id) {
        _closeForm();
      }
      await _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${item.name}"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCount = _products.where((p) => p.isLowStock).length;

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
            onPressed: _exporting || _products.isEmpty ? null : _exportCsv,
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
                    key: ValueKey(_selected?.id ?? 'new-product'),
                    initial: _selected,
                    onSubmit: _saveProduct,
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
                          key: ValueKey(_selected?.id ?? 'new-product'),
                          initial: _selected,
                          onSubmit: _saveProduct,
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
        label: const Text('Add product'),
      ),
    );
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final file = await ExportService.exportStocksCsv(_products);
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

  /// Returns an error string if [sku] is already used by another variant
  /// (other than [excludingVariantId]) across any product, otherwise null.
  String? _validateSku(String sku, String excludingVariantId) {
    final duplicate = _products.any(
      (p) => p.variants.any((v) => v.id != excludingVariantId && v.sku.toLowerCase() == sku.toLowerCase()),
    );
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
            'Select an item to edit,\nor tap "Add product" to create one.',
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
              hintText: 'Search by name, SKU, category, size, or color',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filteredProducts.isEmpty
                  ? _buildEmptyList()
                  : RefreshIndicator(
                      onRefresh: _loadProducts,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final item = _filteredProducts[index];
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
    final hasProducts = _products.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasProducts ? Icons.search_off : Icons.inventory_2_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            hasProducts ? 'No items match your search' : 'No products yet.\nTap "Add product" to get started.',
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
