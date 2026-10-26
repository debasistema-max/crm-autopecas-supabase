const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const context = vm.createContext({ money: value => `R$ ${Number(value).toFixed(2)}` });
vm.runInContext(fs.readFileSync('public/js/commercial_prices.js', 'utf8'), context);
const price = { status: 'OK', base_price: 100, ipi_amount: 10, icms_st_amount: 20,
  total_taxes: 30, total_expenses: 0, final_price: 130,
  tax_breakdown: { ipi: 10, icms_st: 20, icms_proprio: 12 } };
const item = (discount = 0, source = price) => ({ quantidade: 2, preco: source.final_price,
  desconto_percentual: discount, fiscal_details: source });

test('decimal rounding follows PostgreSQL for cent ties and tiny components', () => {
  assert.equal(context.commercialRound(1.005, 2), 1.01);
  assert.equal(context.commercialRound(-1.005, 2), -1.01);
  assert.equal(context.commercialRound(5e-7, 6), 0.000001);
});

test('discount changes the base, IPI, ST and total; own ICMS is not added again', () => {
  const result = context.calculateDocumentItemAmounts(item(10));
  assert.equal(result.base, 100);
  assert.equal(result.discountedBase, 90);
  assert.equal(result.discount, 10);
  assert.equal(result.ipi, 9);
  assert.equal(result.st, 18);
  assert.equal(result.other, 0);
  assert.equal(result.finalUnit, 117);
  assert.equal(result.total, 234);
});
test('SP IPI-only remains without ST', () => {
  const result = context.calculateDocumentItemAmounts(item(10, { ...price,
    status: 'OK_SEM_ST', icms_st_amount: 0, total_taxes: 10, final_price: 110 }));
  assert.equal(result.st, 0);
  assert.equal(result.ipi, 9);
  assert.equal(result.finalUnit, 99);
});
test('100 percent discount clears base and taxes; zero discount preserves source', () => {
  assert.equal(context.calculateDocumentItemAmounts(item(100)).total, 0);
  assert.equal(context.calculateDocumentItemAmounts(item()).total, 260);
});
test('saved discounted snapshot never applies the discount twice', () => {
  const snapshot = { ...price, base_price: 90, final_price: 117, ipi_amount: 9,
    icms_st_amount: 18, undiscounted_price: price, discount_basis: 'BASE_PRICE' };
  assert.equal(context.calculateDocumentItemAmounts(item(10, snapshot)).finalUnit, 117);
  assert.equal(context.calculateDocumentItemAmounts(item(20, snapshot)).finalUnit, 104);
});
test('extra components are preserved rather than silently omitted', () => {
  const result = context.calculateDocumentItemAmounts(item(10, { ...price, total_taxes: 35, total_expenses: 2, final_price: 137 }));
  assert.equal(result.other, 6.3);
  assert.equal(result.finalUnit, 123.3);
});
test('blocked, incomplete and malformed prices do not expose fabricated tax zeroes', () => {
  for (const source of [{ ...price, status: 'PRECO_FISCAL_INDISPONIVEL' },
    { ...price, ipi_amount: null, tax_breakdown: {} }, { ...price, final_price: 999 }]) {
    assert.equal(context.calculateDocumentItemAmounts(item(10, source)).available, false);
  }
  for (const discount of [-1, 101, Infinity]) {
    assert.equal(context.calculateDocumentItemAmounts(item(discount)).available, false);
  }
});
test('summary uses only the base for discount, with row-rounded totals', () => {
  const totals = context.getDocumentTaxTotals([item(10), item(0)]);
  assert.equal(totals.base, 400);
  assert.equal(totals.discount, 20);
  assert.equal(totals.st, 76);
  assert.equal(totals.ipi, 38);
  assert.equal(totals.total, 494);
});
test('shared markup labels tax components and preserves editable discount', () => {
  const html = context.renderDocumentTaxCells(item(10), '<input data-discount>');
  assert.match(html, /data-discount/);
  assert.match(context.renderDocumentTaxTotals([item(10)]), /Desconto sobre a base/);
});
test('migration only changes functions, protects internals and keeps legacy authorization', () => {
  const sql = fs.readFileSync('supabase/migrations/117_document_base_discount_taxes.sql', 'utf8');
  assert.doesNotMatch(sql, /drop table|truncate|alter table/i);
  assert.match(sql, /commercial_create_document_raw_117\(document_type,payload\)/);
  assert.match(sql, /commercial_update_document_items_raw_117\(document_type,payload\)/);
  assert.match(sql, /revoke all on function public.finalize_document_base_discount\(text,uuid\) from public,anon,authenticated/);
  assert.match(sql, /RECALCULAR_IMPOSTOS_DESCONTO_BASE/);
});
