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
    container.innerHTML = `
      <section class="cards">
        <article class="metric-card"><span>Pedidos hoje</span><strong>${data.pedidosHoje || 0}</strong></article>
        <article class="metric-card"><span>Total hoje</span><strong>${money(data.totalHoje)}</strong></article>
        <article class="metric-card"><span>Sem cadastro</span><strong>${data.produtosSemCadastro || 0}</strong></article>
        <article class="metric-card"><span>Estoque zerado</span><strong>${data.estoqueZerado || 0}</strong></article>
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
