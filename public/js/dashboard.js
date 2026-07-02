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

async function renderDashboard(container) {
  container.innerHTML = '<div class="empty-state">Carregando dashboard...</div>';
  try {
    const data = await supabaseGetDashboard();
    const orders = data.ultimosPedidos || [];
    const pedidos = data.resumoPedidos || {};
    const cotacoes = data.resumoCotacoes || {};
    container.innerHTML = `
      <section class="cards">
        <article class="metric-card"><span>Pedidos hoje</span><strong>${data.pedidosHoje || 0}</strong></article>
        <article class="metric-card"><span>Total hoje</span><strong>${money(data.totalHoje)}</strong></article>
        <article class="metric-card"><span>Sem cadastro</span><strong>${data.produtosSemCadastro || 0}</strong></article>
        <article class="metric-card"><span>Estoque zerado</span><strong>${data.estoqueZerado || 0}</strong></article>
      </section>
      <section class="cards">
        ${renderStatusMetric('Pedidos efetivados', pedidos.efetivado)}
        ${renderStatusMetric('Pedidos cancelados', pedidos.cancelado)}
        ${renderStatusMetric('Cotacoes efetivadas', cotacoes.efetivado)}
        ${renderStatusMetric('Cotacoes canceladas', cotacoes.cancelado)}
      </section>
      <section class="panel">
        <div class="panel-header">
          <div><h2>Relatorios por status</h2><p>Resumo de documentos abertos, efetivados e cancelados.</p></div>
        </div>
        <div class="dashboard-report-grid">
          ${renderStatusSummaryTable('Pedidos', pedidos)}
          ${renderStatusSummaryTable('Cotacoes', cotacoes)}
        </div>
      </section>
      <section class="panel">
        <div class="panel-header">
          <div><h2>Ultimos pedidos</h2><p>Movimento recente registrado no Supabase.</p></div>
        </div>
        ${orders.length ? renderOrdersTable(orders) : '<div class="empty-state">Nenhum pedido encontrado.</div>'}
      </section>
    `;
  } catch (error) {
    container.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
  }
}

function renderStatusMetric(label, item) {
  const metric = item || { count: 0, value: 0 };
  return `
    <article class="metric-card">
      <span>${escapeHtml(label)}</span>
      <strong>${metric.count || 0}</strong>
      <small>${money(metric.value)}</small>
    </article>
  `;
}

function renderStatusSummaryTable(title, summary) {
  const rows = [
    ['Aberto', summary.aberto],
    ['Efetivado', summary.efetivado],
    ['Cancelado', summary.cancelado],
    ['Total', summary.total]
  ];
  return `
    <div class="table-wrap compact-table">
      <table>
        <thead><tr><th>${escapeHtml(title)}</th><th>Qtd</th><th>Valor</th></tr></thead>
        <tbody>
          ${rows.map(([label, item]) => `
            <tr>
              <td><span class="status-pill">${escapeHtml(label)}</span></td>
              <td>${(item && item.count) || 0}</td>
              <td>${money(item && item.value)}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function renderOrdersTable(orders) {
  return `
    <div class="table-wrap">
      <table>
        <thead><tr><th>Numero</th><th>Cliente</th><th>Vendedor</th><th>Status</th><th>Total</th></tr></thead>
        <tbody>
          ${orders.map((order) => `
            <tr>
              <td>${escapeHtml(order.numero_pedido)}</td>
              <td>${escapeHtml(order.cliente)}</td>
              <td>${escapeHtml(order.vendedor)}</td>
              <td><span class="status-pill">${escapeHtml(order.status)}</span></td>
              <td>${money(order.total)}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}
