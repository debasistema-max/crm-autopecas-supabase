function money(value) {
  return new Intl.NumberFormat(APP_CONFIG.locale, {
    style: 'currency',
    currency: APP_CONFIG.currency
  }).format(Number(value || 0));
}

function escapeHtml(value) {
  return String(value == null ? '' : value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  }[char]));
}

function todayIsoDate() {
  return new Date().toISOString().slice(0, 10);
}

function monthStartIsoDate() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
}

async function renderDashboard(container) {
  const state = {
    dateFrom: monthStartIsoDate(),
    dateTo: todayIsoDate(),
    region: '',
    sellerId: ''
  };

  container.innerHTML = renderCommercialDashboardShell(state);
  bindCommercialDashboardEvents(container, state);
  await loadCommercialDashboard(container, state);
}

function renderCommercialDashboardShell(state) {
  return `
    <section class="panel commercial-dashboard">
      <div class="panel-header dashboard-header">
        <div>
          <h2>Dashboard Comercial</h2>
          <p>Indicadores agregados do periodo selecionado.</p>
        </div>
        <button class="btn secondary" type="button" data-dashboard-refresh>Atualizar</button>
      </div>
      <form class="dashboard-filters" data-dashboard-filters>
        <label>
          <span>Data inicial</span>
          <input type="date" name="dateFrom" value="${escapeHtml(state.dateFrom)}">
        </label>
        <label>
          <span>Data final</span>
          <input type="date" name="dateTo" value="${escapeHtml(state.dateTo)}">
        </label>
        <label>
          <span>Regiao</span>
          <select name="region">
            <option value="">Todas</option>
            <option value="SP">SP</option>
            <option value="PR">PR</option>
          </select>
        </label>
        <label data-seller-filter hidden>
          <span>Vendedor</span>
          <select name="sellerId">
            <option value="">Todos</option>
          </select>
        </label>
      </form>
    </section>
    <div data-dashboard-result>
      <div class="empty-state">Carregando dashboard...</div>
    </div>
  `;
}

function bindCommercialDashboardEvents(container, state) {
  const form = container.querySelector('[data-dashboard-filters]');
  const refreshButton = container.querySelector('[data-dashboard-refresh]');
  const updateFromForm = () => {
    state.dateFrom = form.elements.dateFrom.value;
    state.dateTo = form.elements.dateTo.value;
    state.region = form.elements.region.value;
    state.sellerId = form.elements.sellerId ? form.elements.sellerId.value : '';
  };

  form.addEventListener('change', async () => {
    updateFromForm();
    await loadCommercialDashboard(container, state);
  });

  refreshButton.addEventListener('click', async () => {
    updateFromForm();
    await loadCommercialDashboard(container, state);
  });
}

async function loadCommercialDashboard(container, state) {
  const result = container.querySelector('[data-dashboard-result]');
  const refreshButton = container.querySelector('[data-dashboard-refresh]');
  refreshButton.disabled = true;
  result.innerHTML = '<div class="empty-state">Carregando dashboard...</div>';

  try {
    const data = isLocalDashboardMockEnabled()
      ? getLocalCommercialDashboardMock(state)
      : await supabaseGetCommercialDashboardSummary(state);
    syncSellerFilter(container, data, state);
    result.innerHTML = renderCommercialDashboard(data);
  } catch (error) {
    result.innerHTML = `
      <section class="panel">
        <div class="empty-state">
          <strong>${escapeHtml(error.message)}</strong>
          <button class="btn secondary" type="button" data-dashboard-retry>Tentar novamente</button>
        </div>
      </section>
    `;
    const retry = result.querySelector('[data-dashboard-retry]');
    retry.addEventListener('click', () => loadCommercialDashboard(container, state));
  } finally {
    refreshButton.disabled = false;
  }
}

function isLocalDashboardMockEnabled() {
  const host = location.hostname;
  const isLocal = location.protocol === 'file:' || host === 'localhost' || host === '127.0.0.1';
  return isLocal && new URLSearchParams(location.search).get('mockDashboard') === '1';
}

function getLocalCommercialDashboardMock(state) {
  return {
    filters: {
      date_from: state.dateFrom,
      date_to: state.dateTo,
      region: state.region || null,
      seller_id: state.sellerId || null
    },
    access: {
      scope: 'all',
      can_filter_seller: true,
      can_filter_region: true,
      can_view_imports: true,
      can_view_products: true
    },
    sellers: [
      { id: '00000000-0000-0000-0000-000000000001', nome: 'Administrador', usuario: 'admin' }
    ],
    orders: {
      count: 12,
      total_value: 18450.75,
      by_status: [
        { status: 'NOVO', count: 3, total_value: 2500 },
        { status: 'APROVADO', count: 8, total_value: 15200.75 },
        { status: 'CANCELADO', count: 1, total_value: 750 }
      ]
    },
    quotations: {
      pending_count: 4,
      by_status: [
        { status: 'NOVA', count: 2, total_value: 1800 },
        { status: 'ENVIADA', count: 2, total_value: 3200 },
        { status: 'APROVADA', count: 1, total_value: 1200 }
      ]
    },
    products: {
      out_of_stock_count: 7
    },
    imports: {
      last_import: {
        id: 'mock-local',
        created_at: new Date().toISOString(),
        imported_at: new Date().toISOString(),
        status: 'imported',
        region: state.region || 'SP',
        source_name: 'mock-dashboard.csv',
        total_rows: 100,
        valid_rows: 98,
        error_count: 0
      },
      batches_by_status: [
        { status: 'validated', count: 1 },
        { status: 'approved', count: 1 },
        { status: 'imported', count: 3 }
      ]
    },
    recent_activities: [
      { data_hora: new Date().toISOString(), usuario: 'admin', acao: 'MOCK_DASHBOARD_LOCAL', entidade: 'dashboard', id_entidade: 'local' }
    ]
  };
}

