import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/sale.dart';

/// Thrown when a sale can't be completed because one or more cart lines
/// exceed the currently available stock quantity.
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
  static const _dbVersion = 7;

  /// Legacy flat stock table (pre-variants). Only read during migration.
  static const _legacyStocksTable = 'stocks';

  static const productsTable = 'products';
  static const variantsTable = 'product_variants';
  static const salesTable = 'sales';
  static const saleItemsTable = 'sale_items';

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
        paymentMethod TEXT NOT NULL DEFAULT 'cash'
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
  /// clamped so it never makes the total negative.
  ///
  /// [paymentMethod] records how the sale was paid for (cash or online).
  ///
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

    await db.transaction((txn) async {
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
        ));
      }

      final subtotal = lineItems.fold<double>(0, (sum, line) => sum + line.subtotal);
      final discountAmount = computeDiscountAmount(subtotal, discountType, discountValue);

      await txn.insert(salesTable, {
        'id': saleId,
        'createdAt': createdAt.toIso8601String(),
        'discountType': discountType.dbValue,
        'discountValue': discountValue,
        'discountAmount': discountAmount,
        'paymentMethod': paymentMethod.dbValue,
      });
      for (final line in lineItems) {
        await txn.insert(saleItemsTable, line.toMap());
      }
    });

    final subtotal = lineItems.fold<double>(0, (sum, line) => sum + line.subtotal);
    final discountAmount = computeDiscountAmount(subtotal, discountType, discountValue);
    return Sale(
      id: saleId,
      createdAt: createdAt,
      items: lineItems,
      discountType: discountType,
      discountValue: discountValue,
      discountAmount: discountAmount,
      paymentMethod: paymentMethod,
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

  /// Deletes (voids) a sale and restores the quantities it deducted back
  /// onto their product variants, so inventory counts stay accurate.
  /// Variants that have since been deleted are simply skipped.
  Future<void> deleteSale(String saleId) async {
    final db = await database;
    await db.transaction((txn) async {
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
