import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/sale.dart';
import '../models/stock_item.dart';

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
  static const _dbVersion = 3;
  static const table = 'stocks';
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
    await db.execute('''
      CREATE TABLE $table (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        category TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit TEXT NOT NULL,
        price REAL NOT NULL,
        costPrice REAL NOT NULL,
        lowStockThreshold INTEGER NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    await _createSalesTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createSalesTables(db);
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE $salesTable ADD COLUMN discountType TEXT NOT NULL DEFAULT 'none'");
      await db.execute('ALTER TABLE $salesTable ADD COLUMN discountValue REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE $salesTable ADD COLUMN discountAmount REAL NOT NULL DEFAULT 0');
    }
  }

  Future<void> _createSalesTables(Database db) async {
    await db.execute('''
      CREATE TABLE $salesTable (
        id TEXT PRIMARY KEY,
        createdAt TEXT NOT NULL,
        discountType TEXT NOT NULL DEFAULT 'none',
        discountValue REAL NOT NULL DEFAULT 0,
        discountAmount REAL NOT NULL DEFAULT 0
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
        FOREIGN KEY (saleId) REFERENCES $salesTable (id)
      )
    ''');
  }

  Future<List<StockItem>> getAllStocks() async {
    final db = await database;
    final rows = await db.query(table, orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(StockItem.fromMap).toList();
  }

  Future<StockItem?> getStockById(String id) async {
    final db = await database;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return StockItem.fromMap(rows.first);
  }

  Future<void> insertStock(StockItem item) async {
    final db = await database;
    await db.insert(
      table,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateStock(StockItem item) async {
    final db = await database;
    await db.update(
      table,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteStock(String id) async {
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> skuExists(String sku, {String? excludingId}) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: excludingId == null ? 'sku = ?' : 'sku = ? AND id != ?',
      whereArgs: excludingId == null ? [sku] : [sku, excludingId],
    );
    return rows.isNotEmpty;
  }

  /// Completes a sale for the given cart (stock item -> quantity to sell),
  /// decrementing each item's stock quantity and persisting a sale record.
  ///
  /// An optional discount can be applied to the cart's subtotal: pass
  /// [discountType]/[discountValue] as a flat peso amount ([DiscountType.fixed])
  /// or a percentage 0-100 ([DiscountType.percent]). The resulting discount is
  /// clamped so it never makes the total negative.
  ///
  /// Runs inside a single transaction: if any line would oversell an item,
  /// [InsufficientStockException] is thrown and nothing is written.
  Future<Sale> recordSale(
    Map<StockItem, int> cart, {
    DiscountType discountType = DiscountType.none,
    double discountValue = 0,
  }) async {
    if (cart.isEmpty) {
      throw ArgumentError('Cannot record a sale with an empty cart');
    }

    final db = await database;
    final saleId = const Uuid().v4();
    final createdAt = DateTime.now();
    final lineItems = <SaleLineItem>[];

    await db.transaction((txn) async {
      for (final entry in cart.entries) {
        final stockItem = entry.key;
        final requestedQty = entry.value;

        final rows = await txn.query(table, where: 'id = ?', whereArgs: [stockItem.id]);
        if (rows.isEmpty) continue;
        final current = StockItem.fromMap(rows.first);

        if (current.quantity < requestedQty) {
          throw InsufficientStockException(current.name, current.quantity, requestedQty);
        }

        await txn.update(
          table,
          {
            'quantity': current.quantity - requestedQty,
            'updatedAt': createdAt.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [current.id],
        );

        lineItems.add(SaleLineItem(
          id: const Uuid().v4(),
          saleId: saleId,
          stockId: current.id,
          name: current.name,
          sku: current.sku,
          unitPrice: current.price,
          quantity: requestedQty,
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
  /// onto their stock items, so inventory counts stay accurate. Stock items
  /// that have since been deleted are simply skipped.
  Future<void> deleteSale(String saleId) async {
    final db = await database;
    await db.transaction((txn) async {
      final lineRows = await txn.query(saleItemsTable, where: 'saleId = ?', whereArgs: [saleId]);

      for (final lineRow in lineRows) {
        final line = SaleLineItem.fromMap(lineRow);
        final stockRows = await txn.query(table, where: 'id = ?', whereArgs: [line.stockId]);
        if (stockRows.isEmpty) continue;
        final current = StockItem.fromMap(stockRows.first);
        await txn.update(
          table,
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
