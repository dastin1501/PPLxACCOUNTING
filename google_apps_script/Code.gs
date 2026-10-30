/**
 * POS sheet sync.
 *
 * 1. Paste this file into Extensions > Apps Script on the Google Sheet.
 * 2. Change SECRET to a long private password. Use the same value in the POS app.
 * 3. Run setupSheets once and allow the permissions.
 * 4. Deploy > New deployment > Web app.
 *    Execute as: Me
 *    Who has access: Anyone
 * 5. Copy the web app URL (it ends in /exec) into the POS app.
 *
 * The tablet is the source of truth. Each sync rewrites product quantities
 * from the tablet. Sales and stock movements are appended once; the same
 * line or movement id sent again is updated in place, not duplicated.
 * Sale ID on the sheet is the receipt number from the app (S-0001).
 * SKUs stay text, so 00001 is not stored as 1.
 * New product rows you add on the sheet, with a blank Variant ID, are
 * given an id and downloaded by the tablet.
 */
var SECRET = 'CHANGE_ME';

var PRODUCTS = 'Products';
var SALES = 'Sales';
var MOVEMENTS = 'StockMovements';

var PRODUCT_HEADERS = [
  'Variant ID', 'Product ID', 'Name', 'Category', 'Unit', 'Price', 'Cost Price',
  'SKU', 'Size', 'Color', 'Quantity', 'Low Stock', 'Updated At'
];
var SALE_HEADERS = [
  'Line ID', 'Sale ID', 'Receipt Number', 'Date', 'Payment Method', 'Name', 'SKU', 'Size', 'Color',
  'Variant ID', 'Unit Price', 'Quantity', 'Line Subtotal', 'Discount Type',
  'Discount Value', 'Discount Amount', 'Sale Subtotal', 'Sale Total'
];
var MOVEMENT_HEADERS = [
  'Movement ID', 'Date', 'Variant ID', 'SKU', 'Name', 'Size', 'Color', 'Delta',
  'Reason', 'Sale ID', 'Source ID'
];

// These columns must stay text. Sheets would otherwise turn 00001 into 1.
var TEXT_HEADERS = {
  'Variant ID': true,
  'Product ID': true,
  'SKU': true,
  'Line ID': true,
  'Sale ID': true,
  'Receipt Number': true,
  'Movement ID': true,
  'Source ID': true,
  'Size': true,
  'Color': true
};

function setupSheets() {
  var ss = SpreadsheetApp.getActive();
  ensureSheet(ss, PRODUCTS, PRODUCT_HEADERS);
  ensureSheet(ss, SALES, SALE_HEADERS);
  ensureSheet(ss, MOVEMENTS, MOVEMENT_HEADERS);
}

function ensureSheet(ss, name, headers) {
  var sheet = ss.getSheetByName(name);
  if (!sheet) sheet = ss.insertSheet(name);
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold');
    applyTextColumns(sheet);
    return;
  }
  var map = headerIndex(sheet);
  headers.forEach(function (header) {
    if (map[header] !== undefined) return;
    var col = Math.max(sheet.getLastColumn(), 0) + 1;
    sheet.getRange(1, col).setValue(header).setFontWeight('bold');
    map[header] = col - 1;
  });
  applyTextColumns(sheet);
}

