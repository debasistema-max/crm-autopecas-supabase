const productState = {
  searchTimer: null,
  results: [],
  favorites: new Set(),
  recent: [],
  topSelling: [],
  selected: null,
  params: {},
  offset: 0,
  pageSize: 60,
  loadingMore: false,
  hasMore: false
};

async function renderProducts(container) {
  container.innerHTML = `
    <section class="product-shell">
      <section class="panel product-search-panel">
        <div class="panel-header">
          <div>
            <h2>Produtos</h2>
            <p>Busca rapida por codigo, descricao, marca, OEM, similares, aplicacoes e montadoras.</p>
          </div>
        </div>
        <form id="productSearchForm" class="product-search-grid">
          <label class="product-search-main">Pesquisa inteligente
            <input id="productTerm" type="search" placeholder="Codigo, OEM, similar, veiculo, marca ou aplicacao" autocomplete="off">
          </label>
          <label>UF preco
            <select id="productRegion"><option>SP</option><option>PR</option></select>
          </label>
          <label>Marca
            <select id="productBrandFilter"><option value="">Todas</option></select>
          </label>
          <label>Linha
            <select id="productLineFilter"><option value="">Todas</option></select>
          </label>
          <label>Grupo
            <select id="productGroupFilter"><option value="">Todos</option></select>
          </label>
          <label>Montadora
            <select id="productMakerFilter"><option value="">Todas</option></select>
          </label>
          <label>Disponibilidade
            <select id="productAvailabilityFilter">
              <option value="">Todas</option>
              <option value="disponivel">Disponivel</option>
              <option value="baixo">Estoque baixo</option>
              <option value="alto">Estoque alto</option>
              <option value="zerado">Sem estoque</option>
            </select>
          </label>
          <label>Imagem
            <select id="productImageFilter">
              <option value="">Todas</option>
              <option value="com">Com foto</option>
              <option value="sem">Sem foto</option>
            </select>
          </label>
          <label class="product-toggle"><input id="productOemFilter" type="checkbox"> Com OEM</label>
          <label class="product-toggle"><input id="productFavoritesFilter" type="checkbox"> Favoritos</label>
          <div class="product-search-actions">
            <button class="btn btn-primary" type="submit">Pesquisar</button>
            <button class="btn btn-secondary" id="productGeneralListButton" type="button">Lista geral</button>
            <button class="btn btn-ghost" id="productClearFiltersButton" type="button">Limpar</button>
            <p id="productMessage" class="form-message"></p>
          </div>
        </form>
      </section>

      <section class="product-insights-grid">
        <section class="panel">
          <div class="panel-header"><div><h2>Recentemente consultados</h2><p>Ultimos produtos abertos neste usuario.</p></div></div>
          <div id="productRecentList" class="product-mini-list"><div class="empty-state compact-state">Carregando recentes...</div></div>
        </section>
        <section class="panel">
          <div class="panel-header"><div><h2>Mais vendidos</h2><p>Ranking restrito por perfil quando a migration 024 estiver ativa.</p></div></div>
          <div id="productTopList" class="product-mini-list"><div class="empty-state compact-state">Carregando ranking...</div></div>
        </section>
      </section>

      <section class="product-layout">
        <section class="panel" id="productResults">
          <div class="empty-state">Digite para pesquisar ou gere uma lista geral.</div>
        </section>
        <aside class="panel product-detail-panel" id="productDetail">
          <div class="empty-state compact-state">Selecione um produto para ver foto, OEM, similares, aplicacoes e historicos reais.</div>
        </aside>
      </section>
    </section>
  `;

  await Promise.all([
    loadProductFilterOptions(),
    loadProductSideData()
  ]);

  bindProductSearch();
}

function bindProductSearch() {
  const form = document.getElementById('productSearchForm');
  const term = document.getElementById('productTerm');
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    await runProductSearch();
  });
  term.addEventListener('input', () => {
    window.clearTimeout(productState.searchTimer);
    productState.searchTimer = window.setTimeout(() => runProductSearch({ silentEmpty: true }), 220);
  });
  [
    'productRegion',
    'productBrandFilter',
    'productLineFilter',
    'productGroupFilter',
    'productMakerFilter',
    'productAvailabilityFilter',
    'productImageFilter',
    'productOemFilter',
    'productFavoritesFilter'
  ].forEach((id) => {
    document.getElementById(id).addEventListener('change', () => runProductSearch({ silentEmpty: true }));
  });
  document.getElementById('productGeneralListButton').addEventListener('click', () => runProductSearch({ listaGeral: true }));
  document.getElementById('productClearFiltersButton').addEventListener('click', clearProductFilters);
}

