const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const XLSX = require('../public/js/vendor/xlsx.full.min.js');
const { jsPDF } = require('../public/js/vendor/jspdf.umd.min.js');
require('../public/js/vendor/jspdf.plugin.autotable.min.js').applyPlugin(jsPDF);
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
test('direct PDF is landscape, contains literal text and uses exact saved totals', () => {
  const pdf = context.buildCommercialPdf(context.buildCommercialExport('pedidos', row), jsPDF);
  assert.ok(pdf.internal.pageSize.getWidth() > pdf.internal.pageSize.getHeight());
  assert.equal(pdf.getNumberOfPages(), 1);
  assert.equal(pdf.lastAutoTable.body[0].cells[0].raw, '00123');
  assert.equal(pdf.lastAutoTable.body[0].cells[1].raw, item.descricao);
  assert.equal(pdf.lastAutoTable.foot[0].cells[10].raw, 'R$ 234.00');
  assert.match(pdf.output(), /^%PDF-/);
});
test('large PDFs paginate horizontally without dropping items or repeating the final total', () => {
  const data = context.buildCommercialExport('cotacoes', row);
  data.rows = Array.from({ length: 140 }, (_, index) => [String(index).padStart(5, '0'),
    'CX. DIRECAO HIDRAULICA - descricao com aplicacao e embalagem de duas pecas', 2, 100, 10, 90, 18, 9, 0, 117, 234]);
  const pdf = context.buildCommercialPdf(data, jsPDF);
  assert.ok(pdf.getNumberOfPages() > 1);
  assert.equal(pdf.lastAutoTable.body.length, 140);
  assert.equal(pdf.lastAutoTable.settings.showFoot, 'lastPage');
  const pageWidth = pdf.internal.pageSize.getWidth();
  for (const tableRow of pdf.lastAutoTable.body) {
    for (const cell of Object.values(tableRow.cells)) assert.ok(cell.x + cell.width <= pageWidth - 11.9);
  }
});
test('PDF loads fixed local libraries only on demand and never opens the print dialog', () => {
  const source = fs.readFileSync('public/js/document_exports.js', 'utf8');
  assert.match(source, /jspdf.umd.min.js\?v=4.2.1/);
  assert.match(source, /jspdf.plugin.autotable.min.js\?v=5.0.9/);
  assert.match(source, /returnPromise: true/);
  assert.doesNotMatch(source, /window.open|\.print\(|document.write/);
  const html = fs.readFileSync('public/app.html', 'utf8');
  assert.doesNotMatch(html, /<script[^>]+src="[^\"]*vendor\/jspdf/);
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
