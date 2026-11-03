import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/adjustment.dart';
import '../models/product.dart';
import '../models/sale.dart';
import 'database_helper.dart';
import 'sheet_sync_settings.dart';

class SheetSyncException implements Exception {
  SheetSyncException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

class SheetSyncResult {
  const SheetSyncResult({
    required this.ok,
    required this.message,
    this.pushedSales = 0,
    this.pushedMovements = 0,
    this.importedVariants = 0,
  });

  final bool ok;
  final String message;
  final int pushedSales;
  final int pushedMovements;
  final int importedVariants;
}

/// Copies the local database to a Google Sheet through an Apps Script web
/// app, and downloads product rows that were added on the sheet.
///
/// The tablet keeps working with no network. Anything that fails to upload
/// stays pending and is sent again on the next sync. The sheet's Sale ID is
/// the receipt number from the app (S-0001), and SKUs are sent unchanged.
/// Line and movement ids stay stable so a repeated sync does not duplicate rows.
class SheetSyncService {
  SheetSyncService._();
  static final SheetSyncService instance = SheetSyncService._();

  final _db = DatabaseHelper.instance;
  Future<SheetSyncResult>? _inFlight;

  Future<SheetSyncResult?> syncIfConfigured() async {
    final config = await SheetSyncSettings.load();
    if (!config.isReady) return null;
    return sync(config);
  }

  Future<SheetSyncResult> sync(SheetSyncConfig config) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final run = _sync(config);
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  Future<SheetSyncResult> _sync(SheetSyncConfig config) async {
    try {
      final pulled = await _withRetry(() => _getProducts(config));
      final imported = await _db.importNewSheetVariants(pulled);

      final products = await _db.getAllProducts();
      final unsyncedSales = await _db.getUnsyncedSales();
      final sales = await _db.getAllSales();
      final unsyncedAdjustments = await _db.getUnsyncedAdjustments();
      final adjustmentGroups = await _db.getAdjustmentsGroupedBySale();
      final adjustments = [for (final group in adjustmentGroups.values) ...group];
      final voids = await _db.getUnsyncedVoids();
      final receiptBySale = {for (final sale in sales) sale.id: sale.receiptNumber};

      final movements = <Map<String, Object?>>[
        for (final sale in sales)
          for (final line in sale.items) _saleMovement(sale, line),
        for (final adjustment in adjustments)
          for (final line in adjustment.lines)
            _adjustmentMovement(adjustment, line, receiptBySale[adjustment.saleId] ?? ''),
        for (final row in voids) ..._voidMovements(row),
      ];

      final response = await _withRetry(() => _post(config, {
            'secret': config.secret.trim(),
            'products': products.expand(_productRows).toList(),
            'sales': sales.map(_salePayload).toList(),
            'movements': movements,
          }));

      final acceptedSales = _idSet(response['saleIds']);
      final acceptedMovements = _idSet(response['movementIds']);
      final saleIds = unsyncedSales.where((sale) {
        if (!acceptedSales.contains(sale.id)) return false;
        return sale.items.every((line) => acceptedMovements.contains('sale-${line.id}'));
      }).map((sale) => sale.id).toList();
      final adjustmentIds = unsyncedAdjustments
          .where((adjustment) => adjustment.lines.every((line) => acceptedMovements.contains('adj-${line.id}')))
          .map((adjustment) => adjustment.id)
          .toList();
      final voidIds = voids.where((row) {
        final ids = _voidMovements(row).map((m) => m['id'].toString());
        return ids.every(acceptedMovements.contains);
      }).map((row) => row['id'] as String).toList();

      await _db.markSheetSynced(
        saleIds: saleIds,
        adjustmentIds: adjustmentIds,
        voidIds: voidIds,
      );

      final pendingMovementIds = <String>{
        for (final sale in unsyncedSales)
          for (final line in sale.items) 'sale-${line.id}',
        for (final adjustment in unsyncedAdjustments)
          for (final line in adjustment.lines) 'adj-${line.id}',
        for (final row in voids)
          for (final movement in _voidMovements(row)) movement['id'].toString(),
      };
      final result = SheetSyncResult(
        ok: true,
        message: _successMessage(
          sales: saleIds.length,
          movements: pendingMovementIds.where(acceptedMovements.contains).length,
          imported: imported,
        ),
        pushedSales: saleIds.length,
        pushedMovements: pendingMovementIds.length,
        importedVariants: imported,
      );
      await SheetSyncSettings.remember(result.message, ok: true);
      return result;
    } on SheetSyncException catch (e) {
      await SheetSyncSettings.remember(e.message, ok: false);
      return SheetSyncResult(ok: false, message: e.message);
    } catch (e) {
      final message = 'Sync failed: $e';
      await SheetSyncSettings.remember(message, ok: false);
      return SheetSyncResult(ok: false, message: message);
    }
  }

