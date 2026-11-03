import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/adjustment.dart';
import '../models/product.dart';
import '../models/sale.dart';

/// Thrown when a sale can't be completed because one or more cart lines
/// exceed the currently available stock quantity.
/// Thrown when a return or exchange can't be recorded (too many items
/// brought back, or the product is no longer in inventory).
class AdjustmentException implements Exception {
  AdjustmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class InsufficientStockException implements Exception {
  InsufficientStockException(this.itemName, this.available, this.requested);

  final String itemName;
  final int available;
  final int requested;

  @override
  String toString() =>
      'Not enough stock for "$itemName" (have $available, requested $requested)';
}

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const _dbName = 'pos_app.db';
  static const _dbVersion = 11;

  /// Legacy flat stock table (pre-variants). Only read during migration.
  static const _legacyStocksTable = 'stocks';

  static const productsTable = 'products';
  static const variantsTable = 'product_variants';
  static const salesTable = 'sales';
  static const saleItemsTable = 'sale_items';
  static const adjustmentsTable = 'adjustments';
  static const adjustmentLinesTable = 'adjustment_lines';
  static const pendingVoidsTable = 'pending_voids';

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createProductTables(db);
    await _createSalesTables(db);
    await _createAdjustmentTables(db);
    await _createSyncTables(db);
  }

  Future<void> _createProductTables(Database db) async {
    await db.execute('''
      CREATE TABLE $productsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        unit TEXT NOT NULL,
        price REAL NOT NULL,
        costPrice REAL NOT NULL,
        imagePath TEXT,
        updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $variantsTable (
        id TEXT PRIMARY KEY,
        productId TEXT NOT NULL,
        sku TEXT NOT NULL,
        size TEXT NOT NULL DEFAULT '',
        color TEXT NOT NULL DEFAULT '',
        quantity INTEGER NOT NULL,
        lowStockThreshold INTEGER NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (productId) REFERENCES $productsTable (id)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createSalesTables(db);
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, salesTable, 'discountType', "TEXT NOT NULL DEFAULT 'none'");
      await _addColumnIfMissing(db, salesTable, 'discountValue', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, salesTable, 'discountAmount', 'REAL NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      if (await _tableExists(db, _legacyStocksTable)) {
        await _addColumnIfMissing(db, _legacyStocksTable, 'size', "TEXT NOT NULL DEFAULT ''");
        await _addColumnIfMissing(db, _legacyStocksTable, 'color', "TEXT NOT NULL DEFAULT ''");
      }
      await _addColumnIfMissing(db, saleItemsTable, 'size', "TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(db, saleItemsTable, 'color', "TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 5) {
      await _migrateStocksToProducts(db);
    }
    if (oldVersion < 6) {
      await _addColumnIfMissing(db, salesTable, 'paymentMethod', "TEXT NOT NULL DEFAULT 'cash'");
    }

    // Defensive final pass: guarantee every column the current app code
    // relies on actually exists, in case a database's stored version number
    // doesn't perfectly match its real schema (e.g. from an earlier
    // interrupted migration during development). All of these are no-ops
    // when the column is already present.
    await _addColumnIfMissing(db, saleItemsTable, 'size', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, saleItemsTable, 'color', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, salesTable, 'discountType', "TEXT NOT NULL DEFAULT 'none'");
    await _addColumnIfMissing(db, salesTable, 'discountValue', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, salesTable, 'discountAmount', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, salesTable, 'paymentMethod', "TEXT NOT NULL DEFAULT 'cash'");
    await _addColumnIfMissing(db, saleItemsTable, 'discountType', "TEXT NOT NULL DEFAULT 'none'");
    await _addColumnIfMissing(db, saleItemsTable, 'discountValue', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, saleItemsTable, 'discountAmount', 'REAL NOT NULL DEFAULT 0');

    // Returns and size exchanges. IF NOT EXISTS so this also heals a
    // database whose version number got ahead of its real tables.
    await _createAdjustmentTables(db);
    await _addColumnIfMissing(db, salesTable, 'sheetSyncedAt', 'TEXT');
    await _addColumnIfMissing(db, adjustmentsTable, 'sheetSyncedAt', 'TEXT');
    await _addColumnIfMissing(db, salesTable, 'receiptNumber', 'TEXT');
    await _createSyncTables(db);
    await _backfillReceiptNumbers(db);
  }

  /// Gives every sale that doesn't have one a short receipt number, in the
  /// order the sales were made, so older receipts can be looked up too.
  Future<void> _backfillReceiptNumbers(Database db) async {
    final rows = await db.query(salesTable, columns: ['id', 'receiptNumber'], orderBy: 'createdAt ASC');
    var max = 0;
    for (final row in rows) {
      final current = _receiptSequence(row['receiptNumber'] as String?);
      if (current != null && current > max) max = current;
    }
    for (final row in rows) {
      final current = row['receiptNumber'] as String?;
      if (current != null && current.isNotEmpty) continue;
      max += 1;
      await db.update(
        salesTable,
        {'receiptNumber': _formatReceipt(max)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  int? _receiptSequence(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'^S-(\d+)$').firstMatch(value.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String _formatReceipt(int sequence) => 'S-${sequence.toString().padLeft(4, '0')}';

  Future<String> _nextReceiptNumber(DatabaseExecutor db) async {
    final rows = await db.query(salesTable, columns: ['receiptNumber']);
    var max = 0;
    for (final row in rows) {
      final current = _receiptSequence(row['receiptNumber'] as String?);
      if (current != null && current > max) max = current;
    }
    return _formatReceipt(max + 1);
  }

  Future<void> _createSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $pendingVoidsTable (
        id TEXT PRIMARY KEY,
        saleId TEXT NOT NULL,
        payload TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        sheetSyncedAt TEXT
      )
    ''');
  }

  Future<void> _createAdjustmentTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $adjustmentsTable (
        id TEXT PRIMARY KEY,
        saleId TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        kind TEXT NOT NULL,
        sheetSyncedAt TEXT,
        FOREIGN KEY (saleId) REFERENCES $salesTable (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $adjustmentLinesTable (
        id TEXT PRIMARY KEY,
        adjustmentId TEXT NOT NULL,
        saleItemId TEXT,
        stockId TEXT NOT NULL,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        size TEXT NOT NULL DEFAULT '',
        color TEXT NOT NULL DEFAULT '',
        quantity INTEGER NOT NULL,
        direction TEXT NOT NULL,
        unitPrice REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (adjustmentId) REFERENCES $adjustmentsTable (id)
      )
    ''');
  }

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.any((row) => row['name'] == column);
  }

  /// Adds [column] to [table] with [definition] (e.g. "TEXT NOT NULL DEFAULT
  /// ''") only if it doesn't already exist, so upgrade steps can be re-run
  /// safely against a database that's in an unexpected/partial state.
  Future<void> _addColumnIfMissing(Database db, String table, String column, String definition) async {
    if (!await _columnExists(db, table, column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  /// Splits the old flat `stocks` table into `products` + `product_variants`,
  /// grouping rows that share the exact same product name into a single
  /// product with multiple variants (one per original row). Each variant
  /// reuses its original stock row's id, so `sale_items.stockId` on existing
  /// sales keeps pointing at a valid record with no further changes needed.
  ///
  /// The original `stocks` table is kept around (renamed) as a safety net
  /// rather than dropped.
  Future<void> _migrateStocksToProducts(Database db) async {
    if (!await _tableExists(db, _legacyStocksTable)) {
      // Nothing to migrate (e.g. this db already went through the v5
      // migration once before, or was created fresh past that point).
      if (!await _tableExists(db, productsTable)) {
        await _createProductTables(db);
      }
      return;
    }
    if (!await _tableExists(db, productsTable)) {
      await _createProductTables(db);
    }

    final legacyRows = await db.query(_legacyStocksTable, orderBy: 'name COLLATE NOCASE ASC');
    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in legacyRows) {
      final name = row['name'] as String;
      groups.putIfAbsent(name, () => []).add(row);
    }

    await db.transaction((txn) async {
      for (final entry in groups.entries) {
        final rows = entry.value;
        // Product-level fields (category/unit/price/cost) come from the
        // first row in the group; low-stock threshold stays per-variant.
        final first = rows.first;
        final productId = const Uuid().v4();

        await txn.insert(productsTable, {
          'id': productId,
          'name': entry.key,
          'category': first['category'],
          'unit': first['unit'],
          'price': first['price'],
          'costPrice': first['costPrice'],
          'imagePath': null,
          'updatedAt': first['updatedAt'],
        });

        for (final row in rows) {
          await txn.insert(variantsTable, {
            'id': row['id'],
            'productId': productId,
            'sku': row['sku'],
            'size': row['size'] ?? '',
            'color': row['color'] ?? '',
            'quantity': row['quantity'],
            'lowStockThreshold': row['lowStockThreshold'],
            'updatedAt': row['updatedAt'],
          });
        }
      }

      await txn.execute('ALTER TABLE $_legacyStocksTable RENAME TO stocks_legacy_v4');
    });
  }

  Future<void> _createSalesTables(Database db) async {
    await db.execute('''
      CREATE TABLE $salesTable (
        id TEXT PRIMARY KEY,
        createdAt TEXT NOT NULL,
        discountType TEXT NOT NULL DEFAULT 'none',
        discountValue REAL NOT NULL DEFAULT 0,
        discountAmount REAL NOT NULL DEFAULT 0,
        paymentMethod TEXT NOT NULL DEFAULT 'cash',
        sheetSyncedAt TEXT,
        receiptNumber TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE $saleItemsTable (
        id TEXT PRIMARY KEY,
        saleId TEXT NOT NULL,
        stockId TEXT NOT NULL,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        unitPrice REAL NOT NULL,
        quantity INTEGER NOT NULL,
        size TEXT NOT NULL DEFAULT '',
        color TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (saleId) REFERENCES $salesTable (id)
      )
    ''');
  }

  Future<List<ProductVariant>> _variantsForProduct(DatabaseExecutor db, String productId) async {
    final rows = await db.query(
      variantsTable,
      where: 'productId = ?',
      whereArgs: [productId],
      orderBy: 'size COLLATE NOCASE ASC, color COLLATE NOCASE ASC',
    );
    return rows.map(ProductVariant.fromMap).toList();
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final rows = await db.query(productsTable, orderBy: 'name COLLATE NOCASE ASC');
    final products = <Product>[];
    for (final row in rows) {
      final variants = await _variantsForProduct(db, row['id'] as String);
      products.add(Product.fromMap(row, variants));
    }
    return products;
  }

  Future<Product?> getProductByVariantId(String variantId) async {
    final db = await database;
    final rows = await db.query(
      variantsTable,
      columns: ['productId'],
      where: 'id = ?',
      whereArgs: [variantId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return getProductById(rows.first['productId'] as String);
  }

  Future<Product?> getProductById(String id) async {
    final db = await database;
    final rows = await db.query(productsTable, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final variants = await _variantsForProduct(db, id);
    return Product.fromMap(rows.first, variants);
  }

  /// Inserts or fully replaces a product and its variant list in one
  /// transaction. Any variants no longer present in [product.variants] are
  /// deleted; the rest are upserted.
  Future<void> saveProduct(Product product) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        productsTable,
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final existingIds = (await txn.query(
        variantsTable,
        columns: ['id'],
        where: 'productId = ?',
        whereArgs: [product.id],
      )).map((r) => r['id'] as String).toSet();

      final keptIds = product.variants.map((v) => v.id).toSet();
      final removedIds = existingIds.difference(keptIds);
      for (final id in removedIds) {
        await txn.delete(variantsTable, where: 'id = ?', whereArgs: [id]);
      }

      for (final variant in product.variants) {
        await txn.insert(
          variantsTable,
          variant.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteProduct(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(variantsTable, where: 'productId = ?', whereArgs: [id]);
      await txn.delete(productsTable, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<bool> skuExists(String sku, {String? excludingVariantId}) async {
    final db = await database;
    final rows = await db.query(
      variantsTable,
      where: excludingVariantId == null ? 'sku = ?' : 'sku = ? AND id != ?',
      whereArgs: excludingVariantId == null ? [sku] : [sku, excludingVariantId],
    );
    return rows.isNotEmpty;
  }

  /// Completes a sale for the given cart lines, decrementing each variant's
  /// stock quantity and persisting a sale record.
  ///
  /// An optional discount can be applied to the cart's subtotal: pass
  /// [discountType]/[discountValue] as a flat peso amount ([DiscountType.fixed])
  /// or a percentage 0-100 ([DiscountType.percent]). The resulting discount is
  /// Each cart line can carry its own discount. [discountType]/[discountValue]
  /// is an extra discount on whatever is left after those line discounts,
  /// as a flat peso amount ([DiscountType.fixed]) or a percentage 0-100
  /// ([DiscountType.percent]). The result is clamped so the total stays
  /// at zero or above.
  /// Runs inside a single transaction: if any line would oversell a variant,
  /// [InsufficientStockException] is thrown and nothing is written.
  Future<Sale> recordSale(
    List<CartLine> cart, {
    DiscountType discountType = DiscountType.none,
    double discountValue = 0,
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) async {
    if (cart.isEmpty) {
      throw ArgumentError('Cannot record a sale with an empty cart');
    }

    final db = await database;
    final saleId = const Uuid().v4();
    final createdAt = DateTime.now();
    final lineItems = <SaleLineItem>[];
    late final String receiptNumber;

    await db.transaction((txn) async {
      receiptNumber = await _nextReceiptNumber(txn);
      for (final cartLine in cart) {
        final rows = await txn.query(variantsTable, where: 'id = ?', whereArgs: [cartLine.variant.id]);
        if (rows.isEmpty) continue;
        final current = ProductVariant.fromMap(rows.first);

        if (current.quantity < cartLine.quantity) {
          final itemName = cartLine.product.name +
              (current.hasVariantLabel ? ' (${current.label})' : '');
          throw InsufficientStockException(itemName, current.quantity, cartLine.quantity);
        }

        await txn.update(
          variantsTable,
          {
            'quantity': current.quantity - cartLine.quantity,
            'updatedAt': createdAt.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [current.id],
        );

        final lineSubtotal = cartLine.product.price * cartLine.quantity;
        lineItems.add(SaleLineItem(
          id: const Uuid().v4(),
          saleId: saleId,
          stockId: current.id,
          name: cartLine.product.name,
          sku: current.sku,
          unitPrice: cartLine.product.price,
          quantity: cartLine.quantity,
          size: current.size,
          color: current.color,
          discountType: cartLine.discountType,
          discountValue: cartLine.discountValue,
          discountAmount: computeDiscountAmount(lineSubtotal, cartLine.discountType, cartLine.discountValue),
        ));
      }

      final subtotal = lineItems.fold<double>(0, (sum, line) => sum + line.subtotal);
      final itemDiscount = lineItems.fold<double>(0, (sum, line) => sum + line.discountAmount);
      final discountAmount = computeDiscountAmount(subtotal - itemDiscount, discountType, discountValue);

      await txn.insert(salesTable, {
        'id': saleId,
        'createdAt': createdAt.toIso8601String(),
        'discountType': discountType.dbValue,
        'discountValue': discountValue,
        'discountAmount': discountAmount,
        'paymentMethod': paymentMethod.dbValue,
        'receiptNumber': receiptNumber,
      });
      for (final line in lineItems) {
        await txn.insert(saleItemsTable, line.toMap());
      }
    });

    final subtotal = lineItems.fold<double>(0, (sum, line) => sum + line.subtotal);
    final itemDiscount = lineItems.fold<double>(0, (sum, line) => sum + line.discountAmount);
    final discountAmount = computeDiscountAmount(subtotal - itemDiscount, discountType, discountValue);
    return Sale(
      id: saleId,
      createdAt: createdAt,
      items: lineItems,
      discountType: discountType,
      discountValue: discountValue,
      discountAmount: discountAmount,
      paymentMethod: paymentMethod,
      receiptNumber: receiptNumber,
    );
  }

  Future<List<Sale>> getAllSales() async {
    final db = await database;
    final saleRows = await db.query(salesTable, orderBy: 'createdAt DESC');
    final sales = <Sale>[];
    for (final saleRow in saleRows) {
      final itemRows = await db.query(
        saleItemsTable,
        where: 'saleId = ?',
        whereArgs: [saleRow['id']],
      );
      sales.add(Sale.fromMap(saleRow, itemRows.map(SaleLineItem.fromMap).toList()));
    }
    return sales;
  }

  Future<double> getTodaysSalesTotal() async {
    final sales = await getAllSales();
    final now = DateTime.now();
    return sales
        .where((s) => s.createdAt.year == now.year && s.createdAt.month == now.month && s.createdAt.day == now.day)
        .fold<double>(0.0, (sum, s) => sum + s.total);
  }

  /// Records a return or size/color exchange against an existing sale.
  ///
  /// Returned units go back onto their original variant. When [lines]
  /// include [ReturnLineRequest.exchangeTo], that many units are taken
  /// from the replacement variant. The original sale row is left as-is so
  /// the receipt history stays intact.
  Future<StockAdjustment> recordReturnOrExchange({
    required String saleId,
    required List<ReturnLineRequest> lines,
  }) async {
    final requested = lines.where((l) => l.quantity > 0).toList();
    if (requested.isEmpty) {
      throw AdjustmentException('Choose at least one item to return');
    }

    final db = await database;
    final adjustmentId = const Uuid().v4();
    final createdAt = DateTime.now();
    final savedLines = <AdjustmentLine>[];

    await db.transaction((txn) async {
      final already = await _inboundQtyBySaleItem(txn, saleId);
      final saleRows = await txn.query(saleItemsTable, where: 'saleId = ?', whereArgs: [saleId]);
      final soldById = {for (final row in saleRows) row['id'] as String: SaleLineItem.fromMap(row)};

      for (final request in requested) {
        final sold = soldById[request.saleLine.id];
        if (sold == null) {
          throw AdjustmentException('That item is not part of this sale');
        }
        final remaining = sold.quantity - (already[sold.id] ?? 0);
        if (request.quantity > remaining) {
          throw AdjustmentException(
            'Only $remaining of "${sold.name}" can still be returned',
          );
        }

        await _changeVariantQty(
          txn,
          sold.stockId,
          request.quantity,
          _lineName(sold.name, sold.size, sold.color),
        );
        savedLines.add(AdjustmentLine(
          id: const Uuid().v4(),
          adjustmentId: adjustmentId,
          saleItemId: sold.id,
          stockId: sold.stockId,
          name: sold.name,
          sku: sold.sku,
          size: sold.size,
          color: sold.color,
          quantity: request.quantity,
          direction: AdjustmentDirection.inbound,
          unitPrice: sold.netUnitPrice,
        ));

        final replacement = request.exchangeTo;
        if (replacement != null && replacement.id != sold.stockId) {
          await _changeVariantQty(
            txn,
            replacement.id,
            -request.quantity,
            _lineName(request.exchangeName, replacement.size, replacement.color),
          );
          savedLines.add(AdjustmentLine(
            id: const Uuid().v4(),
            adjustmentId: adjustmentId,
            saleItemId: sold.id,
            stockId: replacement.id,
            name: request.exchangeName.isEmpty ? sold.name : request.exchangeName,
            sku: replacement.sku,
            size: replacement.size,
            color: replacement.color,
            quantity: request.quantity,
            direction: AdjustmentDirection.outbound,
            unitPrice: request.exchangeUnitPrice,
          ));
        }
      }

      final kind = savedLines.any((l) => l.direction == AdjustmentDirection.outbound) ? 'exchange' : 'return';
      await txn.insert(adjustmentsTable, {
        'id': adjustmentId,
        'saleId': saleId,
        'createdAt': createdAt.toIso8601String(),
        'kind': kind,
      });
      for (final line in savedLines) {
        await txn.insert(adjustmentLinesTable, line.toMap());
      }
    });

    final kind = savedLines.any((l) => l.direction == AdjustmentDirection.outbound) ? 'exchange' : 'return';
    return StockAdjustment(
      id: adjustmentId,
      saleId: saleId,
      createdAt: createdAt,
      kind: kind,
      lines: savedLines,
    );
  }

  Future<Map<String, List<StockAdjustment>>> getAdjustmentsGroupedBySale() async {
    final db = await database;
    if (!await _tableExists(db, adjustmentsTable)) return {};

    final adjRows = await db.query(adjustmentsTable, orderBy: 'createdAt DESC');
    final lineRows = await db.query(adjustmentLinesTable);
    final linesByAdj = <String, List<AdjustmentLine>>{};
    for (final row in lineRows) {
      final line = AdjustmentLine.fromMap(row);
      linesByAdj.putIfAbsent(line.adjustmentId, () => []).add(line);
    }

    final grouped = <String, List<StockAdjustment>>{};
    for (final row in adjRows) {
      final adjustment = StockAdjustment.fromMap(row, linesByAdj[row['id']] ?? const []);
      grouped.putIfAbsent(adjustment.saleId, () => []).add(adjustment);
    }
    return grouped;
  }

  Future<Map<String, int>> _inboundQtyBySaleItem(DatabaseExecutor db, String saleId) async {
    final rows = await db.rawQuery(
      '''
      SELECT l.saleItemId AS saleItemId, SUM(l.quantity) AS qty
      FROM $adjustmentLinesTable l
      JOIN $adjustmentsTable a ON a.id = l.adjustmentId
      WHERE a.saleId = ? AND l.direction = 'in' AND l.saleItemId IS NOT NULL
      GROUP BY l.saleItemId
      ''',
      [saleId],
    );
    return {
      for (final row in rows) row['saleItemId'] as String: (row['qty'] as num).toInt(),
    };
  }

  Future<void> _changeVariantQty(DatabaseExecutor txn, String variantId, int delta, String itemName) async {
    final rows = await txn.query(variantsTable, where: 'id = ?', whereArgs: [variantId]);
    if (rows.isEmpty) {
      throw AdjustmentException('"$itemName" is no longer in inventory, so stock can\'t be updated');
    }
    final current = ProductVariant.fromMap(rows.first);
    final next = current.quantity + delta;
    if (next < 0) {
      throw InsufficientStockException(itemName, current.quantity, -delta);
    }
    await txn.update(
      variantsTable,
      {
        'quantity': next,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [variantId],
    );
  }

  String _lineName(String name, String size, String color) {
    final label = [size, color].where((v) => v.isNotEmpty).join(', ');
    return label.isEmpty ? name : '$name ($label)';
  }

  /// Deletes (voids) a sale and restores the quantities it deducted back
  /// onto their product variants, so inventory counts stay accurate.
  ///
  /// Returns and exchanges on that sale are undone first, so stock isn't
  /// counted twice. Variants that have since been deleted are skipped.
  Future<List<Sale>> getUnsyncedSales() async {
    final db = await database;
    final saleRows = await db.query(
      salesTable,
      where: 'sheetSyncedAt IS NULL',
      orderBy: 'createdAt ASC',
    );
    final sales = <Sale>[];
    for (final saleRow in saleRows) {
      final itemRows = await db.query(saleItemsTable, where: 'saleId = ?', whereArgs: [saleRow['id']]);
      sales.add(Sale.fromMap(saleRow, itemRows.map(SaleLineItem.fromMap).toList()));
    }
    return sales;
  }

  Future<List<StockAdjustment>> getUnsyncedAdjustments() async {
    final db = await database;
    final adjRows = await db.query(
      adjustmentsTable,
      where: 'sheetSyncedAt IS NULL',
      orderBy: 'createdAt ASC',
    );
    final adjustments = <StockAdjustment>[];
    for (final row in adjRows) {
      final lineRows = await db.query(
        adjustmentLinesTable,
        where: 'adjustmentId = ?',
        whereArgs: [row['id']],
      );
      adjustments.add(StockAdjustment.fromMap(row, lineRows.map(AdjustmentLine.fromMap).toList()));
    }
    return adjustments;
  }

  Future<List<Map<String, Object?>>> getUnsyncedVoids() async {
    final db = await database;
    if (!await _tableExists(db, pendingVoidsTable)) return [];
    return db.query(pendingVoidsTable, where: 'sheetSyncedAt IS NULL', orderBy: 'createdAt ASC');
  }

  Future<void> markSheetSynced({
    List<String> saleIds = const [],
    List<String> adjustmentIds = const [],
    List<String> voidIds = const [],
  }) async {
    if (saleIds.isEmpty && adjustmentIds.isEmpty && voidIds.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final id in saleIds) {
        await txn.update(salesTable, {'sheetSyncedAt': now}, where: 'id = ?', whereArgs: [id]);
      }
      for (final id in adjustmentIds) {
        await txn.update(adjustmentsTable, {'sheetSyncedAt': now}, where: 'id = ?', whereArgs: [id]);
      }
      for (final id in voidIds) {
        await txn.update(pendingVoidsTable, {'sheetSyncedAt': now}, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<int> pendingSyncCount() async {
    final db = await database;
    Future<int> count(String table) async {
      if (!await _tableExists(db, table)) return 0;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table WHERE sheetSyncedAt IS NULL');
      return (rows.first['c'] as num?)?.toInt() ?? 0;
    }

    return await count(salesTable) + await count(adjustmentsTable) + await count(pendingVoidsTable);
  }

  /// Inserts product variants that exist on the sheet but not on this device.
  /// Existing variants are left alone, so local stock stays the source of truth.
  /// Returns how many variants were added.
  Future<int> importNewSheetVariants(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return 0;
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final variantId = (row['variantId'] as String?)?.trim() ?? '';
      final productId = (row['productId'] as String?)?.trim() ?? '';
      if (variantId.isEmpty || productId.isEmpty) continue;
      grouped.putIfAbsent(productId, () => []).add(row);
    }

    var added = 0;
    for (final entry in grouped.entries) {
      final existing = await getProductById(entry.key);
      final known = existing?.variants.map((v) => v.id).toSet() ?? {};
      final fresh = <ProductVariant>[];
      for (final row in entry.value) {
        final variantId = (row['variantId'] as String).trim();
        if (known.contains(variantId)) continue;
        fresh.add(ProductVariant(
          id: variantId,
          productId: entry.key,
          sku: (row['sku'] as String?)?.trim() ?? '',
          size: (row['size'] as String?)?.trim() ?? '',
          color: (row['color'] as String?)?.trim() ?? '',
          quantity: (row['quantity'] as num?)?.toInt() ?? 0,
          lowStockThreshold: (row['lowStock'] as num?)?.toInt() ?? 5,
          updatedAt: DateTime.tryParse(row['updatedAt'] as String? ?? '') ?? DateTime.now(),
        ));
      }
      if (fresh.isEmpty) continue;

      final first = entry.value.first;
      if (existing == null) {
        await saveProduct(Product(
          id: entry.key,
          name: (first['name'] as String?)?.trim().isNotEmpty == true ? (first['name'] as String).trim() : 'Untitled',
          category: (first['category'] as String?)?.trim().isNotEmpty == true ? (first['category'] as String).trim() : 'General',
          unit: (first['unit'] as String?)?.trim().isNotEmpty == true ? (first['unit'] as String).trim() : 'pcs',
          price: (first['price'] as num?)?.toDouble() ?? 0,
          costPrice: (first['costPrice'] as num?)?.toDouble() ?? 0,
          updatedAt: DateTime.now(),
          variants: fresh,
        ));
      } else {
        await saveProduct(existing.copyWith(variants: [...existing.variants, ...fresh]));
      }
      added += fresh.length;
    }
    return added;
  }

  Future<void> deleteSale(String saleId) async {
    final db = await database;
    await db.transaction((txn) async {
      final saleRows = await txn.query(salesTable, where: 'id = ?', whereArgs: [saleId]);
      final saleSynced = saleRows.isNotEmpty && saleRows.first['sheetSyncedAt'] != null;
      final receipt = saleRows.isEmpty ? '' : saleRows.first['receiptNumber'] as String? ?? '';
      final sheetSaleId = receipt.isEmpty ? saleId : receipt;
      final itemRows = await txn.query(saleItemsTable, where: 'saleId = ?', whereArgs: [saleId]);
      final adjRowsForVoid = await txn.query(adjustmentsTable, where: 'saleId = ?', whereArgs: [saleId]);
      final voidMovements = <Map<String, Object?>>[];
      final voidedAt = DateTime.now().toIso8601String();

      if (saleSynced) {
        for (final item in itemRows) {
          voidMovements.add({
            'id': 'void-${item['id']}',
            'createdAt': voidedAt,
            'variantId': item['stockId'],
            'sku': item['sku'] ?? '',
            'name': item['name'] ?? '',
            'size': item['size'] ?? '',
            'color': item['color'] ?? '',
            'delta': item['quantity'],
            'reason': 'void_sale',
            'saleId': sheetSaleId,
            'sourceId': item['id'],
          });
        }
      }

      if (adjRowsForVoid.isNotEmpty) {
        final ids = adjRowsForVoid.map((r) => r['id'] as String).toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        final syncedAdjIds = adjRowsForVoid
            .where((r) => r['sheetSyncedAt'] != null)
            .map((r) => r['id'] as String)
            .toSet();
        final adjLineRows = await txn.query(
          adjustmentLinesTable,
          where: 'adjustmentId IN ($placeholders)',
          whereArgs: ids,
        );
        for (final line in adjLineRows) {
          if (!syncedAdjIds.contains(line['adjustmentId'])) continue;
          final inbound = line['direction'] == 'in';
          final quantity = line['quantity'] as int;
          voidMovements.add({
            'id': 'void-${line['id']}',
            'createdAt': voidedAt,
            'variantId': line['stockId'],
            'sku': line['sku'] ?? '',
            'name': line['name'] ?? '',
            'size': line['size'] ?? '',
            'color': line['color'] ?? '',
            'delta': inbound ? -quantity : quantity,
            'reason': inbound ? 'void_return' : 'void_exchange',
            'saleId': sheetSaleId,
            'sourceId': line['id'],
          });
        }
      }

      if (voidMovements.isNotEmpty) {
        await txn.insert(pendingVoidsTable, {
          'id': const Uuid().v4(),
          'saleId': saleId,
          'payload': jsonEncode({'movements': voidMovements}),
          'createdAt': voidedAt,
        });
      }

      final adjRows = await txn.query(adjustmentsTable, where: 'saleId = ?', whereArgs: [saleId]);
      if (adjRows.isNotEmpty) {
        final ids = adjRows.map((r) => r['id'] as String).toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        final lineRows = await txn.query(
          adjustmentLinesTable,
          where: 'adjustmentId IN ($placeholders)',
          whereArgs: ids,
        );
        for (final lineRow in lineRows) {
          final line = AdjustmentLine.fromMap(lineRow);
          final delta = line.direction == AdjustmentDirection.inbound ? -line.quantity : line.quantity;
          final variantRows = await txn.query(variantsTable, where: 'id = ?', whereArgs: [line.stockId]);
          if (variantRows.isEmpty) continue;
          final current = ProductVariant.fromMap(variantRows.first);
          final next = current.quantity + delta;
          if (next < 0) {
            throw AdjustmentException(
              'Can\'t delete this sale because "${line.name}" from the return was already sold again',
            );
          }
          await txn.update(
            variantsTable,
            {
              'quantity': next,
              'updatedAt': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [current.id],
          );
        }
        await txn.delete(adjustmentLinesTable, where: 'adjustmentId IN ($placeholders)', whereArgs: ids);
        await txn.delete(adjustmentsTable, where: 'saleId = ?', whereArgs: [saleId]);
      }

      final lineRows = await txn.query(saleItemsTable, where: 'saleId = ?', whereArgs: [saleId]);

      for (final lineRow in lineRows) {
        final line = SaleLineItem.fromMap(lineRow);
        final variantRows = await txn.query(variantsTable, where: 'id = ?', whereArgs: [line.stockId]);
        if (variantRows.isEmpty) continue;
        final current = ProductVariant.fromMap(variantRows.first);
        await txn.update(
          variantsTable,
          {
            'quantity': current.quantity + line.quantity,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [current.id],
        );
      }

      await txn.delete(saleItemsTable, where: 'saleId = ?', whereArgs: [saleId]);
      await txn.delete(salesTable, where: 'id = ?', whereArgs: [saleId]);
    });
  }
}
