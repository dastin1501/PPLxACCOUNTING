import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/stock_item.dart';

/// Form for creating a new [StockItem] or editing an existing one.
///
/// Pass [initial] to edit; leave it null to create a new stock item.
class StockForm extends StatefulWidget {
  const StockForm({
    super.key,
    required this.initial,
    required this.onSubmit,
    required this.onCancel,
    required this.skuValidator,
  });

  final StockItem? initial;
  final void Function(StockItem item) onSubmit;
  final VoidCallback onCancel;

  /// Returns an error string if the SKU is already in use, otherwise null.
  final String? Function(String sku) skuValidator;

  @override
  State<StockForm> createState() => _StockFormState();
}

class _StockFormState extends State<StockForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costPriceCtrl;
  late final TextEditingController _lowStockCtrl;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _skuCtrl = TextEditingController(text: item?.sku ?? '');
    _categoryCtrl = TextEditingController(text: item?.category ?? '');
    _quantityCtrl = TextEditingController(text: item?.quantity.toString() ?? '0');
    _unitCtrl = TextEditingController(text: item?.unit ?? 'pcs');
    _priceCtrl = TextEditingController(text: item?.price.toString() ?? '');
    _costPriceCtrl = TextEditingController(text: item?.costPrice.toString() ?? '');
    _lowStockCtrl = TextEditingController(text: item?.lowStockThreshold.toString() ?? '5');
  }

  @override
  void didUpdateWidget(StockForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial?.id != widget.initial?.id) {
      final item = widget.initial;
      _nameCtrl.text = item?.name ?? '';
      _skuCtrl.text = item?.sku ?? '';
      _categoryCtrl.text = item?.category ?? '';
      _quantityCtrl.text = item?.quantity.toString() ?? '0';
      _unitCtrl.text = item?.unit ?? 'pcs';
      _priceCtrl.text = item?.price.toString() ?? '';
      _costPriceCtrl.text = item?.costPrice.toString() ?? '';
      _lowStockCtrl.text = item?.lowStockThreshold.toString() ?? '5';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _categoryCtrl.dispose();
    _quantityCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    _costPriceCtrl.dispose();
    _lowStockCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final isEditing = widget.initial != null;
    final item = StockItem(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      sku: _skuCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty ? 'Uncategorized' : _categoryCtrl.text.trim(),
      quantity: int.parse(_quantityCtrl.text.trim()),
      unit: _unitCtrl.text.trim().isEmpty ? 'pcs' : _unitCtrl.text.trim(),
      price: double.parse(_priceCtrl.text.trim()),
      costPrice: _costPriceCtrl.text.trim().isEmpty ? 0 : double.parse(_costPriceCtrl.text.trim()),
      lowStockThreshold: int.parse(_lowStockCtrl.text.trim()),
      updatedAt: DateTime.now(),
    );
    widget.onSubmit(item);
    if (!isEditing) {
      _formKey.currentState!.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isEditing ? Icons.edit_outlined : Icons.add_box_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                isEditing ? 'Edit Stock Item' : 'Add New Stock Item',
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Product name'),
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _skuCtrl,
                  decoration: const InputDecoration(labelText: 'SKU / Barcode'),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'SKU is required';
                    final err = widget.skuValidator(v.trim());
                    return err;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Category'),
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _quantityCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity on hand'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(labelText: 'Unit (pcs, kg, box...)'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _lowStockCtrl,
                  decoration: const InputDecoration(labelText: 'Low stock alert at'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Selling price',
                    prefixText: '\u20b1 ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (double.tryParse(v.trim()) == null) return 'Invalid number';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _costPriceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cost price (optional)',
                    prefixText: '\u20b1 ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (double.tryParse(v.trim()) == null) return 'Invalid number';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _submit,
                icon: Icon(isEditing ? Icons.save : Icons.add),
                label: Text(isEditing ? 'Save changes' : 'Add stock item'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