  String _successMessage({required int sales, required int movements, required int imported}) {
    final parts = <String>[];
    if (sales > 0) parts.add('$sales sale${sales == 1 ? '' : 's'}');
    if (movements > 0) parts.add('$movements stock change${movements == 1 ? '' : 's'}');
    if (imported > 0) parts.add('$imported new variant${imported == 1 ? '' : 's'} from the sheet');
    if (parts.isEmpty) return 'Sheet is up to date';
    return 'Synced ${parts.join(', ')}';
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await action();
      } on SheetSyncException catch (e) {
        if (!e.retryable) rethrow;
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw SheetSyncException('Could not reach the sheet. $lastError', retryable: false);
  }

  Future<List<Map<String, Object?>>> _getProducts(SheetSyncConfig config) async {
    final uri = _webAppUri(config).replace(queryParameters: {
      'secret': config.secret.trim(),
      'action': 'products',
    });
    final body = await _request('GET', uri);
    final decoded = _decode(body);
    return _productList(decoded['products']);
  }

  Future<Map<String, dynamic>> _post(SheetSyncConfig config, Map<String, Object?> payload) async {
    final body = await _request('POST', _webAppUri(config), jsonEncode(payload));
    return _decode(body);
  }

  Uri _webAppUri(SheetSyncConfig config) {
    final raw = config.webAppUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw SheetSyncException('The web app URL is not valid', retryable: false);
    }
    return uri;
  }