async function runProductSearch(options = {}) {
  productState.offset = 0;
  productState.results = [];
  productState.params = getProductSearchParams(options);
  await searchProductsInto(document.getElementById('productResults'), productState.params);
}

function getProductSearchParams(options = {}) {
  const imageFilter = document.getElementById('productImageFilter').value;
  return {
    termo: document.getElementById('productTerm').value,
    regiao: document.getElementById('productRegion').value,
    marca: document.getElementById('productBrandFilter').value,
    linha: document.getElementById('productLineFilter').value,
    grupo: document.getElementById('productGroupFilter').value,
    montadora: document.getElementById('productMakerFilter').value,
    disponibilidade: document.getElementById('productAvailabilityFilter').value,
    comOem: document.getElementById('productOemFilter').checked,
    comFoto: imageFilter === 'com',
    semFoto: imageFilter === 'sem',
    favoritos: document.getElementById('productFavoritesFilter').checked,
    listaGeral: options.listaGeral === true,
    silentEmpty: options.silentEmpty === true,
    limite: productState.pageSize,
    offset: 0
  };
}

function clearProductFilters() {
  document.getElementById('productTerm').value = '';
  document.getElementById('productBrandFilter').value = '';
  document.getElementById('productLineFilter').value = '';
  document.getElementById('productGroupFilter').value = '';
  document.getElementById('productMakerFilter').value = '';
  document.getElementById('productAvailabilityFilter').value = '';
  document.getElementById('productImageFilter').value = '';
  document.getElementById('productOemFilter').checked = false;
  document.getElementById('productFavoritesFilter').checked = false;
  document.getElementById('productResults').innerHTML = '<div class="empty-state">Digite para pesquisar ou gere uma lista geral.</div>';
  document.getElementById('productDetail').innerHTML = '<div class="empty-state compact-state">Selecione um produto para ver foto, OEM, similares, aplicacoes e historicos reais.</div>';
  document.getElementById('productMessage').textContent = '';
  productState.results = [];
  productState.selected = null;
  productState.offset = 0;
  productState.hasMore = false;
}

async function searchProductsInto(target, params, onAdd) {
  const hasQuery = String(params.termo || '').trim()
    || params.listaGeral
    || params.marca
    || params.linha
    || params.grupo
    || params.montadora
    || params.disponibilidade
    || params.comOem
    || params.comFoto
    || params.semFoto
    || params.favoritos;
  if (!hasQuery) {
    if (!params.silentEmpty) target.innerHTML = '<div class="empty-state">Digite um termo para pesquisar.</div>';
    return;
  }
  target.innerHTML = '<div class="empty-state">Pesquisando produtos...</div>';
  try {
    const products = await supabaseSearchProducts(Object.assign({}, params, { context: onAdd ? 'pedido' : 'produtos' }));
    if (!products.length) {
      target.innerHTML = '<div class="empty-state">Nenhum produto encontrado.</div>';
      return;
    }
    if (onAdd) {
      renderProductPickerResults(target, products, onAdd);
      return;
    }
    productState.results = products;
    productState.offset = products.length;
    productState.hasMore = products.length >= productState.pageSize;
    target.innerHTML = renderProductCatalog(productState.results, params);
    bindProductCatalog(productState.results, params);
  } catch (error) {
    target.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
  }
}

function renderProductPickerResults(target, products, onAdd) {
  target.innerHTML = `
    <div class="table-wrap">
      <table>
        <thead><tr><th>Codigo</th><th>Descricao</th><th>Marca</th><th>Aplicacao</th><th>Estoque</th><th>Preco</th><th></th></tr></thead>
        <tbody>
          ${products.map((p, index) => `
            <tr>
              <td>${escapeHtml(p.codigo)}</td>
              <td>${escapeHtml(p.descricao)}</td>
              <td>${escapeHtml(p.marca)}</td>
              <td>${escapeHtml(p.aplicacao)}</td>
              <td>${escapeHtml(p.estoque)}</td>
              <td>${money(p.preco)}</td>
              <td><button class="btn btn-secondary" type="button" data-add-product="${index}">Selecionar</button></td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
  target.querySelectorAll('[data-add-product]').forEach((button) => {
    button.addEventListener('click', () => onAdd(products[Number(button.dataset.addProduct)]));
  });
}

