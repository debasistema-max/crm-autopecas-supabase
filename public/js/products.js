async function renderProducts(container) {
  container.innerHTML = `
    <section class="panel">
      <div class="panel-header">
        <div><h2>Produtos</h2><p>Pesquise por codigo, descricao, marca, grupo, montadora, aplicacao, palavras-chave ou similares.</p></div>
      </div>
      <form id="productSearchForm" class="actions-row">
        <label class="span-6">Termo de busca
          <input id="productTerm" type="search" placeholder="Digite para pesquisar" minlength="2">
        </label>
        <label>Estado
          <select id="productRegion"><option>SP</option><option>PR</option></select>
        </label>
        <button class="btn btn-primary" type="submit">Pesquisar</button>
      </form>
    </section>
    <section class="panel" id="productResults">
      <div class="empty-state">Os produtos aparecem somente apos uma pesquisa.</div>
    </section>
  `;

  document.getElementById('productSearchForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    await searchProductsInto(document.getElementById('productResults'), {
      termo: document.getElementById('productTerm').value,
      regiao: document.getElementById('productRegion').value
    });
  });
}

async function searchProductsInto(target, params, onAdd) {
  if (!String(params.termo || '').trim()) {
    target.innerHTML = '<div class="empty-state">Digite um termo para pesquisar.</div>';
    return;
  }
  target.innerHTML = '<div class="empty-state">Pesquisando produtos...</div>';
  try {
    const products = await supabaseSearchProducts(Object.assign({}, params, { context: onAdd ? 'pedido' : 'produtos' }));
    if (!products.length) {
      target.innerHTML = '<div class="empty-state">Nenhum produto encontrado.</div>';
      return;
    }
    target.innerHTML = `
      <div class="table-wrap">
        <table>
          <thead><tr><th>Codigo</th><th>Descricao</th><th>Marca</th><th>Aplicacao</th><th>Estoque</th><th>Preco</th>${onAdd ? '<th></th>' : ''}</tr></thead>
          <tbody>
            ${products.map((p, index) => `
              <tr>
                <td>${escapeHtml(p.codigo)}</td>
                <td>${escapeHtml(p.descricao)}</td>
                <td>${escapeHtml(p.marca)}</td>
                <td>${escapeHtml(p.aplicacao)}</td>
                <td>${escapeHtml(p.estoque)}</td>
                <td>${money(p.preco)}</td>
                ${onAdd ? `<td><button class="btn btn-secondary" type="button" data-add-product="${index}">Adicionar</button></td>` : ''}
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    `;
    if (onAdd) {
      target.querySelectorAll('[data-add-product]').forEach((button) => {
        button.addEventListener('click', () => onAdd(products[Number(button.dataset.addProduct)]));
      });
    }
  } catch (error) {
    target.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
  }
}
