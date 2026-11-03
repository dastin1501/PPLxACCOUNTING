import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/sale.dart';
import '../services/database_helper.dart';
import '../widgets/cart_line_tile.dart';
import '../widgets/product_picker_tile.dart';
import '../widgets/sheet_sync_button.dart';
import '../widgets/variant_picker_sheet.dart';

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

  List<Product> _products = [];
  bool _loading = true;
  String _query = '';

  // variantId -> cart line (product + variant + quantity).
  final Map<String, CartLine> _cart = {};
  bool _checkingOut = false;

  DiscountType _discountType = DiscountType.none;
  final _discountCtrl = TextEditingController();
  final Map<String, TextEditingController> _lineDiscountCtrls = {};
  PaymentMethod _paymentMethod = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _discountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    for (final controller in _lineDiscountCtrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _lineDiscountCtrl(String variantId) {
    return _lineDiscountCtrls.putIfAbsent(variantId, () {
      final controller = TextEditingController();
      controller.addListener(() => _applyLineDiscountValue(variantId));
      return controller;
    });
  }

  void _applyLineDiscountValue(String variantId) {
    final line = _cart[variantId];
    final controller = _lineDiscountCtrls[variantId];
    if (line == null || controller == null || !mounted) return;
    final value = double.tryParse(controller.text.trim()) ?? 0;
    if (line.discountValue == value) return;
    setState(() => _cart[variantId] = line.copyWith(discountValue: value));
  }

  void _clearLineDiscount(String variantId) {
    final controller = _lineDiscountCtrls.remove(variantId);
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  /// Reloads product data from the database. Called externally (e.g. by the
  /// navigation shell) whenever the Inventory tab may have changed items,
  /// so newly added/edited products show up here without restarting the app.
  Future<void> refresh() => _loadProducts();

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final products = await _db.getAllProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _loading = false;

      final updated = <String, CartLine>{};
      for (final entry in _cart.entries) {
        final product = _products.where((p) => p.id == entry.value.product.id).firstOrNull;
        if (product == null) continue;
        final variant = product.variants.where((v) => v.id == entry.key).firstOrNull;
        if (variant == null) continue;
        final qty = entry.value.quantity.clamp(0, variant.quantity);
        if (qty <= 0) continue;
        updated[entry.key] = entry.value.copyWith(product: product, variant: variant, quantity: qty);
      }
      _cart
        ..clear()
        ..addAll(updated);
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

  double get _cartSubtotal => _cart.values.fold(0.0, (sum, line) => sum + line.subtotal);

  double get _itemDiscountAmount => _cart.values.fold(0.0, (sum, line) => sum + line.discountAmount);

  double get _discountValue => double.tryParse(_discountCtrl.text.trim()) ?? 0;

  double get _discountAmount {
    final remaining = _cartSubtotal - _itemDiscountAmount;
    return computeDiscountAmount(remaining < 0 ? 0 : remaining, _discountType, _discountValue);
  }

  double get _cartTotal {
    final total = _cartSubtotal - _itemDiscountAmount - _discountAmount;
    return total < 0 ? 0 : total;
  }

  int get _cartItemCount => _cart.values.fold(0, (sum, line) => sum + line.quantity);

  int _cartQuantityForProduct(Product product) =>
      _cart.values.where((l) => l.product.id == product.id).fold(0, (sum, l) => sum + l.quantity);

  void _setDiscountType(DiscountType type) {
    setState(() {
      _discountType = type;
      if (type == DiscountType.none) _discountCtrl.clear();
    });
  }

  void _addToCart(Product product, ProductVariant variant, int qtyToAdd) {
    final existing = _cart[variant.id];
    final current = existing?.quantity ?? 0;
    final newQty = current + qtyToAdd;
    if (newQty > variant.quantity) {
      final label = product.name + (variant.hasVariantLabel ? ' (${variant.label})' : '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only ${variant.quantity} ${product.unit} of "$label" available')),
      );
      return;
    }
    setState(() {
      _cart[variant.id] = CartLine(
        product: product,
        variant: variant,
        quantity: newQty,
        discountType: existing?.discountType ?? DiscountType.none,
        discountValue: existing?.discountValue ?? 0,
      );
    });
  }

  void _setLineDiscountType(CartLine line, DiscountType type) {
    setState(() {
      if (type == DiscountType.none) {
        _clearLineDiscount(line.variant.id);
        _cart[line.variant.id] = line.copyWith(discountType: type, discountValue: 0);
      } else {
        _lineDiscountCtrl(line.variant.id);
        _cart[line.variant.id] = line.copyWith(discountType: type);
      }
    });
  }

  void _onProductTap(Product product) {
    if (!product.hasVariants) {
      _addToCart(product, product.variants.first, 1);
      return;
    }
    showVariantPickerSheet(
      context: context,
      product: product,
      cartQuantityForVariant: (v) => _cart[v.id]?.quantity ?? 0,
      onAddToCart: (variant, qty) => _addToCart(product, variant, qty),
    );
  }

  void _increment(CartLine line) => _addToCart(line.product, line.variant, 1);

  void _decrement(CartLine line) {
    if (line.quantity <= 1) {
      _removeLine(line);
    } else {
      setState(() => _cart[line.variant.id] = line.copyWith(quantity: line.quantity - 1));
    }
  }

  void _removeLine(CartLine line) {
    setState(() {
      _cart.remove(line.variant.id);
      _clearLineDiscount(line.variant.id);
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      for (final variantId in _lineDiscountCtrls.keys.toList()) {
        _clearLineDiscount(variantId);
      }
      _discountType = DiscountType.none;
      _discountCtrl.clear();
      _paymentMethod = PaymentMethod.cash;
    });
  }

  void _setPaymentMethod(PaymentMethod method) {
    setState(() => _paymentMethod = method);
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _checkingOut) return;
    setState(() => _checkingOut = true);
    try {
      final sale = await _db.recordSale(
        _cart.values.toList(),
        discountType: _discountType,
        discountValue: _discountValue,
        paymentMethod: _paymentMethod,
      );
      _cart.clear();
      for (final variantId in _lineDiscountCtrls.keys.toList()) {
        _clearLineDiscount(variantId);
      }
      _discountType = DiscountType.none;
      _discountCtrl.clear();
      _paymentMethod = PaymentMethod.cash;
      await _loadProducts();
      widget.onSaleCompleted();
      if (!mounted) return;
      await _showReceiptDialog(sale);
    } on InsufficientStockException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      await _loadProducts();
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _showReceiptDialog(Sale sale) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(sale.receiptNumber.isEmpty ? 'Sale completed' : sale.receiptNumber),
            ),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${line.name} x${line.quantity}'),
                            if (line.hasVariant)
                              Text(
                                _saleLineVariantLabel(line.size, line.color),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
                              ),
                            if (line.hasDiscount)
                              Text(
                                'Discount -\u20b1${line.discountAmount.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Theme.of(context).colorScheme.error),
                              ),
                          ],
                        ),
                      ),
                      Text('\u20b1${line.net.toStringAsFixed(2)}'),
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
              if (sale.hasItemDiscount)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Item discount'),
                      Text('-\u20b1${sale.itemDiscountAmount.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              if (sale.hasDiscount)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        sale.discountType == DiscountType.percent
                            ? 'Whole sale (${sale.discountValue.toStringAsFixed(0)}%)'
                            : 'Whole sale',
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
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Payment method'),
                    Text(
                      sale.paymentMethod.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
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
      appBar: AppBar(
        title: const Text('Sell'),
        actions: [
          SheetSyncButton(onSynced: () {
            refresh();
          }),
          const SizedBox(width: 8),
        ],
      ),
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
            decoration: const InputDecoration(
              hintText: 'Search products to sell',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _products.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _products.isEmpty
                                ? 'No products yet.\nAdd items in the Inventory tab first.'
                                : 'No items match your search',
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
                        mainAxisExtent: 316,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return ProductPickerTile(
                          item: product,
                          cartQuantity: _cartQuantityForProduct(product),
                          onTap: () => _onProductTap(product),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildCartPane() {
    final cartLines = _cart.values.toList();
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
              if (cartLines.isNotEmpty) TextButton(onPressed: _clearCart, child: const Text('Clear')),
            ],
          ),
        ),
        Expanded(
          child: cartLines.isEmpty
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
                  children: [
                    for (final line in cartLines)
                      CartLineTile(
                        cartLine: line,
                        onIncrement: line.quantity < line.variant.quantity ? () => _increment(line) : null,
                        onDecrement: () => _decrement(line),
                        onRemove: () => _removeLine(line),
                        onDiscountType: (type) => _setLineDiscountType(line, type),
                        discountController:
                            line.discountType == DiscountType.none ? null : _lineDiscountCtrl(line.variant.id),
                      ),
                  ],
                ),
        ),
        _buildCheckoutBar(),
      ],
    );
  }

  Widget _buildCheckoutBar() {
    final hasItemDiscount = _itemDiscountAmount > 0;
    final hasSaleDiscount = _discountType != DiscountType.none && _discountAmount > 0;
    final hasDiscount = hasItemDiscount || hasSaleDiscount;

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
              Text('Payment', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<PaymentMethod>(
                  segments: const [
                    ButtonSegment(
                      value: PaymentMethod.cash,
                      label: Text('Cash'),
                      icon: Icon(Icons.payments_outlined),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.card,
                      label: Text('Card'),
                      icon: Icon(Icons.credit_card_outlined),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.online,
                      label: Text('Online'),
                      icon: Icon(Icons.qr_code_scanner_outlined),
                    ),
                  ],
                  selected: {_paymentMethod},
                  onSelectionChanged: (s) => _setPaymentMethod(s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Whole sale', style: Theme.of(context).textTheme.bodyMedium),
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
          if (hasItemDiscount)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Item discount', style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    '-\u20b1${_itemDiscountAmount.toStringAsFixed(2)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ),
            ),
          if (hasSaleDiscount)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Whole sale', style: Theme.of(context).textTheme.bodyMedium),
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
                onPressed: _showCartSheet,
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
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: _buildCartPane(),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Formats a sold item's size/color snapshot for display, e.g. "M, Grey".
String _saleLineVariantLabel(String size, String color) {
  return [size, color].where((v) => v.isNotEmpty).join(', ');
}
