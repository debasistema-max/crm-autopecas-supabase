let orderItems = [];

async function renderOrders(container) {
  orderItems = [];
  container.innerHTML = `
    <div class="order-grid">
      <section>
        <section class="panel">
          <div class="panel-header">
            <div><h2>Gerar pedido</h2><p>O pedido comeca vazio. Pesquise produtos para adicionar itens.</p></div>
          </div>
          <div class="field-grid">
            <label class="span-3">Estado
              <select id="orderRegion"><option>SP</option><option>PR</option></select>
            </label>
            <label class="span-5">Cliente<input id="orderClient" type="text"></label>
            <label class="span-4">CNPJ<input id="orderCnpj" type="text"></label>
            <label class="span-4">Telefone<input id="orderPhone" type="text"></label>
            <label class="span-8">Endereco<input id="orderAddress" type="text"></label>
            <label class="span-4">Prazo<input id="orderTerm" type="text"></label>
            <label class="span-4">Transportadora<input id="orderCarrier" type="text"></label>
            <label class="span-4">CNPJ transportadora<input id="orderCarrierCnpj" type="text"></label>
            <label class="span-12">Observacao<textarea id="orderNotes"></textarea></label>
          </div>
        </section>

        <section class="panel">
          <div class="panel-header">
            <div><h2>Adicionar item</h2><p>Produtos aparecem somente apos pesquisa.</p></div>
          </div>
          <form id="orderProductSearch" class="actions-row">
            <label class="span-6">Produto
              <input id="orderProductTerm" type="search" placeholder="Codigo, descricao, aplicacao ou similar">
            </label>
            <button class="btn btn-primary" type="submit">Pesquisar</button>
          </form>
        </section>
        <section class="panel" id="orderSearchResults"><div class="empty-state">Pesquise para adicionar itens ao pedido.</div></section>
      </section>

      <aside class="panel cart-summary">
        <div class="panel-header"><div><h2>Itens do pedido</h2><p id="cartCount">0 itens</p></div></div>
        <div id="cartItems" class="empty-state">Nenhum item adicionado.</div>
        <div class="totals" id="cartTotals"></div>
        <button class="btn btn-primary" id="saveOrderButton" type="button">Salvar pedido</button>
        <p id="orderMessage" class="form-message"></p>
      </aside>
    </div>
  `;

  document.getElementById('orderProductSearch').addEventListener('submit', async (event) => {
    event.preventDefault();
    await searchProductsInto(document.getElementById('orderSearchResults'), {
      termo: document.getElementById('orderProductTerm').value,
      regiao: document.getElementById('orderRegion').value
    }, addProductToOrder);
  });

  document.getElementById('orderRegion').addEventListener('change', () => {
    orderItems = [];
    renderCart();
    document.getElementById('orderSearchResults').innerHTML = '<div class="empty-state">Pesquise novamente para obter precos do estado selecionado.</div>';
  });

  document.getElementById('saveOrderButton').addEventListener('click', saveCurrentOrder);
  renderCart();
}

function addProductToOrder(product) {
  const existing = orderItems.find((item) => item.codigo === product.codigo);
  if (existing) {
    existing.quantidade += 1;
  } else {
    orderItems.push({
      codigo: product.codigo,
      descricao: product.descricao,
      marca: product.marca,
      aplicacao: product.aplicacao,
      preco: Number(product.preco || 0),
      quantidade: 1,
      desconto_percentual: 0
    });
  }
  renderCart();
}

