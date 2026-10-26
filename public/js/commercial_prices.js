function commercialRound(value, places = 6) {
  const number = Number(value);
  if (!Number.isFinite(number)) return number;
  const [coefficient, exponent = '0'] = String(Math.abs(number)).split('e');
  const shifted = Number(`${coefficient}e${Number(exponent) + places}`);
  return Math.sign(number) * Number(`${Math.round(shifted)}e-${places}`);
}

// Preview only. The transactional RPC independently applies the same discount
// to the authoritative, approved route snapshot before saving.
function calculateDocumentItemAmounts(item) {
  const saved = item.fiscal_details;
  const source = saved?.undiscounted_price || saved;
  const discount = Number(item.desconto_percentual || 0);
  const quantity = Number(item.quantidade || 0);
  const base = Number(source?.base_price);
  const ipi = Number(source?.ipi_amount ?? source?.tax_breakdown?.ipi ?? NaN);
  const st = Number(source?.icms_st_amount ?? source?.tax_breakdown?.icms_st ?? NaN);
  const taxes = Number(source?.total_taxes ?? NaN);
  const expenses = Number(source?.total_expenses || 0);
  const available = ['OK', 'OK_SEM_ST'].includes(source?.status)
    && [base, ipi, st, taxes, expenses, discount, quantity].every(Number.isFinite)
    && base > 0 && Math.min(ipi, st, taxes, expenses, discount, quantity) >= 0 && discount <= 100
    && source?.final_price != null
    && Math.abs(Number(source.final_price) - base - taxes - expenses) <= 0.020001;
  if (!available) {
    const finalUnit = commercialRound(Number(item.preco || 0) * (1 - discount / 100), 4);
    return { available: false, base: null, discountedBase: null, discount: null,
      ipi: null, st: null, other: null, finalUnit, total: commercialRound(finalUnit * quantity, 2) };
  }
  const factor = 1 - discount / 100;
  const discountedBase = commercialRound(base * factor);
  const discountedTaxes = commercialRound(taxes * factor);
  const discountedExpenses = commercialRound(expenses * factor);
  const discountedIpi = commercialRound(ipi * factor);
  const discountedSt = commercialRound(st * factor);
  const finalUnit = commercialRound(discountedBase + discountedTaxes + discountedExpenses, 4);
  return { available: true, base, discountedBase, discount: commercialRound(base - discountedBase),
    ipi: discountedIpi, st: discountedSt,
    other: commercialRound(discountedTaxes - discountedIpi - discountedSt + discountedExpenses),
    finalUnit, total: commercialRound(finalUnit * quantity, 2) };
}

function getDocumentTaxTotals(items) {
  const totals = { base: 0, discount: 0, discountedBase: 0, ipi: 0, st: 0, other: 0, total: 0, incomplete: false };
  items.forEach((item) => {
    const amounts = calculateDocumentItemAmounts(item);
    totals.incomplete ||= !amounts.available;
    ['base', 'discount', 'discountedBase', 'ipi', 'st', 'other'].forEach((key) => {
      totals[key] += Number(amounts[key] || 0) * Number(item.quantidade || 0);
    });
    totals.total += amounts.total;
  });
  return totals;
}

function commercialAmount(value) {
  return value == null ? 'Indisponivel' : money(value);
}

function renderDocumentTaxTotals(items) {
  const totals = getDocumentTaxTotals(items);
  return `<div class="commercial-tax-totals">
    ${totals.incomplete ? '<small>Composicao fiscal indisponivel para um ou mais itens.</small>' : ''}
    <div><span>Preco base</span><strong>${commercialAmount(totals.incomplete ? null : totals.base)}</strong></div>
    <div><span>Desconto sobre a base</span><strong>${commercialAmount(totals.incomplete ? null : totals.discount)}</strong></div>
    <div><span>Base com desconto</span><strong>${commercialAmount(totals.incomplete ? null : totals.discountedBase)}</strong></div>
    <div><span>ST</span><strong>${commercialAmount(totals.incomplete ? null : totals.st)}</strong></div>
    <div><span>IPI</span><strong>${commercialAmount(totals.incomplete ? null : totals.ipi)}</strong></div>
    ${Math.abs(totals.other) >= 0.005 ? `<div><span>Outros componentes</span><strong>${money(totals.other)}</strong></div>` : ''}
    <div class="commercial-grand-total"><span>Total com impostos</span><strong>${money(totals.total)}</strong></div>
  </div>`;
}

function renderDocumentTaxCells(item, discountInput) {
  const amounts = calculateDocumentItemAmounts(item);
  return `<td>${commercialAmount(amounts.base)}</td>
    <td class="commercial-discount-cell">${discountInput}</td>
    <td>${commercialAmount(amounts.discountedBase)}</td>
    <td>${commercialAmount(amounts.st)}</td><td>${commercialAmount(amounts.ipi)}</td>
    <td>${money(amounts.finalUnit)}${Math.abs(amounts.other || 0) >= 0.005 ? `<small>Outros: ${money(amounts.other)}</small>` : ''}</td>
    <td>${money(amounts.total)}</td>`;
}
