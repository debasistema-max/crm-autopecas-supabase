let quoteItems = [];

async function renderCreateQuotation(container) {
  quoteItems = [];
  container.innerHTML = `
    <div class="order-grid">
      <section>
        <section class="panel">
          <div class="panel-header">
            <div><h2>Criar cotacao</h2><p>Use os mesmos clientes e produtos do pedido para montar a cotacao.</p></div>
          </div>
          <div class="field-grid">
            <label class="span-8">Cliente
              <input id="quoteClientSearch" type="search" placeholder="Buscar cliente por codigo SAP, CNPJ ou empresa">
            </label>
            <div class="span-4 actions-row align-end">
              <button class="btn btn-secondary" id="quoteClientSearchButton" type="button">Buscar cliente</button>
            </div>
            <div class="span-12" id="quoteClientResults">
              <div class="empty-state compact-state">Clientes aparecem aqui para preencher a cotacao.</div>
            </div>
            <label class="span-3">Estado
              <select id="quoteRegion"><option>SP</option><option>PR</option></select>
            </label>
            <label class="span-3">Codigo SAP cliente<input id="quoteClientSapCode" type="text"></label>
            <label class="span-6">Cliente<input id="quoteClient" type="text"></label>
            <label class="span-4">CNPJ<input id="quoteCnpj" type="text"></label>
            <label class="span-4">Telefone<input id="quotePhone" type="text"></label>
            <label class="span-8">Endereco<input id="quoteAddress" type="text"></label>
            <label class="span-4">Prazo<input id="quoteTerm" type="text"></label>
            <label class="span-12">Observacao<textarea id="quoteNotes"></textarea></label>
          </div>
        </section>

        <section class="panel">
          <div class="panel-header">
            <div><h2>Adicionar item</h2><p>Produtos aparecem somente apos pesquisa.</p></div>
          </div>
          <form id="quoteProductSearch" class="actions-row">
            <label class="span-6">Produto
              <input id="quoteProductTerm" type="search" placeholder="Codigo, descricao, aplicacao ou similar">
            </label>
            <button class="btn btn-primary" type="submit">Pesquisar</button>
          </form>
        </section>
        <section class="panel" id="quoteSearchResults"><div class="empty-state">Pesquise para adicionar itens a cotacao.</div></section>
      </section>

      <aside class="panel cart-summary">
        <div class="panel-header"><div><h2>Itens da cotacao</h2><p id="quoteCount">0 itens</p></div></div>
        <div id="quoteItems" class="empty-state">Nenhum item adicionado.</div>
        <div class="totals" id="quoteTotals"></div>
        <button class="btn btn-primary" id="saveQuoteButton" type="button">Salvar cotacao</button>
        <p id="quoteMessage" class="form-message"></p>
      </aside>
    </div>
  `;

  document.getElementById('quoteClientSearchButton').addEventListener('click', searchClientsForQuote);
  document.getElementById('quoteClientSearch').addEventListener('keydown', async (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      await searchClientsForQuote();
    }
  });
  document.getElementById('quoteProductSearch').addEventListener('submit', async (event) => {
    event.preventDefault();
    await searchProductsInto(document.getElementById('quoteSearchResults'), {
      termo: document.getElementById('quoteProductTerm').value,
      regiao: document.getElementById('quoteRegion').value
    }, addProductToQuote);
  });
  document.getElementById('quoteRegion').addEventListener('change', () => {
    quoteItems = [];
    renderQuoteCart();
    document.getElementById('quoteSearchResults').innerHTML = '<div class="empty-state">Pesquise novamente para obter precos do estado selecionado.</div>';
  });
  document.getElementById('saveQuoteButton').addEventListener('click', saveCurrentQuote);
  renderQuoteCart();
}

function addProductToQuote(product) {
  const existing = quoteItems.find((item) => item.codigo === product.codigo);
  if (existing) {
    existing.quantidade += 1;
  } else {
    quoteItems.push({
      codigo: product.codigo,
      descricao: product.descricao,
      marca: product.marca,
      aplicacao: product.aplicacao,
      preco: Number(product.preco || 0),
      quantidade: 1,
      desconto_percentual: 0
    });
  }
  renderQuoteCart();
}

