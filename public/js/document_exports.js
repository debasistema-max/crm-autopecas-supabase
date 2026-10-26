function buildCommercialExport(kind, row) {
  const order = kind === 'pedidos';
  const title = order ? 'Pedido de venda' : 'Cotacao de venda';
  const number = row[order ? 'numero_pedido' : 'numero_cotacao'] || row.id;
  const headers = ['Codigo', 'Descricao', 'Quantidade', 'Base unit.', 'Desconto %',
    'Base c/ desconto unit.', 'ST unit.', 'IPI unit.', 'Outros unit.', 'Final unit.', 'Total'];
  const numeric = value => value == null || !Number.isFinite(Number(value)) ? null : Number(value);
  // Export persisted amounts, never reprice a historical document with today's rules.
  const items = (row[order ? 'order_items' : 'quotation_items'] || []).slice()
    .sort((a, b) => Number(a.item || 0) - Number(b.item || 0));
  const rows = items.map(item => {
    const fiscal = item.fiscal_details || {};
    const baseDiscount = fiscal.discount_basis === 'BASE_PRICE';
    const st = baseDiscount ? numeric(fiscal.icms_st_amount) : null;
    const ipi = baseDiscount ? numeric(fiscal.ipi_amount) : null;
    const taxes = numeric(item.imposto_unitario);
    return [String(item.codigo || ''), String(item.descricao || ''), numeric(item.quantidade),
      baseDiscount ? numeric(fiscal.original_base_price) : null,
      numeric(item.desconto_percentual), baseDiscount ? numeric(item.preco_sem_imposto_unitario) : null,
      st, ipi, taxes != null && st != null && ipi != null ? commercialRound(taxes - st - ipi) : null,
      numeric(item.preco_final_unitario), numeric(item.total_item)];
  });
  const details = [
    [title, String(number)], ['Status', formatDocumentStatus(kind, row.status)],
    ['Data', formatDateTime(row.created_at || row.data_hora)],
    ['Cliente', row.cliente || ''], ['CPF/CNPJ', row.cnpj || ''],
    ['Codigo SAP', row.codigo_sap_cliente || ''], ['Vendedor', row.vendedor || ''],
    ['Filial de origem', row.regiao || ''], ['Estado de destino', row.billing_uf || ''],
    ['Endereco', row.endereco || ''], ['Telefone', row.telefone || ''],
    ['Pagamento', row.prazo || ''], ['Transportadora', row.transportadora || ''],
    ['Observacoes', row.observacao || '']
  ];
  return { title, number, headers, rows, details, total: numeric(row.total),
    filename: `${order ? 'pedido' : 'cotacao'}-${String(number).replace(/[^a-zA-Z0-9_-]/g, '_')}` };
}

function commercialExportSheet(data) {
  const rows = [...data.details, [], data.headers, ...data.rows, [], ['Total do documento', data.total]];
  const sheet = XLSX.utils.aoa_to_sheet(rows);
  sheet['!cols'] = [18, 52, 12, 16, 14, 22, 16, 16, 16, 16, 18].map(wch => ({ wch }));
  const start = data.details.length + 2;
  data.rows.forEach((row, index) => {
    row.forEach((value, col) => {
      const cell = sheet[XLSX.utils.encode_cell({ r: start + index, c: col })];
      if (cell && typeof value === 'number') cell.z = col === 2 ? '0.####' : '#,##0.00';
    });
  });
  sheet['!autofilter'] = { ref: XLSX.utils.encode_range({ r: start - 1, c: 0 },
    { r: start - 1 + data.rows.length, c: data.headers.length - 1 }) };
  return sheet;
}

