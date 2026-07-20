import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../models/stock_item.dart';
import '../services/database_helper.dart';
import '../widgets/cart_line_tile.dart';
import '../widgets/product_picker_tile.dart';

/// The point-of-sale "checkout" screen: pick products to build a cart, then
/// complete the sale, which decrements stock quantities accordingly.
class SellScreen extends StatefulWidget {
  const SellScreen({super.key, required this.onSaleCompleted});

  /// Called after a sale is successfully recorded, so other screens
  /// (e.g. inventory, sales history) can refresh their data.
  final VoidCallback onSaleCompleted;

  @override
  State<SellScreen> createState() => SellScreenState();
}

class SellScreenState extends State<SellScreen> {
  final _db = DatabaseHelper.instance;

  List<StockItem> _stocks = [];
  bool _loading = true;
  String _query = '';

  // stockId -> quantity in cart.
  final Map<String, int> _cart = {};
  bool _checkingOut = false;

  DiscountType _discountType = DiscountType.none;
  final _discountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStocks();
    _discountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    super.dispose();
  }

  /// Reloads stock data from the database. Called externally (e.g. by the
  /// navigation shell) whenever the Inventory tab may have changed items,
  /// so newly added/edited products show up here without restarting the app.
  Future<void> refresh() => _loadStocks();

  Future<void> _loadStocks() async {
    setState(() => _loading = true);
    final stocks = await _db.getAllStocks();
    setState(() {
      _stocks = stocks;
      _loading = false;
      // Drop any cart lines whose item no longer exists.
      _cart.removeWhere((id, _) => !_stocks.any((s) => s.id == id));
    });
  }

  List<StockItem> get _filteredStocks {
    if (_query.trim().isEmpty) return _stocks;
    final q = _query.trim().toLowerCase();
    return _stocks
        .where((s) => s.name.toLowerCase().contains(q) || s.sku.toLowerCase().contains(q) || s.category.toLowerCase().contains(q))
        .toList();
  }

  Map<StockItem, int> get _cartItems {
    final result = <StockItem, int>{};
    for (final entry in _cart.entries) {
      final item = _stocks.where((s) => s.id == entry.key).firstOrNull;
      if (item != null) result[item] = entry.value;
    }
    return result;
  }

  double get _cartSubtotal {
    var total = 0.0;
    for (final entry in _cartItems.entries) {
      total += entry.key.price * entry.value;
    }
    return total;
  }

  double get _discountValue => double.tryParse(_discountCtrl.text.trim()) ?? 0;

  double get _discountAmount => computeDiscountAmount(_cartSubtotal, _discountType, _discountValue);

  double get _cartTotal => _cartSubtotal - _discountAmount;

  int get _cartItemCount => _cart.values.fold(0, (sum, q) => sum + q);

  void _setDiscountType(DiscountType type) {
    setState(() {
      _discountType = type;
      if (type == DiscountType.none) _discountCtrl.clear();
    });
  }

  void _addToCart(StockItem item) {
    final current = _cart[item.id] ?? 0;
    if (current >= item.quantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only ${item.quantity} ${item.unit} of "${item.name}" available')),
      );
      return;
    }
    setState(() => _cart[item.id] = current + 1);
  }

  void _increment(StockItem item) => _addToCart(item);

  void _decrement(StockItem item) {
    final current = _cart[item.id] ?? 0;
    if (current <= 1) {
      setState(() => _cart.remove(item.id));
    } else {
      setState(() => _cart[item.id] = current - 1);
    }
  }

  void _removeLine(StockItem item) {
    setState(() => _cart.remove(item.id));
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _discountType = DiscountType.none;
      _discountCtrl.clear();
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _checkingOut) return;
    setState(() => _checkingOut = true);
    try {
      final sale = await _db.recordSale(
        _cartItems,
        discountType: _discountType,
        discountValue: _discountValue,
      );
      _cart.clear();
      _discountType = DiscountType.none;
      _discountCtrl.clear();
      await _loadStocks();
      widget.onSaleCompleted();
      if (!mounted) return;
      await _showReceiptDialog(sale);
    } on InsufficientStockException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      await _loadStocks();
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _showReceiptDialog(Sale sale) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Sale completed'),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...sale.items.map(
                (line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text('${line.name} x${line.quantity}')),
                      Text('\u20b1${line.subtotal.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal'),
                  Text('\u20b1${sale.subtotal.toStringAsFixed(2)}'),
                ],
              ),
              if (sale.hasDiscount)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        sale.discountType == DiscountType.percent
                            ? 'Discount (${sale.discountValue.toStringAsFixed(0)}%)'
                            : 'Discount',
                      ),
                      Text('-\u20b1${sale.discountAmount.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '\u20b1${sale.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sell')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final productPane = _buildProductPane();

          if (!isWide) {
            return Column(
              children: [
                Expanded(child: productPane),
                _buildBottomCartBar(),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: productPane),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 400,
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: _buildCartPane(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProductPane() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search products to sell',
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
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _stocks.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _stocks.isEmpty ? 'No stock items yet.\nAdd items in the Inventory tab first.' : 'No items match your search',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.outline),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 240,
                        mainAxisExtent: 172,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: _filteredStocks.length,
                      itemBuilder: (context, index) {
                        final item = _filteredStocks[index];
                        return ProductPickerTile(
                          item: item,
                          cartQuantity: _cart[item.id] ?? 0,
                          onTap: () => _addToCart(item),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildCartPane() {
    final cartItems = _cartItems;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
          child: Row(
            children: [
              Icon(Icons.shopping_cart_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Current sale', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (cartItems.isNotEmpty)
                TextButton(onPressed: _clearCart, child: const Text('Clear')),
            ],
          ),
        ),
        Expanded(
          child: cartItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_shopping_cart_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        'Tap a product to add it here',
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  children: cartItems.entries
                      .map(
                        (e) => CartLineTile(
                          item: e.key,
                          quantity: e.value,
                          onIncrement: e.value < e.key.quantity ? () => _increment(e.key) : null,
                          onDecrement: () => _decrement(e.key),
                          onRemove: () => _removeLine(e.key),
                        ),
                      )
                      .toList(),
                ),
        ),
        _buildCheckoutBar(),
      ],
    );
  }

  Widget _buildCheckoutBar() {
    final hasDiscount = _discountType != DiscountType.none && _discountAmount > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Discount', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<DiscountType>(
                  segments: const [
                    ButtonSegment(value: DiscountType.none, label: Text('None')),
                    ButtonSegment(value: DiscountType.fixed, label: Text('\u20b1')),
                    ButtonSegment(value: DiscountType.percent, label: Text('%')),
                  ],
                  selected: {_discountType},
                  onSelectionChanged: (s) => _setDiscountType(s.first),
                ),
              ),
            ],
          ),
          if (_discountType != DiscountType.none)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _discountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: _discountType == DiscountType.percent ? 'Discount percent' : 'Discount amount',
                  prefixText: _discountType == DiscountType.fixed ? '\u20b1 ' : null,
                  suffixText: _discountType == DiscountType.percent ? '%' : null,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hasDiscount ? 'Subtotal' : 'Total',
                style: hasDiscount ? Theme.of(context).textTheme.bodyMedium : Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '\u20b1${_cartSubtotal.toStringAsFixed(2)}',
                style: hasDiscount
                    ? null
                    : Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (hasDiscount)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Discount', style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    '-\u20b1${_discountAmount.toStringAsFixed(2)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ),
            ),
          if (hasDiscount)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '\u20b1${_cartTotal.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _cart.isEmpty || _checkingOut ? null : _checkout,
            icon: _checkingOut
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.point_of_sale),
            label: Text(_checkingOut ? 'Processing...' : 'Complete sale'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCartBar() {
    if (_cart.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text('$_cartItemCount item(s) • \u20b1${_cartTotal.toStringAsFixed(2)}'),
              ),
              OutlinedButton(
                onPressed: () => _showCartSheet(),
                child: const Text('View cart'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _checkingOut ? null : _checkout,
                child: Text(_checkingOut ? 'Processing...' : 'Checkout'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return FractionallySizedBox(
            heightFactor: 0.75,
            child: _buildCartPane(),
          );
        },
      ),
    ).then((_) => setState(() {}));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
