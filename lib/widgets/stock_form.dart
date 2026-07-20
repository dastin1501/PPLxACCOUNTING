import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../services/image_storage_service.dart';
import '../utils/color_names.dart';

const _sizePresets = ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL'];

/// Form for creating a new [Product] (with its variants) or editing an
/// existing one.
///
/// Pass [initial] to edit; leave it null to create a new product.
class StockForm extends StatefulWidget {
  const StockForm({
    super.key,
    required this.initial,
    required this.onSubmit,
    required this.onCancel,
    required this.skuValidator,
  });

  final Product? initial;
  final void Function(Product product) onSubmit;
  final VoidCallback onCancel;

  /// Returns an error string if [sku] is already used by another variant
  /// (other than [excludingVariantId]), otherwise null.
  final String? Function(String sku, String excludingVariantId) skuValidator;

  @override
  State<StockForm> createState() => _StockFormState();
}

class _VariantRow {
  _VariantRow({
    required this.id,
    String sku = '',
    String size = '',
    String color = '',
    int quantity = 0,
    int lowStockThreshold = 5,
  })  : skuCtrl = TextEditingController(text: sku),
        sizeCtrl = TextEditingController(text: size),
        colorCtrl = TextEditingController(text: color),
        quantityCtrl = TextEditingController(text: quantity.toString()),
        lowStockCtrl = TextEditingController(text: lowStockThreshold.toString());

  factory _VariantRow.fromVariant(ProductVariant v) => _VariantRow(
        id: v.id,
        sku: v.sku,
        size: v.size,
        color: v.color,
        quantity: v.quantity,
        lowStockThreshold: v.lowStockThreshold,
      );

  factory _VariantRow.blank() => _VariantRow(id: const Uuid().v4());

  final String id;
  final TextEditingController skuCtrl;
  final TextEditingController sizeCtrl;
  final TextEditingController colorCtrl;
  final TextEditingController quantityCtrl;
  final TextEditingController lowStockCtrl;

  void dispose() {
    skuCtrl.dispose();
    sizeCtrl.dispose();
    colorCtrl.dispose();
    quantityCtrl.dispose();
    lowStockCtrl.dispose();
  }
}