function renderCommercialPrint(data) {
  const text = value => escapeHtml(String(value ?? 'Nao informado'));
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
    <title>${text(data.filename)}</title><style>
    @page{size:A4 landscape;margin:12mm}body{font:12px Arial;color:#111;margin:20px}
    h1{font-size:20px}dl{display:grid;grid-template-columns:160px 1fr;gap:5px}dt{font-weight:bold}dd{margin:0;white-space:pre-wrap;overflow-wrap:anywhere}
    table{width:100%;border-collapse:collapse;font-size:10px}th,td{padding:7px 4px;border-bottom:1px solid #ccc;text-align:right;overflow-wrap:anywhere}
    th:first-child,td:first-child,th:nth-child(2),td:nth-child(2){text-align:left}thead{display:table-header-group}tr{break-inside:avoid}
    .total{text-align:right;font-size:16px;font-weight:bold}
    </style></head><body><h1>${text(data.title)} - ${text(data.number)}</h1>
    <dl>${data.details.slice(1).map(([label, value]) => `<dt>${text(label)}</dt><dd>${text(value)}</dd>`).join('')}</dl>
    <table><thead><tr>${data.headers.map(h => `<th>${text(h)}</th>`).join('')}</tr></thead>
    <tbody>${data.rows.map(row => `<tr>${row.map((value, col) => `<td>${text(value == null ? 'Nao informado' : col < 3 ? value : col === 4 ? value + '%' : money(value))}</td>`).join('')}</tr>`).join('')}</tbody></table>
    <p class="total">Total do documento: ${text(data.total == null ? 'Nao informado' : money(data.total))}</p>
    <p>Valores preservados do documento salvo. Campos sem composicao registrada: Nao informado. Documento comercial, sem valor fiscal.</p>
    </body></html>`;
}

async function exportSavedCommercialDocument(kind, id, format) {
  const message = document.getElementById(`${kind}EditMessage`);
  const buttons = ['Pdf', 'Xlsx'].map(name => document.getElementById(`${kind}${name}Button`));
  if (buttons.some(button => button?.disabled)) return;
  let printWindow;
  try {
    if (!['pedidos', 'cotacoes'].includes(kind) || !['pdf', 'xlsx'].includes(format)) throw new Error('Exportacao invalida.');
    if (window[`${kind}EditDirty`]) throw new Error('Salve as alteracoes dos itens antes de exportar.');
    if (document.getElementById(`${kind}EditSaveButton`)?.disabled || documentStatusRequests.has(kind)) {
      throw new Error('Aguarde a conclusao da operacao antes de exportar.');
    }
    if (format === 'pdf') {
      printWindow = window.open('', '_blank');
      if (!printWindow) throw new Error('Permita abrir janelas para salvar o PDF.');
      printWindow.opener = null;
      printWindow.document.body.textContent = 'Preparando documento...';
    }
    buttons.forEach(button => { if (button) button.disabled = true; });
    message.textContent = 'Preparando exportacao...';
    const order = kind === 'pedidos';
    const itemColumns = 'item,codigo,descricao,quantidade,desconto_percentual,preco_sem_imposto_unitario,imposto_unitario,preco_final_unitario,total_item,fiscal_details';
    const { data: row, error } = await supabaseClient.from(order ? 'orders' : 'quotations')
      .select(`id,${order ? 'numero_pedido' : 'numero_cotacao'},status,created_at,data_hora,cliente,cnpj,codigo_sap_cliente,vendedor,regiao,billing_uf,endereco,telefone,prazo,transportadora,observacao,total,${order ? 'order_items' : 'quotation_items'}(${itemColumns})`)
      .eq('id', id).single();
    if (error) throw error;
    const data = buildCommercialExport(kind, row);
    if (format === 'xlsx') {
      if (typeof XLSX === 'undefined') throw new Error('Biblioteca XLSX indisponivel. Atualize a pagina e tente novamente.');
      const workbook = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(workbook, commercialExportSheet(data), 'Documento');
      XLSX.writeFile(workbook, `${data.filename}.xlsx`, { compression: true });
      message.textContent = 'Planilha gerada.';
    } else {
      if (printWindow.closed) throw new Error('A janela de impressao foi fechada. Tente novamente.');
      printWindow.document.open();
      printWindow.document.write(renderCommercialPrint(data));
      printWindow.document.close();
      printWindow.focus();
      printWindow.print();
      message.textContent = 'Selecione Salvar como PDF na janela de impressao.';
    }
    message.style.color = 'var(--success)';
  } catch (error) {
    if (printWindow && !printWindow.closed) printWindow.close();
    message.style.color = 'var(--accent)';
    message.textContent = error.message || 'Nao foi possivel exportar o documento.';
  } finally {
    buttons.forEach(button => { if (button) button.disabled = false; });
  }
}