function renderProductCatalog(products, params) {
  const filters = renderProductFilterSummary(params);
  return `
    <div class="panel-header product-results-header">
      <div><h2>${products.length} produtos</h2><p>${escapeHtml(filters || 'Resultado da pesquisa')}</p></div>
      <button class="btn btn-secondary" type="button" data-export-products>Baixar CSV</button>
    </div>
    <div class="product-card-grid">
      ${products.map((product, index) => renderProductCard(product, index)).join('')}
    </div>
    ${productState.hasMore ? '<div class="product-load-row"><button class="btn btn-secondary" type="button" data-load-more-products>Carregar mais</button></div>' : ''}
  `;
}

function renderProductCard(product, index) {
  const favorite = productState.favorites.has(product.codigo);
  const availability = getProductAvailability(product);
  return `
    <article class="product-card" data-open-product="${index}">
      <button class="product-favorite ${favorite ? 'is-active' : ''}" type="button" data-favorite-product="${index}" aria-label="Favorito">${favorite ? '*' : '+'}</button>
      <div class="product-image">${renderProductImage(product)}</div>
      <div class="product-card-body">
        <div class="product-card-topline">
          <span class="product-code">${escapeHtml(product.codigo)}</span>
          <span class="product-availability ${availability.className}">${escapeHtml(availability.label)}</span>
        </div>
        <h3>${escapeHtml(product.descricao || 'Produto sem descricao')}</h3>
        <p>${escapeHtml([product.marca, product.montadora, product.linha || product.categoria].filter(Boolean).join(' - '))}</p>
        <div class="product-tags">
          ${renderTag('OEM', product.oem)}
          ${renderTag('Similar', product.similar)}
          ${renderTag('Aplicacao', product.aplicacao)}
        </div>
        <div class="product-card-footer">
          <span>${escapeHtml(product.estoque || formatStock(product.estoque_quantidade))}</span>
          <strong>${money(product.preco)}</strong>
        </div>
      </div>
    </article>
  `;
}

function bindProductCatalog(products, params) {
  document.querySelectorAll('[data-open-product]').forEach((card) => {
    card.addEventListener('click', () => openProductDetail(products[Number(card.dataset.openProduct)], params));
  });
  document.querySelectorAll('[data-favorite-product]').forEach((button) => {
    button.addEventListener('click', async (event) => {
      event.stopPropagation();
      const product = products[Number(button.dataset.favoriteProduct)];
      const next = !productState.favorites.has(product.codigo);
      const favorites = await supabaseToggleProductFavorite(product.codigo, next);
      productState.favorites = new Set(favorites);
      button.classList.toggle('is-active', next);
      button.textContent = next ? '*' : '+';
      await refreshProductSideData();
    });
  });
  const exportButton = document.querySelector('[data-export-products]');
  if (exportButton) exportButton.addEventListener('click', () => exportProductsCsv(products, params));
  const loadMoreButton = document.querySelector('[data-load-more-products]');
  if (loadMoreButton) loadMoreButton.addEventListener('click', loadMoreProducts);
}

async function loadMoreProducts() {
  if (productState.loadingMore || !productState.hasMore) return;
  productState.loadingMore = true;
  const button = document.querySelector('[data-load-more-products]');
  if (button) button.textContent = 'Carregando...';
  try {
    const params = Object.assign({}, productState.params, {
      offset: productState.offset,
      limite: productState.pageSize
    });
    const more = await supabaseSearchProducts(Object.assign({}, params, { context: 'produtos' }));
    productState.results = productState.results.concat(more);
    productState.offset += more.length;
    productState.hasMore = more.length >= productState.pageSize;
    document.getElementById('productResults').innerHTML = renderProductCatalog(productState.results, productState.params);
    bindProductCatalog(productState.results, productState.params);
  } finally {
    productState.loadingMore = false;
  }
}

async function openProductDetail(product, params = {}) {
  if (!product) return;
  productState.selected = product;
  try {
    await supabaseRegisterProductView(product.codigo);
  } catch (error) {
    console.info('Modulo Produtos: recente nao registrado.', error.message || error);
  }
  const history = await supabaseGetProductHistory(product.codigo);
  document.getElementById('productDetail').innerHTML = renderProductDetail(product, params, history);
  const closeButton = document.querySelector('[data-close-product-detail]');
  if (closeButton) closeButton.addEventListener('click', closeProductDetail);
  await refreshProductSideData();
}

function closeProductDetail() {
  productState.selected = null;
  document.getElementById('productDetail').innerHTML = '<div class="empty-state compact-state">Selecione um produto para ver foto, OEM, similares, aplicacoes e historicos reais.</div>';
}