function doGet(e) {
  try {
    if (String(SECRET) === 'CHANGE_ME') {
      return json({ ok: false, error: 'Set SECRET in the Apps Script, then deploy a new version' });
    }
    var secret = e && e.parameter ? e.parameter.secret : '';
    if (!authorized(secret)) return json({ ok: false, error: 'unauthorized' });
    setupSheets();
    var lock = LockService.getScriptLock();
    lock.waitLock(20000);
    try {
      return json({ ok: true, products: readProducts() });
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

function doPost(e) {
  try {
    if (String(SECRET) === 'CHANGE_ME') {
      return json({ ok: false, error: 'Set SECRET in the Apps Script, then deploy a new version' });
    }
    var body = JSON.parse(e.postData.contents);
    if (!authorized(body.secret)) return json({ ok: false, error: 'unauthorized' });
    setupSheets();
    var lock = LockService.getScriptLock();
    lock.waitLock(20000);
    try {
      upsertProducts(body.products || []);
      var saleIds = upsertSales(body.sales || []);
      var movementIds = upsertMovements(body.movements || []);
      return json({ ok: true, saleIds: saleIds, movementIds: movementIds });
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

function authorized(secret) {
  return String(secret || '') !== '' && String(secret) === String(SECRET);
}

function readProducts() {
  var sheet = SpreadsheetApp.getActive().getSheetByName(PRODUCTS);
  var map = headerIndex(sheet);
  var last = sheet.getLastRow();
  if (last < 2) return [];
  var width = Math.max(sheet.getLastColumn(), 1);
  var values = sheet.getRange(2, 1, last - 1, width).getValues();
  var out = [];
  for (var i = 0; i < values.length; i++) {
    var row = values[i];
    var sheetRow = i + 2;
    var variantId = cell(row, map, 'Variant ID');
    var productId = cell(row, map, 'Product ID');
    var name = cell(row, map, 'Name');
    var sku = cell(row, map, 'SKU');
    if (!variantId && !productId && !name && !sku) continue;
    if (!variantId) {
      variantId = Utilities.getUuid();
      writeCell(sheet, sheetRow, map['Variant ID'], variantId);
    }
    if (!productId) {
      productId = Utilities.getUuid();
      writeCell(sheet, sheetRow, map['Product ID'], productId);
    }
    out.push({
      variantId: variantId,
      productId: productId,
      name: name,
      category: cell(row, map, 'Category'),
      unit: cell(row, map, 'Unit'),
      price: num(row, map, 'Price'),
      costPrice: num(row, map, 'Cost Price'),
      sku: sku,
      size: cell(row, map, 'Size'),
      color: cell(row, map, 'Color'),
      quantity: num(row, map, 'Quantity'),
      lowStock: num(row, map, 'Low Stock'),
      updatedAt: cell(row, map, 'Updated At')
    });
  }
  return out;
}

function upsertProducts(products) {
  var sheet = SpreadsheetApp.getActive().getSheetByName(PRODUCTS);
  var found = rowIndex(sheet, 'Variant ID');
  products.forEach(function (p) {
    var id = String(p.variantId || '').trim();
    if (!id) return;
    writeByHeaders(sheet, found.index[id] || null, found.map, {
      'Variant ID': id,
      'Product ID': p.productId || '',
      'Name': p.name || '',
      'Category': p.category || '',
      'Unit': p.unit || '',
      'Price': p.price || 0,
      'Cost Price': p.costPrice || 0,
      'SKU': p.sku || '',
      'Size': p.size || '',
      'Color': p.color || '',
      'Quantity': p.quantity || 0,
      'Low Stock': p.lowStock || 0,
      'Updated At': p.updatedAt || ''
    });
    if (!found.index[id]) found.index[id] = sheet.getLastRow();
  });
}

function sheetSaleId(sale) {
  var receipt = String(sale.receiptNumber || '').trim();
  return receipt || String(sale.id || '');
}

function upsertSales(sales) {
  var sheet = SpreadsheetApp.getActive().getSheetByName(SALES);
  var found = rowIndex(sheet, 'Line ID');
  var accepted = [];
  sales.forEach(function (sale) {
    var saleId = sheetSaleId(sale);
    (sale.lines || []).forEach(function (line) {
      var id = String(line.id || '').trim();
      if (!id) return;
      if (found.index[id]) {
        writeByHeaders(sheet, found.index[id], found.map, {
          'Sale ID': saleId,
          'Receipt Number': sale.receiptNumber || '',
          'SKU': line.sku || ''
        });
        return;
      }
      writeByHeaders(sheet, null, found.map, {
        'Line ID': id,
        'Sale ID': saleId,
        'Receipt Number': sale.receiptNumber || '',
        'Date': sale.createdAt || '',
        'Payment Method': sale.paymentMethod || '',
        'Name': line.name || '',
        'SKU': line.sku || '',
        'Size': line.size || '',
        'Color': line.color || '',
        'Variant ID': line.variantId || '',
        'Unit Price': line.unitPrice || 0,
        'Quantity': line.quantity || 0,
        'Line Subtotal': line.lineSubtotal || 0,
        'Discount Type': sale.discountType || '',
        'Discount Value': sale.discountValue || 0,
        'Discount Amount': sale.discountAmount || 0,
        'Sale Subtotal': sale.subtotal || 0,
        'Sale Total': sale.total || 0
      });
      found.index[id] = sheet.getLastRow();
    });
    if (sale.id) accepted.push(sale.id);
  });
  return accepted;
}

function upsertMovements(movements) {
  var sheet = SpreadsheetApp.getActive().getSheetByName(MOVEMENTS);
  var found = rowIndex(sheet, 'Movement ID');
  var accepted = [];
  movements.forEach(function (m) {
    var id = String(m.id || '').trim();
    if (!id) return;
    accepted.push(id);
    if (found.index[id]) {
      writeByHeaders(sheet, found.index[id], found.map, {
        'SKU': m.sku || '',
        'Sale ID': m.saleId || ''
      });
      return;
    }
    writeByHeaders(sheet, null, found.map, {
      'Movement ID': id,
      'Date': m.createdAt || '',
      'Variant ID': m.variantId || '',
      'SKU': m.sku || '',
      'Name': m.name || '',
      'Size': m.size || '',
      'Color': m.color || '',
      'Delta': m.delta || 0,
      'Reason': m.reason || '',
      'Sale ID': m.saleId || '',
      'Source ID': m.sourceId || ''
    });
    found.index[id] = sheet.getLastRow();
  });
  return accepted;
}

function headerIndex(sheet) {
  var lastCol = Math.max(sheet.getLastColumn(), 1);
  var headers = sheet.getRange(1, 1, 1, lastCol).getValues()[0];
  var map = {};
  headers.forEach(function (header, index) {
    var key = String(header || '').trim();
    if (key) map[key] = index;
  });
  return map;
}

function rowIndex(sheet, idHeader) {
  var map = headerIndex(sheet);
  var index = {};
  var last = sheet.getLastRow();
  if (last >= 2 && map[idHeader] !== undefined) {
    var ids = sheet.getRange(2, map[idHeader] + 1, last - 1, 1).getValues();
    ids.forEach(function (row, i) {
      var id = String(row[0] || '').trim();
      if (id) index[id] = i + 2;
    });
  }
  return { map: map, index: index };
}

function applyTextColumns(sheet) {
  var map = headerIndex(sheet);
  var height = Math.max(sheet.getMaxRows(), 2);
  Object.keys(TEXT_HEADERS).forEach(function (header) {
    if (map[header] === undefined) return;
    sheet.getRange(1, map[header] + 1, height, 1).setNumberFormat('@');
  });
}

function writeByHeaders(sheet, rowNumber, map, valuesByHeader) {
  var width = Math.max(sheet.getLastColumn(), 1);
  var row;
  if (!rowNumber) {
    row = [];
    for (var i = 0; i < width; i++) row.push('');
    rowNumber = sheet.getLastRow() + 1;
  } else {
    row = sheet.getRange(rowNumber, 1, 1, width).getValues()[0];
  }
  Object.keys(valuesByHeader).forEach(function (header) {
    if (map[header] === undefined) return;
    var value = valuesByHeader[header];
    if (TEXT_HEADERS[header]) {
      value = value === null || value === undefined ? '' : String(value);
      sheet.getRange(rowNumber, map[header] + 1).setNumberFormat('@');
    }
    row[map[header]] = value;
  });
  sheet.getRange(rowNumber, 1, 1, width).setValues([row]);
}

function writeCell(sheet, rowNumber, columnIndex, value) {
  if (columnIndex === undefined) return;
  sheet.getRange(rowNumber, columnIndex + 1).setValue(value);
}

function cell(row, map, header) {
  if (map[header] === undefined) return '';
  var value = row[map[header]];
  if (value === null || value === undefined || value === '') return '';
  if (Object.prototype.toString.call(value) === '[object Date]') {
    return Utilities.formatDate(value, Session.getScriptTimeZone(), "yyyy-MM-dd'T'HH:mm:ss");
  }
  return String(value).trim();
}

function num(row, map, header) {
  var raw = cell(row, map, header);
  var parsed = parseFloat(raw);
  return isNaN(parsed) ? 0 : parsed;
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
