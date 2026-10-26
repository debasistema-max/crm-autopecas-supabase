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

let commercialPdfLibraryPromise;

async function loadCommercialPdfLibrary() {
  if (!commercialPdfLibraryPromise) {
    // Load only when requested; XLSX, login and ordinary navigation pay no PDF download cost.
    commercialPdfLibraryPromise = (async () => {
      for (const source of ['js/vendor/jspdf.umd.min.js?v=4.2.1', 'js/vendor/jspdf.plugin.autotable.min.js?v=5.0.9']) {
        await new Promise((resolve, reject) => {
          const script = document.createElement('script');
          script.src = source;
          script.onload = resolve;
          script.onerror = () => { script.remove(); reject(new Error('Nao foi possivel carregar o gerador PDF. Tente novamente.')); };
          document.head.appendChild(script);
        });
      }
      if (!window.jspdf?.jsPDF?.API.autoTable) throw new Error('Gerador PDF indisponivel. Atualize a pagina.');
      return window.jspdf.jsPDF;
    })().catch(error => { commercialPdfLibraryPromise = null; throw error; });
  }
  return commercialPdfLibraryPromise;
}

function buildCommercialPdf(data, PdfConstructor) {
  const pdf = new PdfConstructor({ orientation: 'landscape', unit: 'mm', format: 'a4', compress: true });
  pdf.setProperties({ title: `${data.title} - ${data.number}`, subject: 'Documento comercial, sem valor fiscal' });
  const width = pdf.internal.pageSize.getWidth();
  const height = pdf.internal.pageSize.getHeight();
  const margin = 12;
  const text = value => String(value ?? 'Nao informado');
  const title = `${data.title} - ${data.number}`;
  pdf.setFont('helvetica', 'bold');
  pdf.setFontSize(17);
  const heading = pdf.splitTextToSize(title, width - margin * 2);
  pdf.text(heading, margin, 17);
  pdf.autoTable({
    startY: 20 + (heading.length - 1) * 7, margin: { left: margin, right: margin, top: 15, bottom: 15 },
    theme: 'plain', body: data.details.slice(1).filter(([, value]) => value !== '').map(([label, value]) => [label, text(value)]),
    styles: { font: 'helvetica', fontSize: 9, cellPadding: 1.2, overflow: 'linebreak', textColor: [25, 35, 40] },
    columnStyles: { 0: { cellWidth: 38, fontStyle: 'bold' }, 1: { cellWidth: width - margin * 2 - 38 } }
  });
  pdf.autoTable({
    startY: pdf.lastAutoTable.finalY + 6,
    margin: { left: margin, right: margin, top: 18, bottom: 18 },
    theme: 'striped', head: [data.headers.map((label, index) => index === 2 ? 'Qtde' : index === 4 ? 'Desc. %' : label)],
    body: data.rows.map(row => row.map((value, col) => value == null ? '-' : col < 3 ? text(value) : col === 4 ? `${value}%` : money(value))),
    foot: [[{ content: 'Total do documento', colSpan: 10, styles: { halign: 'right' } },
      data.total == null ? '-' : money(data.total)]], showFoot: 'lastPage',
    styles: { font: 'helvetica', fontSize: 8, cellPadding: 1.6, overflow: 'linebreak', halign: 'right', valign: 'middle' },
    headStyles: { fillColor: [25, 72, 62], textColor: [255, 255, 255], fontStyle: 'bold' },
    footStyles: { fillColor: [230, 239, 236], textColor: [20, 40, 30], fontStyle: 'bold' },
    columnStyles: { 0: { cellWidth: 25, halign: 'left' }, 1: { cellWidth: 68, halign: 'left' },
      2: { cellWidth: 13 }, 3: { cellWidth: 22 }, 4: { cellWidth: 15 }, 5: { cellWidth: 24 },
      6: { cellWidth: 20 }, 7: { cellWidth: 20 }, 8: { cellWidth: 20 }, 9: { cellWidth: 22 }, 10: { cellWidth: 24 } },
    rowPageBreak: 'avoid'
  });
  const pageCount = pdf.getNumberOfPages();
  for (let page = 1; page <= pageCount; page++) {
    pdf.setPage(page);
    pdf.setFont('helvetica', 'normal');
    pdf.setFontSize(7);
    pdf.setTextColor(70);
    pdf.text('Documento comercial, sem valor fiscal. Valores salvos; composicao nao registrada: -.', margin, height - 8);
    pdf.text(`${page} / ${pageCount}`, width - margin, height - 8, { align: 'right' });
  }
  return pdf;
}

async function exportSavedCommercialDocument(kind, id, format) {
  const message = document.getElementById(`${kind}EditMessage`);
  const buttons = ['Pdf', 'Xlsx'].map(name => document.getElementById(`${kind}${name}Button`));
  if (buttons.some(button => button?.disabled)) return;
  try {
    if (!['pedidos', 'cotacoes'].includes(kind) || !['pdf', 'xlsx'].includes(format)) throw new Error('Exportacao invalida.');
    if (window[`${kind}EditDirty`]) throw new Error('Salve as alteracoes dos itens antes de exportar.');
    if (document.getElementById(`${kind}EditSaveButton`)?.disabled || documentStatusRequests.has(kind)) {
      throw new Error('Aguarde a conclusao da operacao antes de exportar.');
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
      const PdfConstructor = await loadCommercialPdfLibrary();
      await buildCommercialPdf(data, PdfConstructor).save(`${data.filename}.pdf`, { returnPromise: true });
      message.textContent = 'PDF gerado.';
    }
    message.style.color = 'var(--success)';
  } catch (error) {
    message.style.color = 'var(--accent)';
    message.textContent = error.message || 'Nao foi possivel exportar o documento.';
  } finally {
    buttons.forEach(button => { if (button) button.disabled = false; });
  }
}