function renderProductDetail(product, params, history) {
  const availability = getProductAvailability(product);
  return `
    <div class="product-detail">
      <button class="product-detail-close" type="button" data-close-product-detail aria-label="Fechar detalhes" title="Fechar detalhes">&times;</button>
      <div class="product-detail-image">${renderProductImage(product, true)}</div>
      <div class="product-detail-title">
        <span>${escapeHtml(product.codigo)}</span>
        <h2>${escapeHtml(product.descricao || 'Produto sem descricao')}</h2>
        <strong>${money(getRegionalPrice(product, params.regiao || document.getElementById('productRegion')?.value || 'SP'))}</strong>
        <small class="product-availability ${availability.className}">${escapeHtml(availability.label)}</small>
      </div>
      <dl class="product-detail-grid">
        ${detailItem('Marca', product.marca)}
        ${detailItem('Linha', product.linha || product.categoria)}
        ${detailItem('Grupo', product.grupo)}
        ${detailItem('Montadora', product.montadora)}
        ${detailItem('Ano', product.ano)}
        ${detailItem('OEM', product.oem)}
        ${detailItem('Similares', product.similar)}
        ${detailItem('Aplicacoes', product.aplicacao)}
        ${detailItem('Detalhes', product.detalhes)}
        ${detailItem('Estoque', product.estoque || formatStock(product.estoque_quantidade))}
        ${detailItem('Preco SP', money(product.preco_sp))}
        ${detailItem('Preco PR', money(product.preco_pr))}
      </dl>
      <div class="product-history-grid">
        ${renderHistoryBlock('Historico de precos', history.prices)}
        ${renderHistoryBlock('Historico de estoque', history.stock)}
      </div>
    </div>
  `;
}

function detailItem(label, value) {
  const hasValue = value !== null && value !== undefined && String(value).trim() !== '';
  if (!hasValue) return '';
  return `<div><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(value)}</dd></div>`;
}

function renderHistoryBlock(title, rows) {
  return `
    <section>
      <h3>${escapeHtml(title)}</h3>
      ${(rows || []).length ? `
        <ul>
          ${rows.map((row) => `<li><span>${escapeHtml(formatProductDate(row.changed_at))}</span><strong>${escapeHtml(row.field || '')}</strong><small>${escapeHtml(historyValue(row.old_value))} -> ${escapeHtml(historyValue(row.new_value))}</small></li>`).join('')}
        </ul>
      ` : '<div class="empty-state compact-state">Sem historico real registrado.</div>'}
    </section>
  `;
}

async function loadProductFilterOptions() {
  const message = document.getElementById('productMessage');
  try {
    const filters = await supabaseListProductFilters();
    fillProductSelect(document.getElementById('productBrandFilter'), filters.marcas, 'Todas');
    fillProductSelect(document.getElementById('productLineFilter'), filters.linhas, 'Todas');
    fillProductSelect(document.getElementById('productGroupFilter'), filters.grupos, 'Todos');
    fillProductSelect(document.getElementById('productMakerFilter'), filters.montadoras, 'Todas');
  } catch (error) {
    message.style.color = 'var(--accent)';
    message.textContent = 'Nao foi possivel carregar filtros.';
  }
}

async function loadProductSideData() {
  try {
    const [favorites, recent, topSelling] = await Promise.all([
      supabaseListProductFavorites(),
      supabaseListRecentProducts(6),
      supabaseGetTopSellingProducts(6)
    ]);
    productState.favorites = new Set(favorites);
    productState.recent = recent;
    productState.topSelling = topSelling;
  } catch (error) {
    console.info('Modulo Produtos: dados complementares indisponiveis.', error.message || error);
  }
  renderProductSideLists();
}

async function refreshProductSideData() {
  try {
    const [recent, topSelling] = await Promise.all([
      supabaseListRecentProducts(6),
      supabaseGetTopSellingProducts(6)
    ]);
    productState.recent = recent;
    productState.topSelling = topSelling;
  } catch (error) {
    console.info('Modulo Produtos: nao foi possivel atualizar dados complementares.', error.message || error);
  }
  renderProductSideLists();
}

