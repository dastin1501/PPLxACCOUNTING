import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/adjustment.dart';
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

  static Future<File> exportSalesCsv(
    List<Sale> sales, {
    Map<String, List<StockAdjustment>> adjustments = const {},
  }) async {
    final rows = <List<dynamic>>[
      [
        'Sale ID',
        'Receipt Number',
        'Date',
        'Payment Method',
        'Movement',
        'Product Name',
        'SKU',
        'Size',
        'Color',
        'Unit Price',
        'Quantity',
        'Line Subtotal',
        'Item Discount',
        'Sale Subtotal',
        'Discount',
        'Sale Total',
      ],
      for (final sale in sales) ...[
        for (var i = 0; i < sale.items.length; i++)
          [
            sale.id,
            sale.receiptNumber,
            _cellTimestamp.format(sale.createdAt),
            sale.paymentMethod.label,
            'Sale',
            sale.items[i].name,
            sale.items[i].sku,
            sale.items[i].size,
            sale.items[i].color,
            sale.items[i].unitPrice,
            sale.items[i].quantity,
            sale.items[i].subtotal,
            sale.items[i].discountAmount,
            // Sale money is written once. Repeating it on every item makes
            // Excel add the same payment again for the pin and the towel.
            if (i == 0) sale.subtotal else '',
            if (i == 0) sale.discountAmount else '',
            if (i == 0) sale.total else '',
          ],
        for (final adjustment in adjustments[sale.id] ?? const <StockAdjustment>[])
          for (final line in adjustment.lines)
            [
              sale.id,
              sale.receiptNumber,
              _cellTimestamp.format(adjustment.createdAt),
              sale.paymentMethod.label,
              line.direction == AdjustmentDirection.inbound
                  ? (adjustment.isExchange ? 'Exchange returned' : 'Return')
                  : 'Exchange given',
              line.name,
              line.sku,
              line.size,
              line.color,
              line.unitPrice,
              line.direction == AdjustmentDirection.inbound ? -line.quantity : line.quantity,
              line.direction == AdjustmentDirection.inbound ? -line.subtotal : line.subtotal,
              '',
              '',
              '',
              '',
            ],
      ],
    ];
    return _writeCsv('sales_export_${_fileTimestamp.format(DateTime.now())}.csv', rows);
  }

  /// Refunds and exchanges, kept apart from the sales export.
  static Future<File> exportReturnsCsv(List<({StockAdjustment adjustment, Sale? sale})> records) async {
    final rows = <List<dynamic>>[
      [
        'Date',
        'Type',
        'Receipt Number',
        'Sale ID',
        'Product Name',
        'SKU',
        'Size',
        'Color',
        'Movement',
        'Quantity',
        'Amount',
        'Refund',
      ],
      for (final record in records)
        for (var i = 0; i < record.adjustment.lines.length; i++)
          [
            _cellTimestamp.format(record.adjustment.createdAt),
            record.adjustment.isExchange ? 'Exchange' : 'Return',
            record.sale?.receiptNumber ?? '',
            record.adjustment.saleId,
            record.adjustment.lines[i].name,
            record.adjustment.lines[i].sku,
            record.adjustment.lines[i].size,
            record.adjustment.lines[i].color,
            record.adjustment.lines[i].direction == AdjustmentDirection.inbound ? 'Returned' : 'Given',
            record.adjustment.lines[i].direction == AdjustmentDirection.inbound
                ? -record.adjustment.lines[i].quantity
                : record.adjustment.lines[i].quantity,
            record.adjustment.lines[i].direction == AdjustmentDirection.inbound
                ? -record.adjustment.lines[i].subtotal
                : record.adjustment.lines[i].subtotal,
            if (i == 0) record.adjustment.refundAmount else '',
          ],
    ];
    return _writeCsv('returns_export_${_fileTimestamp.format(DateTime.now())}.csv', rows);
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
