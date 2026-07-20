import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/product.dart';
import '../models/sale.dart';

/// Builds CSV export files for stock inventory and sales history.
///
/// Files are written to the app's documents directory (available on every
/// platform without extra permissions); callers are responsible for
/// sharing/revealing the resulting file to the user.
class ExportService {
  ExportService._();

  static final _fileTimestamp = DateFormat('yyyyMMdd_HHmmss');
  static final _cellTimestamp = DateFormat('yyyy-MM-dd HH:mm');

  static Future<File> exportStocksCsv(List<Product> products) async {
    final rows = <List<dynamic>>[
      ['Product Name', 'SKU', 'Category', 'Size', 'Color', 'Quantity', 'Unit', 'Price', 'Cost Price', 'Low Stock Alert At', 'Updated At'],
      for (final product in products)
        for (final variant in product.variants)
          [
            product.name,
            variant.sku,
            product.category,
            variant.size,
            variant.color,
            variant.quantity,
            product.unit,
            product.price,
            product.costPrice,
            variant.lowStockThreshold,
            _cellTimestamp.format(variant.updatedAt),
          ],
    ];
    return _writeCsv('stock_export_${_fileTimestamp.format(DateTime.now())}.csv', rows);
  }

  static Future<File> exportSalesCsv(List<Sale> sales) async {
    final rows = <List<dynamic>>[
      [
        'Sale ID',
        'Date',
        'Product Name',
        'SKU',
        'Size',
        'Color',
        'Unit Price',
        'Quantity',
        'Line Subtotal',
        'Sale Subtotal',
        'Discount',
        'Sale Total',
      ],
      for (final sale in sales)
        for (final line in sale.items)
          [
            sale.id,
            _cellTimestamp.format(sale.createdAt),
            line.name,
            line.sku,
            line.size,
            line.color,
            line.unitPrice,
            line.quantity,
            line.subtotal,
            sale.subtotal,
            sale.discountAmount,
            sale.total,
          ],
    ];
    return _writeCsv('sales_export_${_fileTimestamp.format(DateTime.now())}.csv', rows);
  }

  // addBom ensures Excel correctly detects UTF-8 encoding (e.g. the peso sign).
  static final _csv = Csv(addBom: true);

  static Future<File> _writeCsv(String filename, List<List<dynamic>> rows) async {
    final csvBody = _csv.encode(rows);
    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(dir.path, 'exports'));
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final file = File(p.join(exportsDir.path, filename));
    await file.writeAsString(csvBody, encoding: utf8);
    return file;
  }
}