  /// Apps Script web apps answer a POST with a redirect. The first request
  /// still runs doPost; the JSON body is on the redirect target.
  Future<String> _request(String method, Uri uri, [String? body]) async {
    final client = http.Client();
    try {
      final request = http.Request(method, uri);
      request.followRedirects = false;
      if (body != null) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.body = body;
      }
      final streamed = await client.send(request).timeout(const Duration(seconds: 45));
      final status = streamed.statusCode;
      if (status >= 300 && status < 400) {
        final location = streamed.headers['location'];
        if (location == null || location.isEmpty) {
          throw SheetSyncException('Sheet redirect was empty', retryable: true);
        }
        final follow = await client.get(Uri.parse(location)).timeout(const Duration(seconds: 45));
        if (follow.statusCode < 200 || follow.statusCode >= 300) {
          throw SheetSyncException('Sheet returned ${follow.statusCode}', retryable: true);
        }
        return follow.body;
      }
      final text = await streamed.stream.bytesToString();
      if (status < 200 || status >= 300) {
        throw SheetSyncException('Sheet returned $status', retryable: true);
      }
      return text;
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        if (map['ok'] == true) return map;
        final error = map['error']?.toString() ?? 'Sync was rejected';
        throw SheetSyncException(
          error == 'unauthorized' ? 'The shared secret was rejected' : error,
          retryable: error != 'unauthorized',
        );
      }
    } on SheetSyncException {
      rethrow;
    } catch (_) {
      throw SheetSyncException('Sheet returned an unexpected response', retryable: true);
    }
    throw SheetSyncException('Sheet returned an unexpected response', retryable: true);
  }

  List<Map<String, Object?>> _productRows(Product product) {
    return [
      for (final variant in product.variants)
        {
          'variantId': variant.id,
          'productId': product.id,
          'name': product.name,
          'category': product.category,
          'unit': product.unit,
          'price': product.price,
          'costPrice': product.costPrice,
          'sku': variant.sku,
          'size': variant.size,
          'color': variant.color,
          'quantity': variant.quantity,
          'lowStock': variant.lowStockThreshold,
          'updatedAt': variant.updatedAt.toIso8601String(),
        },
    ];
  }

  Map<String, Object?> _salePayload(Sale sale) {
    return {
      'id': sale.id,
      'receiptNumber': sale.receiptNumber,
      'createdAt': sale.createdAt.toIso8601String(),
      'paymentMethod': sale.paymentMethod.label,
      'discountType': sale.discountType.dbValue,
      'discountValue': sale.discountValue,
      'discountAmount': sale.discountAmount,
      'subtotal': sale.subtotal,
      'total': sale.total,
      'lines': [
        for (var i = 0; i < sale.items.length; i++)
          {
            'id': sale.items[i].id,
            'variantId': sale.items[i].stockId,
            'name': sale.items[i].name,
            'sku': sale.items[i].sku,
            'size': sale.items[i].size,
            'color': sale.items[i].color,
            'unitPrice': sale.items[i].unitPrice,
            'quantity': sale.items[i].quantity,
            'lineSubtotal': sale.items[i].subtotal,
            'itemDiscountType': sale.items[i].discountType.dbValue,
            'itemDiscountValue': sale.items[i].discountValue,
            'itemDiscount': sale.items[i].discountAmount,
            'includeSaleTotals': i == 0,
          },
      ],
    };
  }

  Map<String, Object?> _saleMovement(Sale sale, SaleLineItem line) {
    return {
      'id': 'sale-${line.id}',
      'createdAt': sale.createdAt.toIso8601String(),
      'variantId': line.stockId,
      'sku': line.sku,
      'name': line.name,
      'size': line.size,
      'color': line.color,
      'delta': -line.quantity,
      'reason': 'sale',
      'saleId': sale.receiptNumber.isEmpty ? sale.id : sale.receiptNumber,
      'sourceId': line.id,
    };
  }

  Map<String, Object?> _adjustmentMovement(StockAdjustment adjustment, AdjustmentLine line, String receiptNumber) {
    final inbound = line.direction == AdjustmentDirection.inbound;
    final reason = inbound
        ? (adjustment.isExchange ? 'exchange_in' : 'return')
        : 'exchange_out';
    return {
      'id': 'adj-${line.id}',
      'createdAt': adjustment.createdAt.toIso8601String(),
      'variantId': line.stockId,
      'sku': line.sku,
      'name': line.name,
      'size': line.size,
      'color': line.color,
      'delta': inbound ? line.quantity : -line.quantity,
      'reason': reason,
      'saleId': receiptNumber.isEmpty ? adjustment.saleId : receiptNumber,
      'sourceId': line.id,
    };
  }

  List<Map<String, Object?>> _voidMovements(Map<String, Object?> row) {
    final payload = jsonDecode(row['payload'] as String);
    if (payload is! Map || payload['movements'] is! List) return [];
    return [
      for (final item in payload['movements'] as List)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  }

  List<Map<String, Object?>> _productList(dynamic raw) {
    if (raw is! List) return [];
    return [
      for (final item in raw)
        if (item is Map)
          {
            'variantId': item['variantId']?.toString() ?? '',
            'productId': item['productId']?.toString() ?? '',
            'name': item['name']?.toString() ?? '',
            'category': item['category']?.toString() ?? '',
            'unit': item['unit']?.toString() ?? '',
            'sku': item['sku']?.toString() ?? '',
            'size': item['size']?.toString() ?? '',
            'color': item['color']?.toString() ?? '',
            'price': _asDouble(item['price']),
            'costPrice': _asDouble(item['costPrice']),
            'quantity': _asInt(item['quantity']),
            'lowStock': _asInt(item['lowStock']),
            'updatedAt': item['updatedAt']?.toString() ?? '',
          },
    ];
  }

  Set<String> _idSet(dynamic raw) {
    if (raw is! List) return {};
    return raw.map((id) => id.toString()).toSet();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