class _StockFormState extends State<StockForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costPriceCtrl;

  late List<_VariantRow> _variantRows;
  String? _imagePath;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _initFromProduct(widget.initial);
  }

  void _initFromProduct(Product? product) {
    _nameCtrl = TextEditingController(text: product?.name ?? '');
    _categoryCtrl = TextEditingController(text: product?.category ?? '');
    _unitCtrl = TextEditingController(text: product?.unit ?? 'pcs');
    _priceCtrl = TextEditingController(text: product?.price.toString() ?? '');
    _costPriceCtrl = TextEditingController(text: product?.costPrice.toString() ?? '');
    _imagePath = product?.imagePath;
    _variantRows = product == null || product.variants.isEmpty
        ? [_VariantRow.blank()]
        : product.variants.map(_VariantRow.fromVariant).toList();
  }

  // Note: switching between "add new" and "edit <product>" (or between two
  // different products) is handled by the caller giving this widget a new
  // `key`, which makes Flutter fully unmount/remount the form via initState
  // rather than reusing this State. That's what actually resets the fields
  // safely; don't try to detect an `initial` change here and reinitialize
  // controllers in didUpdateWidget (they're `late final` and can only be
  // assigned once per State instance).

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    _costPriceCtrl.dispose();
    for (final row in _variantRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addVariantRow() {
    setState(() => _variantRows.add(_VariantRow.blank()));
  }

  void _addPresetSizeRow(String size) {
    final alreadyPresent = _variantRows.any((r) => r.sizeCtrl.text.trim().toLowerCase() == size.toLowerCase());
    if (alreadyPresent) return;
    setState(() => _variantRows.add(_VariantRow(id: const Uuid().v4(), size: size)));
  }

  void _removeVariantRow(_VariantRow row) {
    setState(() {
      row.dispose();
      _variantRows.remove(row);
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, maxWidth: 1200, imageQuality: 85);
      if (picked == null) return;
      final oldPath = _imagePath;
      final newPath = await ImageStorageService.saveImage(picked.path);
      setState(() => _imagePath = newPath);
      if (oldPath != null && oldPath != newPath) {
        await ImageStorageService.deleteImage(oldPath);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not get a photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _removeImage() async {
    final oldPath = _imagePath;
    setState(() => _imagePath = null);
    await ImageStorageService.deleteImage(oldPath);
  }

  String? _validateVariantSku(_VariantRow row, String? value) {
    if (value == null || value.trim().isEmpty) return 'SKU is required';
    final sku = value.trim();
    final duplicateInForm = _variantRows.any(
      (r) => r != row && r.skuCtrl.text.trim().toLowerCase() == sku.toLowerCase(),
    );
    if (duplicateInForm) return 'Duplicate SKU in this form';
    return widget.skuValidator(sku, row.id);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_variantRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one variant (SKU/quantity) before saving')),
      );
      return;
    }

    final isEditing = widget.initial != null;
    final productId = widget.initial?.id ?? const Uuid().v4();
    final now = DateTime.now();

    final variants = _variantRows
        .map((row) => ProductVariant(
              id: row.id,
              productId: productId,
              sku: row.skuCtrl.text.trim(),
              size: row.sizeCtrl.text.trim(),
              color: row.colorCtrl.text.trim(),
              quantity: int.parse(row.quantityCtrl.text.trim()),
              lowStockThreshold: int.parse(row.lowStockCtrl.text.trim()),
              updatedAt: now,
            ))
        .toList();

    final product = Product(
      id: productId,
      name: _nameCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty ? 'Uncategorized' : _categoryCtrl.text.trim(),
      unit: _unitCtrl.text.trim().isEmpty ? 'pcs' : _unitCtrl.text.trim(),
      price: double.parse(_priceCtrl.text.trim()),
      costPrice: _costPriceCtrl.text.trim().isEmpty ? 0 : double.parse(_costPriceCtrl.text.trim()),
      imagePath: _imagePath,
      updatedAt: now,
      variants: variants,
    );
    widget.onSubmit(product);
    if (!isEditing) {
      setState(() {
        _formKey.currentState!.reset();
        for (final row in _variantRows) {
          row.dispose();
        }
        _variantRows = [_VariantRow.blank()];
        _imagePath = null;
      });
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
                isEditing ? 'Edit Product' : 'Add New Product',
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 28),
          _buildPhotoPicker(theme),
          const SizedBox(height: 24),
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
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Category'),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(labelText: 'Unit (pcs, kg, box...)'),
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
          const SizedBox(height: 28),
          _buildVariantsSection(theme),
          const SizedBox(height: 32),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _submit,
                icon: Icon(isEditing ? Icons.save : Icons.add),
                label: Text(isEditing ? 'Save changes' : 'Add product'),
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

  Widget _buildPhotoPicker(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 120,
          height: 120,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: _pickingImage
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ImageStorageService.exists(_imagePath)
                  ? Image.file(
                      File(_imagePath!),
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      gaplessPlayback: true,
                    )
                  : Icon(Icons.image_outlined, size: 36, color: theme.colorScheme.outline),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pickingImage ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Camera'),
              ),
              OutlinedButton.icon(
                onPressed: _pickingImage ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Gallery'),
              ),
              if (_imagePath != null)
                TextButton.icon(
                  onPressed: _pickingImage ? null : _removeImage,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVariantsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Variants', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text(
              '(size / color / SKU / quantity)',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _sizePresets)
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text(preset),
                onPressed: () => _addPresetSizeRow(preset),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final row in _variantRows) _buildVariantRow(theme, row),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addVariantRow,
          icon: const Icon(Icons.add),
          label: const Text('Add variant'),
        ),
      ],
    );
  }

  Widget _buildVariantRow(ThemeData theme, _VariantRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: row.sizeCtrl,
                  decoration: const InputDecoration(labelText: 'Size', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: row.colorCtrl,
                  decoration: InputDecoration(
                    labelText: 'Color',
                    isDense: true,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorFromName(row.colorCtrl.text) ?? theme.colorScheme.surfaceContainerHighest,
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: row.skuCtrl,
                  decoration: const InputDecoration(labelText: 'SKU / Barcode', isDense: true),
                  validator: (v) => _validateVariantSku(row, v),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove variant',
                onPressed: () => _removeVariantRow(row),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.quantityCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity on hand', isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: row.lowStockCtrl,
                  decoration: const InputDecoration(labelText: 'Low stock alert at', isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 46),
            ],
          ),
        ],
      ),
    );
  }
}
