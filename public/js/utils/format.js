function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function money(value) {
  return Number(value || 0).toLocaleString('pt-BR', {
    style: 'currency',
    currency: APP_CONFIG.currency
  });
}

function spreadsheetSafeCsvText(value) {
  const text = String(value ?? '');
  if (typeof value === 'number' && Number.isFinite(value)) return text;
  // CSVs are for spreadsheet viewing, not raw machine interchange. Keep the
  // protective tab inside a quoted field; quoting alone does not stop formulas.
  const formula = /^['\s\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2060-\u206f]*[=+\-@\uff1d\uff0b\uff0d\uff20]/u;
  return formula.test(text) || /^[\t\r\n]/.test(text) ? `\t${text}` : text;
}

function csvValue(value) {
  return `"${spreadsheetSafeCsvText(value).replaceAll('"', '""')}"`;
}

function csvCell(value) {
  return csvValue(value);
}

function downloadCsv(filename, rows) {
  const headers = Array.isArray(rows[0]) ? null : Object.keys(rows[0] || {});
  const csv = headers
    ? [headers.map(csvValue).join(';')].concat(rows.map((row) => headers.map((header) => csvValue(row[header])).join(';'))).join('\r\n')
    : rows.map((row) => row.map(csvValue).join(';')).join('\n');
  const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
function formatVehicleTypes(types) {
  const labels = { LEVE: 'Leve', UTILITARIO: 'Utilitario', PESADO: 'Pesado', NAO_CLASSIFICADO: 'Nao classificado' };
  return Array.isArray(types) && types.length ? [...new Set(types)].map((type) => labels[type] || 'Nao classificado').join(' / ') : 'Nao classificado';
}

function vehicleMakerLabel(value) {
  return value === '__SEM_MONTADORA__' ? 'Não informada' : value === 'UNIVERSAL' ? 'Aplicação universal' : String(value || '');
}

function formatVehicleMakers(makers) {
  return Array.isArray(makers) && makers.length
    ? [...new Set(makers.filter((maker) => typeof maker === 'string' && maker.trim()))].map(vehicleMakerLabel).join(' / ') || 'Não informada'
    : 'Não informada';
}