function syncSellerFilter(container, data, state) {
  const holder = container.querySelector('[data-seller-filter]');
  const select = holder && holder.querySelector('select');
  if (!holder || !select) return;
  const sellers = Array.isArray(data.sellers) ? data.sellers : [];
  const canFilterSeller = !!(data.access && data.access.can_filter_seller);
  holder.hidden = !canFilterSeller;
  if (!canFilterSeller) {
    select.innerHTML = '<option value="">Todos</option>';
    state.sellerId = '';
    return;
  }
  select.innerHTML = `
    <option value="">Todos</option>
    ${sellers.map((seller) => `
      <option value="${escapeHtml(seller.id)}"${seller.id === state.sellerId ? ' selected' : ''}>${escapeHtml(seller.nome || seller.usuario)}</option>
    `).join('')}
  `;
}

function renderCommercialDashboard(data) {
  const orders = data.orders || {};
  const quotations = data.quotations || {};
  const products = data.products || {};
  const imports = data.imports || {};
  const access = data.access || {};
  const lastImport = imports.last_import || {};

  return `
    <section class="cards">
      <article class="metric-card"><span>Pedidos no periodo</span><strong>${orders.count || 0}</strong></article>
      <article class="metric-card"><span>Valor dos pedidos</span><strong>${money(orders.total_value)}</strong></article>
      <article class="metric-card"><span>Cotacoes pendentes</span><strong>${quotations.pending_count || 0}</strong></article>
      <article class="metric-card"><span>Estoque zerado</span><strong>${products.out_of_stock_count || 0}</strong></article>
    </section>
    <section class="dashboard-grid">
      <article class="panel">
        <div class="panel-header">
          <div><h2>Pedidos por status</h2><p>Totais agregados no periodo.</p></div>
        </div>
        ${renderStatusRows(orders.by_status, true)}
      </article>
      <article class="panel">
        <div class="panel-header">
          <div><h2>Cotacoes por status</h2><p>Quantidade e valor por situacao.</p></div>
        </div>
        ${renderStatusRows(quotations.by_status, true)}
      </article>
    </section>
    <section class="dashboard-grid">
      <article class="panel">
        <div class="panel-header">
          <div><h2>Importacao SAP</h2><p>Ultima movimentacao e resumo dos lotes.</p></div>
        </div>
        ${access.can_view_imports ? renderImportSummary(lastImport, imports.batches_by_status) : '<div class="empty-state">Sem permissao para visualizar importacoes.</div>'}
      </article>
      <article class="panel">
        <div class="panel-header">
          <div><h2>Atividades recentes</h2><p>Eventos seguros registrados no periodo.</p></div>
        </div>
        ${renderRecentActivities(data.recent_activities)}
      </article>
    </section>
  `;
}

function renderStatusRows(rows = [], showValue = false) {
  if (!rows.length) return '<div class="empty-state">Nenhum registro no periodo.</div>';
  return `
    <div class="table-wrap compact-table">
      <table>
        <thead>
          <tr><th>Status</th><th>Qtd</th>${showValue ? '<th>Valor</th>' : ''}</tr>
        </thead>
        <tbody>
          ${rows.map((row) => `
            <tr>
              <td><span class="status-pill">${escapeHtml(row.status)}</span></td>
              <td>${row.count || 0}</td>
              ${showValue ? `<td>${money(row.total_value)}</td>` : ''}
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function renderImportSummary(lastImport, batches = []) {
  const hasLastImport = !!lastImport && !!lastImport.id;
  return `
    <div class="dashboard-import-summary">
      ${hasLastImport ? `
        <div class="dashboard-detail-list">
          <span>Ultimo lote</span><strong>${escapeHtml(lastImport.id)}</strong>
          <span>Status</span><strong>${escapeHtml(lastImport.status)}</strong>
          <span>Regiao</span><strong>${escapeHtml(lastImport.region || '-')}</strong>
          <span>Arquivo</span><strong>${escapeHtml(lastImport.source_name || '-')}</strong>
          <span>Data</span><strong>${formatDateTime(lastImport.imported_at || lastImport.created_at)}</strong>
        </div>
      ` : '<div class="empty-state">Nenhuma importacao encontrada.</div>'}
      <h3 class="dashboard-subtitle">Lotes por status</h3>
      ${renderStatusRows((batches || []).map((row) => ({ status: row.status, count: row.count })), false)}
    </div>
  `;
}

function renderRecentActivities(activities = []) {
  if (!activities.length) return '<div class="empty-state">Nenhuma atividade recente.</div>';
  return `
    <div class="activity-list">
      ${activities.map((activity) => `
        <div class="activity-item">
          <strong>${escapeHtml(activity.acao)}</strong>
          <span>${escapeHtml(activity.usuario || 'Sistema')} - ${escapeHtml(activity.entidade || '-')} - ${formatDateTime(activity.data_hora)}</span>
        </div>
      `).join('')}
    </div>
  `;
}

function formatDateTime(value) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return new Intl.DateTimeFormat(APP_CONFIG.locale, {
    dateStyle: 'short',
    timeStyle: 'short'
  }).format(date);
}
