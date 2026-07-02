let quoteItems = [];
let quoteClientSearchTimer = null;

async function renderCreateQuotation(container) {
  quoteItems = [];
  container.innerHTML = `
    <section class="sap-document">
      <div class="sap-titlebar">
        <div class="sap-title"><span class="sap-title-icon">#</span><h2>Cotacao de venda</h2></div>
        <strong>No. Novo</strong>
      </div>
      <div class="sap-window">
        <section class="sap-section">
          <h3>Dados gerais</h3>
          <div class="sap-form-grid">
            <div class="sap-form-left">
              <label>Filial
                <select id="quoteBranch"><option>(MA/PR) International Parts Service do Brasil Ltda</option></select>
              </label>
              <div class="sap-inline-fields">
                <label>Cliente | CPF/CNPJ
                  <input id="quoteClientSapCode" type="text" placeholder="Codigo SAP">
                </label>
                <button class="sap-mini-button" id="quoteClientSearchButton" type="button" title="Buscar cliente">&#128269;</button>
                <label>
                  <input id="quoteCnpj" type="text" placeholder="CNPJ">
                </label>
              </div>
              <label>Nome cliente<input id="quoteClient" type="text"></label>
              <label>Buscar cliente
                <span class="sap-search-field">
                  <input id="quoteClientSearch" type="search" placeholder="Codigo SAP, CNPJ, protocolo ou empresa">
                  <button class="sap-search-button" id="quoteClientSearchSubmitButton" type="button" title="Buscar cliente">&#128269;</button>
                </span>
              </label>
              <label>Pessoa de contato<input id="quotePhone" type="text"></label>
              <label>No Ref.Cli.<input id="quoteClientRef" type="text"></label>
              <label>Vendedor<input id="quoteSellerDisplay" type="text" value="${escapeHtml((getStoredSession() || {}).nome || '')}"></label>
              <label>Utilizacao principal<select id="quoteUsage"><option>Revenda</option><option>Consumo</option></select></label>
              <label>Deposito<select id="quoteRegion"><option value="SP">02 - FILIAL - SP</option><option value="PR">01 - MATRIZ - PR</option></select></label>
              <label>Endereco<input id="quoteAddress" type="text"></label>
            </div>
            <div class="sap-form-right">
              <label>Status SAP<input type="text" value="Aberto" readonly></label>
              <label>Dt.Cotacao<input type="text" value="${formatDateInput(new Date())}" readonly></label>
              <label>Valido ate<input type="date" id="quoteValidUntil"></label>
              <label>Autorizacao SAP<input type="text" value="Sem status" readonly></label>
              <label>Autorizacao portal<input type="text" value="Sem status" readonly></label>
            </div>
          </div>
          <div id="quoteClientResults" class="sap-search-results">
            <div class="empty-state compact-state">Clientes aparecem aqui para preencher a cotacao.</div>
          </div>
        </section>

        <section class="sap-section sap-tabs-section">
          <div class="sap-tabs">
            <button class="is-active" type="button" data-sap-tab="items">Itens</button>
            <button type="button" data-sap-tab="freight">Frete / Pagamento</button>
          </div>
          <div class="sap-tab-panel" data-sap-panel="items">
            <div class="sap-tab-tools">
              <label class="sap-checkbox"><input type="checkbox" checked> Simular impostos</label>
              <span id="quoteCount">0 itens</span>
            </div>
            <div id="quoteItems" class="sap-items-wrap"></div>
            <div class="sap-bottom-grid">
              <div class="sap-add-item">
                <form id="quoteProductSearch" class="sap-add-form">
                  <label>Cod.Item
                    <input id="quoteProductTerm" type="search" placeholder="Codigo, descricao, aplicacao ou similar">
                  </label>
                  <label>Nome item
                    <input id="quoteProductNamePreview" type="text" readonly>
                  </label>
                  <label>Grupo
                    <input id="quoteProductGroupPreview" type="text" readonly>
                  </label>
                  <div class="sap-stock-line">Disp. Venda: <strong>-</strong> / Pr.Unit.: <strong>-</strong></div>
                  <label>Quantidade
                    <input id="quoteAddQuantity" type="number" min="1" value="1">
                  </label>
                  <div class="actions-row">
                    <button class="btn btn-primary" type="submit">Adicionar</button>
                    <button class="btn btn-ghost" id="quoteClearProductButton" type="button">Limpar</button>
                  </div>
                </form>
                <div id="quoteSearchResults" class="sap-product-results"><div class="empty-state compact-state">Pesquise para adicionar itens a cotacao.</div></div>
              </div>
              <div class="sap-totals" id="quoteTotals"></div>
            </div>
          </div>
          <div class="sap-tab-panel" data-sap-panel="freight" hidden>
            <div class="sap-freight-grid">
              <label>Tipo de envio
                <select id="quoteShippingType">
                  <option>PAGO DESTINATARIO</option>
                  <option>PAGO REMETENTE</option>
                  <option>RETIRA</option>
                </select>
              </label>
              <label>Codigo transportadora
                <span class="sap-search-field">
                  <input id="quoteCarrierSearch" type="search">
                  <button class="sap-search-button" id="quoteCarrierCodeSearchButton" type="button">...</button>
                </span>
              </label>
              <label>Nome transportadora
                <span class="sap-search-field">
                  <input id="quoteCarrier" type="text">
                  <button class="sap-search-button" id="quoteCarrierNameSearchButton" type="button">...</button>
                </span>
              </label>
              <label>Cond. de pagamento
                <select id="quoteTerm">
                  <option>30/40/50/60/70/80</option>
                  <option>28/35/42</option>
                  <option>30/60/90</option>
                  <option>A vista</option>
                </select>
              </label>
            </div>
            <input id="quoteCarrierCnpj" type="hidden">
            <input id="quoteCarrierAddress" type="hidden">
            <input id="quoteNotes" type="hidden">
            <div id="quoteCarrierResults" class="sap-search-results">
              <div class="empty-state compact-state">Transportadoras cadastradas aparecem aqui.</div>
            </div>
          </div>
        </section>
      </div>
      <div class="sap-footer-actions">
        <button class="btn btn-primary" id="saveQuoteButton" type="button">Salvar</button>
        <button class="btn btn-ghost" id="closeQuoteButton" type="button">Fechar</button>
        <p id="quoteMessage" class="form-message"></p>
      </div>
    </section>
  `;

  bindSapTabs(container);
  document.getElementById('quoteClientSearchButton').addEventListener('click', searchClientsForQuote);
  document.getElementById('quoteClientSearchSubmitButton').addEventListener('click', () => searchClientsForQuote({
    term: document.getElementById('quoteClientSearch').value
  }));
  document.getElementById('quoteClientSearch').addEventListener('keydown', async (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      await searchClientsForQuote({ term: event.target.value });
    }
  });
  ['quoteClientSearch', 'quoteClientSapCode', 'quoteCnpj', 'quoteClient'].forEach((id) => {
    document.getElementById(id).addEventListener('input', scheduleQuoteClientAutoSearch);
  });
  document.getElementById('quoteCarrierCodeSearchButton').addEventListener('click', searchCarriersForQuote);
  document.getElementById('quoteCarrierNameSearchButton').addEventListener('click', searchCarriersForQuote);
  document.getElementById('quoteCarrierSearch').addEventListener('keydown', async (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      await searchCarriersForQuote();
    }
  });
  document.getElementById('quoteCarrier').addEventListener('keydown', async (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      await searchCarriersForQuote();
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
  document.getElementById('closeQuoteButton').addEventListener('click', () => {
    openModule('quoteReports');
  });
  document.getElementById('quoteClearProductButton').addEventListener('click', () => {
    document.getElementById('quoteProductTerm').value = '';
    document.getElementById('quoteProductNamePreview').value = '';
    document.getElementById('quoteProductGroupPreview').value = '';
    document.getElementById('quoteSearchResults').innerHTML = '<div class="empty-state compact-state">Pesquise para adicionar itens a cotacao.</div>';
  });
  renderQuoteCart();
}

function addProductToQuote(product) {
  const existing = quoteItems.find((item) => item.codigo === product.codigo);
  const qtyInput = document.getElementById('quoteAddQuantity');
  const quantity = Math.max(1, Number(qtyInput ? qtyInput.value || 1 : 1));
  const namePreview = document.getElementById('quoteProductNamePreview');
  const groupPreview = document.getElementById('quoteProductGroupPreview');
  if (namePreview) namePreview.value = product.descricao || '';
  if (groupPreview) groupPreview.value = product.grupo || product.linha || product.categoria || '';
  if (existing) {
    existing.quantidade += quantity;
  } else {
    quoteItems.push({
      codigo: product.codigo,
      descricao: product.descricao,
      marca: product.marca,
      aplicacao: product.aplicacao,
      preco: Number(product.preco || 0),
      quantidade: quantity,
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
  const subtotal = quoteItems.reduce((sum, item) => sum + item.preco * item.quantidade, 0);
  const total = quoteItems.reduce((sum, item) => sum + item.preco * item.quantidade * (1 - item.desconto_percentual / 100), 0);
  const discount = subtotal - total;
  if (!quoteItems.length) {
    list.className = 'sap-items-wrap';
    list.innerHTML = renderSapQuoteItemsTable([]);
    totals.innerHTML = renderSapTotals(0, 0, 0);
    return;
  }
  list.className = 'sap-items-wrap';
  list.innerHTML = renderSapQuoteItemsTable(quoteItems);
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
  totals.innerHTML = renderSapTotals(subtotal, discount, total);
}

function renderSapQuoteItemsTable(items) {
  const totalQty = items.reduce((sum, item) => sum + Number(item.quantidade || 0), 0);
  const subtotal = items.reduce((sum, item) => sum + item.preco * item.quantidade, 0);
  const total = items.reduce((sum, item) => sum + item.preco * item.quantidade * (1 - item.desconto_percentual / 100), 0);
  const rows = items.length ? items.map((item, index) => {
    const finalUnit = item.preco * (1 - item.desconto_percentual / 100);
    const rowTotal = finalUnit * item.quantidade;
    return `
      <tr>
        <td>${index + 1}</td>
        <td class="sap-code">${escapeHtml(item.codigo)}</td>
        <td>${escapeHtml(item.descricao || '')}</td>
        <td>${escapeHtml(item.marca || '')}</td>
        <td>${escapeHtml(item.aplicacao || '')}</td>
        <td>UN</td>
        <td><input type="number" min="1" value="${escapeHtml(item.quantidade)}" data-quote-qty="${index}"></td>
        <td>${money(item.preco)}</td>
        <td><input type="number" min="0" step="0.01" value="${escapeHtml(item.desconto_percentual)}" data-quote-discount="${index}"></td>
        <td>${money(finalUnit)}</td>
        <td>${money(rowTotal)}</td>
        <td>${money(rowTotal)}</td>
        <td><button class="sap-remove-button" type="button" data-quote-remove="${index}" title="Remover">-</button></td>
      </tr>
    `;
  }).join('') : '<tr><td colspan="13" class="sap-empty-row">Nenhum item adicionado.</td></tr>';
  return `
    <table class="sap-items-table">
      <thead>
        <tr>
          <th>#</th><th>Cod.</th><th>Descricao</th><th>Marca</th><th>Aplicacao</th><th>UM</th><th>Qtde</th>
          <th>Pr.Unit.</th><th>% do desc.</th><th>Pr.Apos Desc.</th><th>Total Apos Desc.</th><th>Total c/ Imp.</th><th></th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
      <tfoot>
        <tr>
          <td colspan="6">Totais:</td><td>${totalQty}</td><td></td><td></td><td></td><td>${money(total)}</td><td>${money(subtotal)}</td><td></td>
        </tr>
      </tfoot>
    </table>
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
      transportadora: document.getElementById('quoteCarrier').value,
      transportadora_cnpj: document.getElementById('quoteCarrierCnpj').value,
      transportadora_endereco: document.getElementById('quoteCarrierAddress').value,
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

function getQuoteClientSearchTerm(sourceId) {
  if (sourceId) return (document.getElementById(sourceId) || {}).value || '';
  return [
    'quoteClientSearch',
    'quoteClientSapCode',
    'quoteCnpj',
    'quoteClient'
  ].map((id) => (document.getElementById(id) || {}).value || '').find((value) => String(value).trim()) || '';
}

function scheduleQuoteClientAutoSearch(event) {
  const term = getQuoteClientSearchTerm(event.target.id);
  window.clearTimeout(quoteClientSearchTimer);
  if (!isClientLookupReady(term)) return;
  quoteClientSearchTimer = window.setTimeout(() => {
    searchClientsForQuote({ term, auto: true });
  }, 450);
}

async function searchClientsForQuote(options = {}) {
  const target = document.getElementById('quoteClientResults');
  const term = options.term !== undefined ? options.term : getQuoteClientSearchTerm();
  if (!isClientLookupReady(term)) {
    target.innerHTML = '<div class="empty-state compact-state">Digite pelo menos 3 caracteres ou CNPJ/codigo para buscar.</div>';
    return;
  }
  target.innerHTML = '<div class="empty-state compact-state">Buscando clientes...</div>';
  try {
    const rows = await supabaseSearchOrderClients(term);
    const exact = findExactClientMatch(rows, term);
    if (exact) {
      applyClientToQuote(exact);
      target.innerHTML = '<div class="empty-state compact-state">Cliente encontrado e carregado automaticamente.</div>';
      return;
    }
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

async function searchCarriersForQuote() {
  const target = document.getElementById('quoteCarrierResults');
  target.innerHTML = '<div class="empty-state compact-state">Buscando transportadoras...</div>';
  try {
    const term = document.getElementById('quoteCarrierSearch').value || document.getElementById('quoteCarrier').value;
    const rows = await supabaseSearchOrderCarriers(term);
    target.innerHTML = renderQuoteCarriersResults(rows);
    target.querySelectorAll('[data-use-quote-carrier]').forEach((button) => {
      button.addEventListener('click', () => applyCarrierToQuote(rows[Number(button.dataset.useQuoteCarrier)]));
    });
  } catch (error) {
    target.innerHTML = `<div class="empty-state compact-state">${escapeHtml(error.message)}</div>`;
  }
}

function renderQuoteCarriersResults(rows) {
  if (!rows.length) return '<div class="empty-state compact-state">Nenhuma transportadora encontrada.</div>';
  return `
    <div class="table-wrap compact-table">
      <table>
        <thead><tr><th>Transportadora</th><th>CNPJ</th><th>Cidade/UF</th><th></th></tr></thead>
        <tbody>
          ${rows.map((row, index) => `
            <tr>
              <td><strong>${escapeHtml(row.nome || '')}</strong><small>${escapeHtml(row.endereco || '')}</small></td>
              <td>${escapeHtml(formatCnpj(row.cnpj || ''))}</td>
              <td>${escapeHtml([row.cidade, row.estado].filter(Boolean).join('/'))}</td>
              <td><button class="btn btn-secondary" type="button" data-use-quote-carrier="${index}">Usar</button></td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function applyCarrierToQuote(row) {
  document.getElementById('quoteCarrier').value = row.nome || '';
  document.getElementById('quoteCarrierCnpj').value = formatCnpj(row.cnpj || '');
  document.getElementById('quoteCarrierAddress').value = formatCarrierAddress(row);
  const message = document.getElementById('quoteMessage');
  message.style.color = 'var(--success)';
  message.textContent = 'Transportadora carregada na cotacao.';
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
          ${rows.map((row, index) => `
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
  const itemsKey = kind === 'pedidos' ? 'order_items' : 'quotation_items';
  window[`${kind}EditingItems`] = normalizeDocumentItems(row[itemsKey] || []);
  panel.hidden = false;
  panel.innerHTML = `
    <div class="panel-header">
      <div>
        <h2>Editar itens ${escapeHtml(row[numberKey] || '')}</h2>
        <p>${escapeHtml(row.cliente || '')} | ${escapeHtml(formatCnpj(row.cnpj || ''))}</p>
      </div>
    </div>
    <form id="${kind}EditForm" class="field-grid">
      <input id="${kind}EditId" type="hidden" value="${escapeHtml(row.id || '')}">
      <div class="span-12 document-edit-summary">
        <strong>Cliente travado</strong>
        <span>${escapeHtml(row.codigo_sap_cliente || '')} ${escapeHtml(row.cliente || '')}</span>
      </div>
      <label class="span-8">Adicionar produto
        <input id="${kind}EditProductTerm" type="search" placeholder="Codigo, descricao, aplicacao ou similar">
      </label>
      <div class="span-4 actions-row align-end">
        <button class="btn btn-secondary" id="${kind}EditProductSearchButton" type="button">Pesquisar item</button>
      </div>
      <div class="span-12" id="${kind}EditProductResults">
        <div class="empty-state compact-state">Pesquise para adicionar novos itens.</div>
      </div>
      <div class="span-12" id="${kind}EditItems"></div>
      <div class="span-12 actions-row">
        <button class="btn btn-primary" type="submit">Salvar itens</button>
        <button class="btn btn-ghost" id="${kind}EditCancel" type="button">Cancelar</button>
        <p id="${kind}EditMessage" class="form-message"></p>
      </div>
    </form>
  `;
  renderDocumentEditItems(kind);
  const searchButton = document.getElementById(`${kind}EditProductSearchButton`);
  const searchInput = document.getElementById(`${kind}EditProductTerm`);
  searchButton.addEventListener('click', () => searchProductsForDocumentEdit(kind, row.regiao || 'SP'));
  searchInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      searchProductsForDocumentEdit(kind, row.regiao || 'SP');
    }
  });
  document.getElementById(`${kind}EditForm`).addEventListener('submit', (event) => saveDocumentEdit(event, kind));
  document.getElementById(`${kind}EditCancel`).addEventListener('click', () => {
    panel.hidden = true;
    panel.innerHTML = '';
  });
  panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function normalizeDocumentItems(items) {
  return (items || [])
    .slice()
    .sort((a, b) => Number(a.item || 0) - Number(b.item || 0))
    .map((item) => ({
      codigo: item.codigo,
      descricao: item.descricao,
      marca: item.marca,
      aplicacao: item.aplicacao,
      preco: Number(item.preco_unitario || 0),
      quantidade: Number(item.quantidade || 1),
      desconto_percentual: Number(item.desconto_percentual || 0)
    }));
}

function renderDocumentEditItems(kind) {
  const target = document.getElementById(`${kind}EditItems`);
  const items = window[`${kind}EditingItems`] || [];
  if (!items.length) {
    target.innerHTML = '<div class="empty-state">Nenhum item no documento.</div>';
    return;
  }
  const subtotal = items.reduce((sum, item) => sum + Number(item.preco || 0) * Number(item.quantidade || 0), 0);
  const total = items.reduce((sum, item) => sum + Number(item.preco || 0) * Number(item.quantidade || 0) * (1 - Number(item.desconto_percentual || 0) / 100), 0);
  target.innerHTML = `
    <div class="table-wrap">
      <table>
        <thead><tr><th>Codigo</th><th>Qtd</th><th>Desc. %</th><th>Unitario</th><th>Total</th><th></th></tr></thead>
        <tbody>
          ${items.map((item, index) => `
            <tr>
              <td>${escapeHtml(item.codigo || '')}<br><small>${escapeHtml(item.descricao || '')}</small></td>
              <td><input type="number" min="1" value="${escapeHtml(item.quantidade)}" data-document-edit-qty="${index}"></td>
              <td><input type="number" min="0" step="0.01" value="${escapeHtml(item.desconto_percentual)}" data-document-edit-discount="${index}"></td>
              <td>${money(item.preco)}</td>
              <td>${money(item.preco * item.quantidade * (1 - item.desconto_percentual / 100))}</td>
              <td><button class="btn btn-ghost" type="button" data-document-edit-remove="${index}">Remover</button></td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
    <div class="totals">
      <div><span>Subtotal</span><span>${money(subtotal)}</span></div>
      <div><span>Desconto</span><span>${money(subtotal - total)}</span></div>
      <div><strong>Total</strong><strong>${money(total)}</strong></div>
    </div>
  `;
  target.querySelectorAll('[data-document-edit-qty]').forEach((input) => {
    input.addEventListener('change', () => {
      items[Number(input.dataset.documentEditQty)].quantidade = Math.max(1, Number(input.value || 1));
      renderDocumentEditItems(kind);
    });
  });
  target.querySelectorAll('[data-document-edit-discount]').forEach((input) => {
    input.addEventListener('change', () => {
      items[Number(input.dataset.documentEditDiscount)].desconto_percentual = Math.max(0, Number(input.value || 0));
      renderDocumentEditItems(kind);
    });
  });
  target.querySelectorAll('[data-document-edit-remove]').forEach((button) => {
    button.addEventListener('click', () => {
      items.splice(Number(button.dataset.documentEditRemove), 1);
      renderDocumentEditItems(kind);
    });
  });
}

async function searchProductsForDocumentEdit(kind, regiao) {
  const target = document.getElementById(`${kind}EditProductResults`);
  await searchProductsInto(target, {
    termo: document.getElementById(`${kind}EditProductTerm`).value,
    regiao
  }, (product) => addProductToDocumentEdit(kind, product));
}

function addProductToDocumentEdit(kind, product) {
  const items = window[`${kind}EditingItems`] || [];
  const existing = items.find((item) => item.codigo === product.codigo);
  if (existing) {
    existing.quantidade += 1;
  } else {
    items.push({
      codigo: product.codigo,
      descricao: product.descricao,
      marca: product.marca,
      aplicacao: product.aplicacao,
      preco: Number(product.preco || 0),
      quantidade: 1,
      desconto_percentual: 0
    });
  }
  window[`${kind}EditingItems`] = items;
  renderDocumentEditItems(kind);
}

async function saveDocumentEdit(event, kind) {
  event.preventDefault();
  const message = document.getElementById(`${kind}EditMessage`);
  message.style.color = 'var(--muted)';
  message.textContent = 'Salvando alteracoes...';
  try {
    const payload = {
      id: document.getElementById(`${kind}EditId`).value,
      items: window[`${kind}EditingItems`] || []
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
