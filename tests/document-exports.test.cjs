const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const XLSX = require('../public/js/vendor/xlsx.full.min.js');
const context = vm.createContext({ XLSX, formatDocumentStatus: (_, status) => status,
  formatDateTime: value => value, money: value => `R$ ${Number(value).toFixed(2)}`,
  escapeHtml: value => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;') });
vm.runInContext(fs.readFileSync('public/js/commercial_prices.js', 'utf8'), context);
vm.runInContext(fs.readFileSync('public/js/document_exports.js', 'utf8'), context);
const item = { item: 1, codigo: '00123', descricao: '<img src=x onerror=alert(1)>', quantidade: 2,
  desconto_percentual: 10, preco_sem_imposto_unitario: 90, imposto_unitario: 27,
  preco_final_unitario: 117, total_item: 234,
  fiscal_details: { discount_basis: 'BASE_PRICE', original_base_price: 100, icms_st_amount: 18, ipi_amount: 9 } };
const row = { id: 'id', numero_pedido: 'P/1', numero_cotacao: 'C/1', cliente: '=1+1',
  status: 'NOVO', total: 234, order_items: [item], quotation_items: [item] };

test('orders and quotations export saved base, discounted taxes and exact row/header totals', () => {
  for (const kind of ['pedidos', 'cotacoes']) {
    const data = context.buildCommercialExport(kind, row);
    assert.deepEqual(Array.from(data.rows[0]), ['00123', item.descricao, 2, 100, 10, 90, 18, 9, 0, 117, 234]);
    assert.equal(data.total, 234);
    assert.doesNotMatch(data.filename, /\//);
  }
});
test('legacy snapshots do not fabricate tax composition', () => {
  const data = context.buildCommercialExport('pedidos', { ...row, order_items: [{ ...item, fiscal_details: {} }] });
  assert.equal(data.rows[0][3], null);
  assert.equal(data.rows[0][6], null);
  assert.equal(data.rows[0][7], null);
  assert.equal(data.rows[0][10], 234);
});
test('print escapes all customer/item markup and preserves document number and total', () => {
  const html = context.renderCommercialPrint(context.buildCommercialExport('pedidos', row));
  assert.doesNotMatch(html, /<img|<script/);
  assert.match(html, /&lt;img/);
  assert.match(html, /R\$ 234.00/);
  assert.match(html, /A4 landscape/);
});
test('XLSX round trip preserves codes as text, numbers and untrusted strings without formulas', () => {
  const data = context.buildCommercialExport('pedidos', row);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, context.commercialExportSheet(data), 'Documento');
  const result = XLSX.read(XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' }), { type: 'buffer' });
  const sheet = result.Sheets.Documento;
  const start = data.details.length + 3;
  assert.equal(sheet[`A${start}`].v, '00123');
  assert.equal(sheet[`A${start}`].t, 's');
  assert.equal(sheet[`K${start}`].v, 234);
  assert.equal(sheet.B4.v, '=1+1');
  assert.equal(sheet.B4.f, undefined);
});
test('export integration blocks unsaved/busy documents and reads one RLS-protected record', () => {
  const source = fs.readFileSync('public/js/document_exports.js', 'utf8');
  assert.match(source, /EditDirty/);
  assert.match(source, /documentStatusRequests.has/);
  assert.match(source, /\.eq\('id', id\)\.single\(\)/);
  assert.doesNotMatch(source, /select\(['"]\*/);
  const html = fs.readFileSync('public/app.html', 'utf8');
  assert.ok(html.indexOf('document_exports.js?v=') < html.indexOf('js/quotes.js?v='));
});