function renderQuoteCart() {
  const list = document.getElementById('quoteItems');
  const count = document.getElementById('quoteCount');
  const totals = document.getElementById('quoteTotals');
  count.textContent = quoteItems.length + (quoteItems.length === 1 ? ' item' : ' itens');
  if (!quoteItems.length) {
    list.className = 'empty-state';
    list.innerHTML = 'Nenhum item adicionado.';
    totals.innerHTML = '';
    return;
  }
  list.className = 'table-wrap';
  list.innerHTML = `
    <table>
      <thead><tr><th>Codigo</th><th>Qtd</th><th>Desc. %</th><th>Total</th><th></th></tr></thead>
      <tbody>
        ${quoteItems.map((item, index) => `
          <tr>
            <td>${escapeHtml(item.codigo)}<br><small>${escapeHtml(item.descricao)}</small></td>
            <td><input type="number" min="1" value="${item.quantidade}" data-quote-qty="${index}"></td>
            <td><input type="number" min="0" step="0.01" value="${item.desconto_percentual}" data-quote-discount="${index}"></td>
            <td>${money(item.preco * item.quantidade * (1 - item.desconto_percentual / 100))}</td>
            <td><button class="btn btn-ghost" type="button" data-quote-remove="${index}">Remover</button></td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `;
  list.querySelectorAll('[data-quote-qty]').forEach((input) => {
    input.addEventListener('change', () => {
      quoteItems[Number(input.dataset.quoteQty)].quantidade = Math.max(1, Number(input.value || 1));
      renderQuoteCart();
    });
  });
  list.querySelectorAll('[data-quote-discount]').forEach((input) => {
    input.addEventListener('change', () => {
      quoteItems[Number(input.dataset.quoteDiscount)].desconto_percentual = Math.max(0, Number(input.value || 0));
      renderQuoteCart();
    });
  });
  list.querySelectorAll('[data-quote-remove]').forEach((button) => {
    button.addEventListener('click', () => {
      quoteItems.splice(Number(button.dataset.quoteRemove), 1);
      renderQuoteCart();
    });
  });
  const subtotal = quoteItems.reduce((sum, item) => sum + item.preco * item.quantidade, 0);
  const total = quoteItems.reduce((sum, item) => sum + item.preco * item.quantidade * (1 - item.desconto_percentual / 100), 0);
  totals.innerHTML = `
    <div><span>Subtotal</span><span>${money(subtotal)}</span></div>
    <div><span>Desconto</span><span>${money(subtotal - total)}</span></div>
    <div><strong>Total</strong><strong>${money(total)}</strong></div>
  `;
}

async function saveCurrentQuote() {
  const message = document.getElementById('quoteMessage');
  message.textContent = '';
  try {
    const payload = {
      sessionId: getSessionId(),
      regiao: document.getElementById('quoteRegion').value,
      codigo_sap_cliente: document.getElementById('quoteClientSapCode').value,
      cliente: document.getElementById('quoteClient').value,
      cnpj: document.getElementById('quoteCnpj').value,
      telefone: document.getElementById('quotePhone').value,
      endereco: document.getElementById('quoteAddress').value,
      prazo: document.getElementById('quoteTerm').value,
      observacao: document.getElementById('quoteNotes').value,
      items: quoteItems
    };
    const data = await supabaseCreateQuotation(payload);
    quoteItems = [];
    renderQuoteCart();
    message.style.color = 'var(--success)';
    message.textContent = 'Cotacao ' + data.numero_cotacao + ' salva com sucesso.';
  } catch (error) {
    message.style.color = 'var(--accent)';
    message.textContent = error.message;
  }
}

async function searchClientsForQuote() {
  const target = document.getElementById('quoteClientResults');
  target.innerHTML = '<div class="empty-state compact-state">Buscando clientes...</div>';
  try {
    const rows = await supabaseSearchOrderClients(document.getElementById('quoteClientSearch').value);
    target.innerHTML = renderQuoteClientsResults(rows);
    target.querySelectorAll('[data-use-quote-client]').forEach((button) => {
      button.addEventListener('click', () => applyClientToQuote(rows[Number(button.dataset.useQuoteClient)]));
    });
  } catch (error) {
    target.innerHTML = `<div class="empty-state compact-state">${escapeHtml(error.message)}</div>`;
  }
}

function renderQuoteClientsResults(rows) {
  if (!rows.length) return '<div class="empty-state compact-state">Nenhum cliente encontrado.</div>';
  return `
    <div class="table-wrap compact-table">
      <table>
        <thead><tr><th>Empresa</th><th>CNPJ</th><th>Codigo SAP</th><th>Origem</th><th></th></tr></thead>
        <tbody>
          ${rows.map((row, index) => `
            <tr>
              <td><strong>${escapeHtml(row.razao_social || row.nome_fantasia || '')}</strong><small>${escapeHtml([row.protocolo, row.cidade, row.estado].filter(Boolean).join(' | '))}</small></td>
              <td>${escapeHtml(formatCnpj(row.cnpj || ''))}</td>
              <td>${escapeHtml(row.codigo_sap_cliente || '')}</td>
              <td>${escapeHtml(row.origem === 'cliente' ? 'CRM' : 'Portal')}</td>
              <td><button class="btn btn-secondary" type="button" data-use-quote-client="${index}">Usar</button></td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function applyClientToQuote(row) {
  document.getElementById('quoteClientSapCode').value = row.codigo_sap_cliente || '';
  document.getElementById('quoteClient').value = row.razao_social || row.nome_fantasia || '';
  document.getElementById('quoteCnpj').value = formatCnpj(row.cnpj || '');
  document.getElementById('quotePhone').value = row.whatsapp || row.telefone || '';
  document.getElementById('quoteAddress').value = formatCadastroAddress(row);
  document.getElementById('quoteTerm').value = row.prazo_desejado || '';
  const message = document.getElementById('quoteMessage');
  message.style.color = 'var(--success)';
  message.textContent = 'Cliente carregado na cotacao.';
}

async function renderQuotationsReport(container) {
  container.innerHTML = renderDocumentReportShell('cotacoes');
  bindDocumentReport('cotacoes');
  await loadDocumentReport('cotacoes');
}

async function renderOrdersReport(container) {
  container.innerHTML = renderDocumentReportShell('pedidos');
  bindDocumentReport('pedidos');
  await loadDocumentReport('pedidos');
}

function renderDocumentReportShell(kind) {
  const title = kind === 'pedidos' ? 'Pedidos' : 'Cotacoes';
  const numberLabel = kind === 'pedidos' ? 'Pedido' : 'Cotacao';
  const today = new Date();
  const from = new Date(today);
  from.setDate(from.getDate() - 30);
  return `
    <section class="panel">
      <div class="panel-header">
        <div>
          <h2>${title}</h2>
          <p>Relatorio de ${title.toLowerCase()} por periodo, cliente, vendedor e status.</p>
        </div>
      </div>
      <div class="field-grid">
        <label class="span-4">Pesquisar
          <input id="${kind}Search" placeholder="${numberLabel}, cliente, CNPJ, SAP ou vendedor">
        </label>
        <label class="span-2">De
          <input id="${kind}From" type="date" value="${formatDateInput(from)}">
        </label>
        <label class="span-2">Ate
          <input id="${kind}To" type="date" value="${formatDateInput(today)}">
        </label>
        <label class="span-2">Status
          <select id="${kind}Status">
            <option value="">Todos</option>
            ${documentStatusOptions(kind).map((status) => `<option value="${escapeHtml(status)}">${escapeHtml(status)}</option>`).join('')}
          </select>
        </label>
        <div class="span-2 actions-row align-end">
          <button class="btn btn-primary" id="${kind}FilterButton" type="button">Filtrar</button>
        </div>
      </div>
      <div class="actions-row" style="margin-top: 12px;">
        <button class="btn btn-secondary" id="${kind}ExportButton" type="button">Baixar CSV</button>
        <p id="${kind}Message" class="form-message"></p>
      </div>
    </section>
    <section class="panel" id="${kind}EditPanel" hidden></section>
    <section class="panel" id="${kind}Results"><div class="empty-state">Carregando ${title.toLowerCase()}...</div></section>
  `;
}

function bindDocumentReport(kind) {
  document.getElementById(`${kind}FilterButton`).addEventListener('click', () => loadDocumentReport(kind));
  document.getElementById(`${kind}ExportButton`).addEventListener('click', () => exportDocumentReport(kind));
  document.getElementById(`${kind}Search`).addEventListener('keydown', (event) => {
    if (event.key === 'Enter') loadDocumentReport(kind);
  });
}

async function loadDocumentReport(kind) {
  const target = document.getElementById(`${kind}Results`);
  target.innerHTML = '<div class="empty-state">Carregando relatorio...</div>';
  try {
    const filters = getDocumentFilters(kind);
    const rows = kind === 'pedidos'
      ? await supabaseListOrdersReport(filters)
      : await supabaseListQuotationsReport(filters);
    window[`${kind}LastRows`] = rows;
    target.innerHTML = renderDocumentReport(kind, rows);
    bindDocumentEditButtons(kind, rows);
  } catch (error) {
    target.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
  }
}

function renderDocumentReport(kind, rows) {
  if (!rows.length) return '<div class="empty-state">Nenhum registro encontrado.</div>';
  const numberKey = kind === 'pedidos' ? 'numero_pedido' : 'numero_cotacao';
  const total = rows.reduce((sum, row) => sum + Number(row.total || 0), 0);
  return `
    <div class="cards" style="margin-bottom: 16px;">
      <article class="metric-card"><span>Registros</span><strong>${rows.length}</strong></article>
      <article class="metric-card"><span>Total</span><strong>${money(total)}</strong></article>
      <article class="metric-card"><span>Ticket medio</span><strong>${money(total / rows.length)}</strong></article>
      <article class="metric-card"><span>Ultimo</span><strong>${escapeHtml(rows[0][numberKey] || '')}</strong></article>
    </div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Numero</th><th>Data</th><th>Cliente</th><th>SAP</th><th>Vendedor</th><th>Status</th><th>Total</th><th></th>
          </tr>
        </thead>
        <tbody>
          ${rows.map((row) => `
            <tr>
              <td><strong>${escapeHtml(row[numberKey] || '')}</strong><small>${escapeHtml(row.regiao || '')}</small></td>
              <td>${escapeHtml(formatDateTime(row.created_at || row.data_hora))}</td>
              <td>${escapeHtml(row.cliente || '')}<small>${escapeHtml(formatCnpj(row.cnpj || ''))}</small></td>
              <td>${escapeHtml(row.codigo_sap_cliente || '')}</td>
              <td>${escapeHtml(row.vendedor || '')}</td>
              <td><span class="status-pill">${escapeHtml(row.status || '')}</span></td>
              <td>${money(row.total)}</td>
              <td><button class="btn btn-secondary" type="button" data-edit-document="${index}">Editar</button></td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function bindDocumentEditButtons(kind, rows) {
  document.querySelectorAll('[data-edit-document]').forEach((button) => {
    button.addEventListener('click', () => showDocumentEditForm(kind, rows[Number(button.dataset.editDocument)]));
  });
}

function showDocumentEditForm(kind, row) {
  const panel = document.getElementById(`${kind}EditPanel`);
  const numberKey = kind === 'pedidos' ? 'numero_pedido' : 'numero_cotacao';
  panel.hidden = false;
  panel.innerHTML = `
    <div class="panel-header">
      <div>
        <h2>Editar ${escapeHtml(row[numberKey] || '')}</h2>
        <p>Atualize dados comerciais e status do registro.</p>
      </div>
    </div>
    <form id="${kind}EditForm" class="field-grid">
      <input id="${kind}EditId" type="hidden" value="${escapeHtml(row.id || '')}">
      <label class="span-3">Status
        <select id="${kind}EditStatus">
          ${documentStatusOptions(kind).map((status) => `<option value="${escapeHtml(status)}"${status === row.status ? ' selected' : ''}>${escapeHtml(status)}</option>`).join('')}
        </select>
      </label>
      <label class="span-3">Codigo SAP<input id="${kind}EditSap" value="${escapeHtml(row.codigo_sap_cliente || '')}"></label>
      <label class="span-6">Cliente<input id="${kind}EditClient" value="${escapeHtml(row.cliente || '')}" required></label>
      <label class="span-3">CNPJ<input id="${kind}EditCnpj" value="${escapeHtml(formatCnpj(row.cnpj || ''))}"></label>
      <label class="span-3">Telefone<input id="${kind}EditPhone" value="${escapeHtml(row.telefone || '')}"></label>
      <label class="span-6">Endereco<input id="${kind}EditAddress" value="${escapeHtml(row.endereco || '')}"></label>
      <label class="span-3">Prazo<input id="${kind}EditTerm" value="${escapeHtml(row.prazo || '')}"></label>
      <label class="span-3">Transportadora<input id="${kind}EditCarrier" value="${escapeHtml(row.transportadora || '')}"></label>
      <label class="span-3">CNPJ transportadora<input id="${kind}EditCarrierCnpj" value="${escapeHtml(formatCnpj(row.transportadora_cnpj || ''))}"></label>
      <label class="span-6">Endereco transportadora<input id="${kind}EditCarrierAddress" value="${escapeHtml(row.transportadora_endereco || '')}"></label>
      <label class="span-12">Observacao<textarea id="${kind}EditNotes">${escapeHtml(row.observacao || '')}</textarea></label>
      <div class="span-12 actions-row">
        <button class="btn btn-primary" type="submit">Salvar alteracoes</button>
        <button class="btn btn-ghost" id="${kind}EditCancel" type="button">Cancelar</button>
        <p id="${kind}EditMessage" class="form-message"></p>
      </div>
    </form>
  `;
  document.getElementById(`${kind}EditForm`).addEventListener('submit', (event) => saveDocumentEdit(event, kind));
  document.getElementById(`${kind}EditCancel`).addEventListener('click', () => {
    panel.hidden = true;
    panel.innerHTML = '';
  });
  panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

async function saveDocumentEdit(event, kind) {
  event.preventDefault();
  const message = document.getElementById(`${kind}EditMessage`);
  message.style.color = 'var(--muted)';
  message.textContent = 'Salvando alteracoes...';
  try {
    const payload = {
      id: document.getElementById(`${kind}EditId`).value,
      status: document.getElementById(`${kind}EditStatus`).value,
      codigo_sap_cliente: document.getElementById(`${kind}EditSap`).value,
      cliente: document.getElementById(`${kind}EditClient`).value,
      cnpj: document.getElementById(`${kind}EditCnpj`).value,
      telefone: document.getElementById(`${kind}EditPhone`).value,
      endereco: document.getElementById(`${kind}EditAddress`).value,
      prazo: document.getElementById(`${kind}EditTerm`).value,
      transportadora: document.getElementById(`${kind}EditCarrier`).value,
      transportadora_cnpj: document.getElementById(`${kind}EditCarrierCnpj`).value,
      transportadora_endereco: document.getElementById(`${kind}EditCarrierAddress`).value,
      observacao: document.getElementById(`${kind}EditNotes`).value
    };
    if (kind === 'pedidos') {
      await supabaseUpdateOrderReport(payload);
    } else {
      await supabaseUpdateQuotationReport(payload);
    }
    message.style.color = 'var(--success)';
    message.textContent = 'Alteracoes salvas.';
    await loadDocumentReport(kind);
  } catch (error) {
    message.style.color = 'var(--accent)';
    message.textContent = error.message;
  }
}

function exportDocumentReport(kind) {
  const rows = window[`${kind}LastRows`] || [];
  const message = document.getElementById(`${kind}Message`);
  if (!rows.length) {
    message.style.color = 'var(--accent)';
    message.textContent = 'Nao ha dados para exportar.';
    return;
  }
  const numberKey = kind === 'pedidos' ? 'numero_pedido' : 'numero_cotacao';
  downloadCsv(`${kind}-${formatDateInput(new Date())}.csv`, rows.map((row) => ({
    numero: row[numberKey] || '',
    data: formatDateTime(row.created_at || row.data_hora),
    cliente: row.cliente || '',
    codigo_sap_cliente: row.codigo_sap_cliente || '',
    cnpj: row.cnpj || '',
    vendedor: row.vendedor || '',
    status: row.status || '',
    total: Number(row.total || 0).toFixed(2)
  })));
}

function getDocumentFilters(kind) {
  return {
    termo: document.getElementById(`${kind}Search`).value.trim(),
    from: dateInputToIsoStart(document.getElementById(`${kind}From`).value),
    to: dateInputToIsoEnd(document.getElementById(`${kind}To`).value),
    status: document.getElementById(`${kind}Status`).value
  };
}

function documentStatusOptions(kind) {
  return kind === 'pedidos'
    ? ['NOVO', 'EM_ANALISE', 'APROVADO', 'CANCELADO', 'FATURADO']
    : ['NOVA', 'ENVIADA', 'APROVADA', 'CANCELADA', 'CONVERTIDA'];
}
