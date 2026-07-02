async function renderProducts(container) {
  container.innerHTML = `
    <section class="panel">
      <div class="panel-header">
        <div><h2>Produtos</h2><p>Pesquise por codigo, descricao, marca, grupo, linha, montadora, aplicacao, palavras-chave ou similares.</p></div>
      </div>
      <form id="productSearchForm" class="field-grid">
        <label class="span-4">Termo de busca
          <input id="productTerm" type="search" placeholder="Digite para pesquisar" minlength="2">
        </label>
        <label class="span-2">Estado
          <select id="productRegion"><option>SP</option><option>PR</option></select>
        </label>
        <label class="span-3">Linha
          <select id="productLineFilter"><option value="">Todas</option></select>
        </label>
        <label class="span-3">Grupo
          <select id="productGroupFilter"><option value="">Todos</option></select>
        </label>
        <div class="span-12 actions-row">
          <button class="btn btn-primary" type="submit">Pesquisar</button>
          <button class="btn btn-secondary" id="productGeneralListButton" type="button">Gerar lista geral</button>
          <button class="btn btn-ghost" id="productClearFiltersButton" type="button">Limpar filtros</button>
          <p id="productMessage" class="form-message"></p>
        </div>
      </form>
    </section>
    <section class="panel" id="productResults">
      <div class="empty-state">Os produtos aparecem somente apos uma pesquisa.</div>
    </section>
  `;

  loadProductFilterOptions();

  document.getElementById('productSearchForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    await searchProductsInto(document.getElementById('productResults'), {
      termo: document.getElementById('productTerm').value,
      regiao: document.getElementById('productRegion').value,
      linha: document.getElementById('productLineFilter').value,
      grupo: document.getElementById('productGroupFilter').value,
      limite: 1000
    });
  });

  document.getElementById('productGeneralListButton').addEventListener('click', async () => {
    await searchProductsInto(document.getElementById('productResults'), {
      termo: document.getElementById('productTerm').value,
      regiao: document.getElementById('productRegion').value,
      linha: document.getElementById('productLineFilter').value,
      grupo: document.getElementById('productGroupFilter').value,
      listaGeral: true,
      limite: 5000
    });
  });

  document.getElementById('productClearFiltersButton').addEventListener('click', () => {
    document.getElementById('productTerm').value = '';
    document.getElementById('productLineFilter').value = '';
    document.getElementById('productGroupFilter').value = '';
    document.getElementById('productResults').innerHTML = '<div class="empty-state">Os produtos aparecem somente apos uma pesquisa.</div>';
    document.getElementById('productMessage').textContent = '';
  });
}

async function searchProductsInto(target, params, onAdd) {
  const hasQuery = String(params.termo || '').trim() || params.listaGeral || params.linha || params.grupo;
  if (!hasQuery) {
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
    const showCatalogColumns = !onAdd;
    target.innerHTML = `
      ${renderProductListHeader(products, params, onAdd)}
      <div class="table-wrap">
        <table>
          <thead><tr>${showCatalogColumns ? '<th>Codigo</th><th>Linha</th><th>Grupo</th><th>Veiculos</th><th>Detalhes</th><th>Similares</th>' : '<th>Codigo</th><th>Descricao</th><th>Marca</th><th>Aplicacao</th>'}<th>Estoque</th><th>Preco</th>${onAdd ? '<th></th>' : ''}</tr></thead>
          <tbody>
            ${products.map((p, index) => `
              <tr>
                <td>${escapeHtml(p.codigo)}</td>
                ${showCatalogColumns ? `
                  <td>${escapeHtml(p.linha || p.categoria)}</td>
                  <td>${escapeHtml(p.grupo)}</td>
                  <td>${escapeHtml(p.aplicacao)}</td>
                  <td>${escapeHtml(p.detalhes || p.descricao)}</td>
                  <td>${escapeHtml(p.similar)}</td>
                ` : `
                  <td>${escapeHtml(p.descricao)}</td>
                  <td>${escapeHtml(p.marca)}</td>
                  <td>${escapeHtml(p.aplicacao)}</td>
                `}
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
    } else {
      const exportButton = target.querySelector('[data-export-products]');
      if (exportButton) exportButton.addEventListener('click', () => exportProductsCsv(products, params));
    }
  } catch (error) {
    target.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
  }
}

async function loadProductFilterOptions() {
  const message = document.getElementById('productMessage');
  try {
    const filters = await supabaseListProductFilters();
    fillProductSelect(document.getElementById('productLineFilter'), filters.linhas, 'Todas');
    fillProductSelect(document.getElementById('productGroupFilter'), filters.grupos, 'Todos');
  } catch (error) {
    message.style.color = 'var(--accent)';
    message.textContent = 'Nao foi possivel carregar filtros.';
  }
}

function fillProductSelect(select, values, emptyLabel) {
  select.innerHTML = `<option value="">${escapeHtml(emptyLabel)}</option>` + (values || [])
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`)
    .join('');
}

function renderProductListHeader(products, params, onAdd) {
  if (onAdd) return '';
  const filters = [
    params.listaGeral ? 'lista geral' : '',
    params.linha ? 'linha: ' + params.linha : '',
    params.grupo ? 'grupo: ' + params.grupo : '',
    params.termo ? 'busca: ' + params.termo : ''
  ].filter(Boolean);
  return `
    <div class="panel-header">
      <div><h2>${products.length} produtos</h2><p>${escapeHtml(filters.join(' | ') || 'Resultado da pesquisa')}</p></div>
      <button class="btn btn-secondary" type="button" data-export-products>Baixar CSV</button>
    </div>
  `;
}

function exportProductsCsv(products, params) {
  const headers = ['codigo', 'linha', 'grupo', 'veiculos', 'detalhes', 'similares', 'estoque', 'preco'];
  const lines = [
    headers.join(';'),
    ...products.map((product) => headers.map((field) => {
      if (field === 'preco') return csvCell(product.preco);
      if (field === 'linha') return csvCell(product.linha || product.categoria);
      if (field === 'veiculos') return csvCell(product.aplicacao);
      if (field === 'similares') return csvCell(product.similar);
      return csvCell(product[field]);
    }).join(';'))
  ];
  const blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = 'lista-produtos-' + (params.regiao || 'SP').toLowerCase() + '.csv';
  link.click();
  URL.revokeObjectURL(link.href);
}

function csvCell(value) {
  const text = String(value == null ? '' : value).replace(/"/g, '""');
  return /[;"\n\r]/.test(text) ? `"${text}"` : text;
}