function renderProductSideLists() {
  const recent = document.getElementById('productRecentList');
  const top = document.getElementById('productTopList');
  if (recent) recent.innerHTML = renderProductMiniList(productState.recent, 'Nenhum produto consultado.');
  if (top) top.innerHTML = renderProductMiniList(productState.topSelling, 'Sem ranking disponivel.');
  document.querySelectorAll('[data-mini-product]').forEach((button) => {
    button.addEventListener('click', async () => {
      const code = button.dataset.miniProduct;
      const product = productState.results.find((item) => item.codigo === code)
        || productState.recent.find((item) => item.codigo === code)
        || productState.topSelling.find((item) => item.codigo === code);
      await openProductDetail(Object.assign({ preco: getRegionalPrice(product, document.getElementById('productRegion')?.value || 'SP') }, product), {
        regiao: document.getElementById('productRegion') ? document.getElementById('productRegion').value : 'SP'
      });
    });
  });
}

function renderProductMiniList(products, emptyText) {
  if (!products || !products.length) return `<div class="empty-state compact-state">${escapeHtml(emptyText)}</div>`;
  return products.map((product) => `
    <button class="product-mini-item" type="button" data-mini-product="${escapeHtml(product.codigo)}">
      <span>${escapeHtml(product.codigo)}</span>
      <strong>${escapeHtml(product.descricao || product.marca || 'Produto')}</strong>
      <small>${escapeHtml(product.quantidade_vendida ? `${product.quantidade_vendida} vendidos` : product.montadora || product.marca || '')}</small>
    </button>
  `).join('');
}

function fillProductSelect(select, values, emptyLabel) {
  select.innerHTML = `<option value="">${escapeHtml(emptyLabel)}</option>` + (values || [])
    .map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`)
    .join('');
}

function renderTag(label, value) {
  return value ? `<span>${escapeHtml(label)}: ${escapeHtml(value)}</span>` : '';
}

function renderProductFilterSummary(params) {
  return [
    params.listaGeral ? 'lista geral' : '',
    params.marca ? 'marca: ' + params.marca : '',
    params.linha ? 'linha: ' + params.linha : '',
    params.grupo ? 'grupo: ' + params.grupo : '',
    params.montadora ? 'montadora: ' + params.montadora : '',
    params.disponibilidade ? 'disponibilidade: ' + params.disponibilidade : '',
    params.comOem ? 'com OEM' : '',
    params.comFoto ? 'com foto' : '',
    params.semFoto ? 'sem foto' : '',
    params.favoritos ? 'favoritos' : '',
    params.termo ? 'busca: ' + params.termo : ''
  ].filter(Boolean).join(' | ');
}

function getProductAvailability(product) {
  const qty = Number(product.estoque_quantidade);
  if (!Number.isFinite(qty) || qty <= 0) return { label: 'Indisponivel', className: 'is-empty' };
  if (qty <= 5) return { label: 'Baixo', className: 'is-low' };
  if (qty > 20) return { label: 'Alto', className: 'is-high' };
  return { label: 'Disponivel', className: 'is-ok' };
}

function renderProductImage(product, large = false) {
  const url = safeProductImageUrl(product.url_imagem);
  if (!url) return '<span>Sem foto</span>';
  return `<img src="${escapeHtml(url)}" alt="${escapeHtml(product.descricao || product.codigo || 'Produto')}" loading="${large ? 'eager' : 'lazy'}" onerror="this.replaceWith(document.createTextNode('Imagem indisponivel'))">`;
}

function safeProductImageUrl(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  try {
    const parsed = new URL(text, window.location.href);
    if (['http:', 'https:', 'data:'].includes(parsed.protocol)) return parsed.href;
    if (text.startsWith('/')) return parsed.href;
  } catch (error) {
    return '';
  }
  return '';
}

function getRegionalPrice(product, region) {
  if (!product) return 0;
  return region === 'PR' ? product.preco_pr : product.preco_sp;
}

function formatStock(value) {
  if (value === null || value === undefined || value === '') return 'Estoque nao informado';
  return String(value);
}

function historyValue(value) {
  if (value == null) return '-';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function formatProductDate(value) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString(APP_CONFIG.locale || 'pt-BR');
}

function exportProductsCsv(products, params) {
  const headers = ['codigo', 'descricao', 'marca', 'linha', 'grupo', 'montadora', 'oem', 'similares', 'aplicacoes', 'estoque', 'preco_sp', 'preco_pr'];
  const lines = [
    headers.join(';'),
    ...products.map((product) => headers.map((field) => {
      if (field === 'linha') return csvCell(product.linha || product.categoria);
      if (field === 'similares') return csvCell(product.similar);
      if (field === 'aplicacoes') return csvCell(product.aplicacao);
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