function renderCart() {
  const list = document.getElementById('cartItems');
  const count = document.getElementById('cartCount');
  const totals = document.getElementById('cartTotals');
  count.textContent = orderItems.length + (orderItems.length === 1 ? ' item' : ' itens');
  if (!orderItems.length) {
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
        ${orderItems.map((item, index) => `
          <tr>
            <td>${escapeHtml(item.codigo)}<br><small>${escapeHtml(item.descricao)}</small></td>
            <td><input type="number" min="1" value="${item.quantidade}" data-cart-qty="${index}"></td>
            <td><input type="number" min="0" step="0.01" value="${item.desconto_percentual}" data-cart-discount="${index}"></td>
            <td>${money(item.preco * item.quantidade * (1 - item.desconto_percentual / 100))}</td>
            <td><button class="btn btn-ghost" type="button" data-cart-remove="${index}">Remover</button></td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `;
  list.querySelectorAll('[data-cart-qty]').forEach((input) => {
    input.addEventListener('change', () => {
      orderItems[Number(input.dataset.cartQty)].quantidade = Math.max(1, Number(input.value || 1));
      renderCart();
    });
  });
  list.querySelectorAll('[data-cart-discount]').forEach((input) => {
    input.addEventListener('change', () => {
      orderItems[Number(input.dataset.cartDiscount)].desconto_percentual = Math.max(0, Number(input.value || 0));
      renderCart();
    });
  });
  list.querySelectorAll('[data-cart-remove]').forEach((button) => {
    button.addEventListener('click', () => {
      orderItems.splice(Number(button.dataset.cartRemove), 1);
      renderCart();
    });
  });
  const subtotal = orderItems.reduce((sum, item) => sum + item.preco * item.quantidade, 0);
  const total = orderItems.reduce((sum, item) => sum + item.preco * item.quantidade * (1 - item.desconto_percentual / 100), 0);
  totals.innerHTML = `
    <div><span>Subtotal</span><span>${money(subtotal)}</span></div>
    <div><span>Desconto</span><span>${money(subtotal - total)}</span></div>
    <div><strong>Total</strong><strong>${money(total)}</strong></div>
  `;
}

async function saveCurrentOrder() {
  const message = document.getElementById('orderMessage');
  message.textContent = '';
  try {
    const payload = {
      sessionId: getSessionId(),
      regiao: document.getElementById('orderRegion').value,
      cliente: document.getElementById('orderClient').value,
      cnpj: document.getElementById('orderCnpj').value,
      telefone: document.getElementById('orderPhone').value,
      endereco: document.getElementById('orderAddress').value,
      prazo: document.getElementById('orderTerm').value,
      transportadora: document.getElementById('orderCarrier').value,
      transportadora_cnpj: document.getElementById('orderCarrierCnpj').value,
      observacao: document.getElementById('orderNotes').value,
      generateDocuments: false,
      items: orderItems
    };
    const subtotal = orderItems.reduce((sum, item) => sum + item.preco * item.quantidade, 0);
    const total = orderItems.reduce((sum, item) => sum + item.preco * item.quantidade * (1 - item.desconto_percentual / 100), 0);
    payload.subtotal = subtotal;
    payload.desconto_total = subtotal - total;
    payload.total = total;
    const data = await supabaseCreateOrder(payload);
    orderItems = [];
    renderCart();
    message.style.color = 'var(--success)';
    message.textContent = 'Pedido ' + data.numero_pedido + ' salvo com sucesso. Documentos podem ser gerados em uma etapa separada.';
  } catch (error) {
    message.style.color = 'var(--accent)';
    message.textContent = error.message;
  }
}

async function renderSapImport(container) {
  container.innerHTML = `
    <section class="panel">
      <div class="panel-header">
        <div><h2>Importacao SAP</h2><p>Cole CSV ou TSV com cabecalho para importar direto no Supabase.</p></div>
      </div>
      <div class="field-grid">
        <label class="span-4">Tipo
          <select id="importType">
            <option value="PORTAL_ESTOQUE">Estoque</option>
            <option value="PRECO_SP">Preco SP</option>
            <option value="PRECO_PR">Preco PR</option>
            <option value="CATALOGO_PESQUISA">Catalogo pesquisa</option>
            <option value="CRISTIANO">Cadastro produtos</option>
          </select>
        </label>
        <label class="span-12">Dados CSV/TSV<textarea id="importText"></textarea></label>
      </div>
      <div class="actions-row">
        <button class="btn btn-primary" id="applyImportButton" type="button">Importar</button>
        <p id="importMessage" class="form-message"></p>
      </div>
    </section>
  `;
  document.getElementById('applyImportButton').addEventListener('click', async () => {
    const message = document.getElementById('importMessage');
    message.textContent = 'Importando...';
    try {
      const data = await supabaseImportProducts({
        tipo: document.getElementById('importType').value,
        texto: document.getElementById('importText').value
      });
      message.style.color = 'var(--success)';
      message.textContent = 'Importacao aplicada: ' + JSON.stringify(data.summary || data.plan && data.plan.summary || {});
    } catch (error) {
      message.style.color = 'var(--accent)';
      message.textContent = error.message;
    }
  });
}
