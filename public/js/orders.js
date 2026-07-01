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
  let currentImportPlan = null;
  container.innerHTML = `
    <section class="panel">
      <div class="panel-header">
        <div><h2>Importacao SAP</h2><p>Cole a tabela do Excel ou envie um CSV/TSV. O sistema detecta as colunas automaticamente.</p></div>
      </div>
      <div class="field-grid">
        <label class="span-4">O que atualizar?
          <select id="importType">
            <option value="CRISTIANO" selected>Cadastro produtos</option>
            <option value="PORTAL_ESTOQUE">Estoque</option>
            <option value="PRECO_SP">Preco SP</option>
            <option value="PRECO_PR">Preco PR</option>
            <option value="CATALOGO_PESQUISA">Catalogo pesquisa</option>
          </select>
        </label>
        <label class="span-8">Arquivo
          <input id="importFile" type="file" accept=".csv,.tsv,.txt,text/csv,text/tab-separated-values">
        </label>
        <label class="span-12">Tabela colada
          <textarea id="importText" placeholder="CODIGO IPS;DESCRICAO;MARCA;APLICACAO;ANO;IPI;PRECO S/IMP;PRECO C/IMP;ESTOQUE"></textarea>
        </label>
      </div>
      <div class="actions-row">
        <button class="btn btn-primary" id="previewImportButton" type="button">Verificar dados</button>
        <button class="btn btn-secondary" id="applyImportButton" type="button" disabled>Importar</button>
        <button class="btn btn-ghost" id="clearImportButton" type="button">Limpar</button>
        <p id="importMessage" class="form-message"></p>
      </div>
    </section>
    <section class="panel">
      <details class="import-help">
        <summary>Ver modelos aceitos</summary>
        <div id="importTemplate"></div>
      </details>
      <details class="import-help" id="importMappingDetails">
        <summary>Ajustar colunas detectadas</summary>
        <div id="importMapping">
          <div class="empty-state">Cole ou selecione um arquivo para mapear as colunas.</div>
        </div>
      </details>
    </section>
    <section class="panel" id="importPreview">
      <div class="empty-state">Clique em Verificar dados antes de importar.</div>
    </section>
  `;

  const refreshImportTemplate = () => {
    document.getElementById('importTemplate').innerHTML = renderImportTemplate(document.getElementById('importType').value);
    const copyButton = document.getElementById('copyImportTemplate');
    const fillButton = document.getElementById('fillImportTemplate');
    copyButton.addEventListener('click', async () => {
      await navigator.clipboard.writeText(getImportTemplate(document.getElementById('importType').value).sample);
      document.getElementById('importMessage').style.color = 'var(--success)';
      document.getElementById('importMessage').textContent = 'Modelo copiado.';
    });
    fillButton.addEventListener('click', () => {
      document.getElementById('importText').value = getImportTemplate(document.getElementById('importType').value).sample;
      currentImportPlan = null;
      document.getElementById('applyImportButton').disabled = true;
      document.getElementById('importPreview').innerHTML = '<div class="empty-state">Modelo carregado. Clique em Verificar dados.</div>';
      refreshImportMapping();
    });
  };
  refreshImportTemplate();

  const refreshImportMapping = () => {
    currentImportPlan = null;
    document.getElementById('applyImportButton').disabled = true;
    const target = document.getElementById('importMapping');
    const text = document.getElementById('importText').value;
    try {
      const plan = getImportColumnPlan(text, document.getElementById('importType').value);
      target.innerHTML = renderImportMapping(plan);
    } catch (error) {
      target.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    }
  };

  document.getElementById('importFile').addEventListener('change', async (event) => {
    const file = event.target.files && event.target.files[0];
    if (!file) return;
    document.getElementById('importText').value = await file.text();
    currentImportPlan = null;
    document.getElementById('applyImportButton').disabled = true;
    document.getElementById('importPreview').innerHTML = '<div class="empty-state">Arquivo carregado. Clique em Verificar dados.</div>';
    refreshImportMapping();
  });

  document.getElementById('importText').addEventListener('input', () => {
    currentImportPlan = null;
    document.getElementById('applyImportButton').disabled = true;
    document.getElementById('importPreview').innerHTML = '<div class="empty-state">Clique em Verificar dados antes de importar.</div>';
  });

  document.getElementById('importType').addEventListener('change', () => {
    currentImportPlan = null;
    document.getElementById('applyImportButton').disabled = true;
    refreshImportTemplate();
    refreshImportMapping();
    document.getElementById('importPreview').innerHTML = '<div class="empty-state">Tipo alterado. Clique em Verificar dados.</div>';
  });

  document.getElementById('clearImportButton').addEventListener('click', () => {
    currentImportPlan = null;
    document.getElementById('importText').value = '';
    document.getElementById('importFile').value = '';
    document.getElementById('applyImportButton').disabled = true;
    document.getElementById('importMessage').textContent = '';
    document.getElementById('importMapping').innerHTML = '<div class="empty-state">Cole ou selecione um arquivo para mapear as colunas.</div>';
    document.getElementById('importPreview').innerHTML = '<div class="empty-state">Clique em Verificar dados antes de importar.</div>';
  });

  document.getElementById('previewImportButton').addEventListener('click', async () => {
    const message = document.getElementById('importMessage');
    const preview = document.getElementById('importPreview');
    message.style.color = 'var(--muted)';
    message.textContent = 'Verificando dados...';
    preview.innerHTML = '<div class="empty-state">Lendo dados e comparando com o Supabase...</div>';
    document.getElementById('applyImportButton').disabled = true;
    try {
      if (!document.querySelector('[data-import-map]')) refreshImportMapping();
      currentImportPlan = await supabasePreviewImportProducts({
        tipo: document.getElementById('importType').value,
        texto: document.getElementById('importText').value,
        mapping: getCurrentImportMapping()
      });
      preview.innerHTML = renderImportPreview(currentImportPlan);
      message.style.color = 'var(--success)';
      message.textContent = 'Dados verificados. Pode importar.';
      document.getElementById('applyImportButton').disabled = false;
    } catch (error) {
      currentImportPlan = null;
      preview.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
      message.style.color = 'var(--accent)';
      message.textContent = error.message;
    }
  });

  document.getElementById('applyImportButton').addEventListener('click', async () => {
    const message = document.getElementById('importMessage');
    const preview = document.getElementById('importPreview');
    const button = document.getElementById('applyImportButton');
    if (!currentImportPlan) {
      message.style.color = 'var(--accent)';
      message.textContent = 'Gere a previa antes de aplicar.';
      return;
    }
    button.disabled = true;
    message.style.color = 'var(--muted)';
    message.textContent = 'Importando 0 de ' + currentImportPlan.validRows + ' produtos...';
    try {
      const data = await supabaseImportProducts({
        tipo: document.getElementById('importType').value,
        texto: document.getElementById('importText').value,
        mapping: getCurrentImportMapping(),
        onProgress: (progress) => {
          message.textContent = 'Importando ' + progress.done + ' de ' + progress.total + ' produtos...';
        }
      });
      message.style.color = 'var(--success)';
      message.textContent = 'Importacao aplicada com sucesso.';
      preview.innerHTML = renderImportResult(data.summary);
      currentImportPlan = null;
    } catch (error) {
      message.style.color = 'var(--accent)';
      message.textContent = error.message;
      button.disabled = false;
    }
  });
}

function getImportFieldOptions() {
  return [
    ['', 'Ignorar'],
    ['codigo', 'Codigo'],
    ['descricao', 'Descricao'],
    ['marca', 'Marca'],
    ['aplicacao', 'Aplicacao'],
    ['ano', 'Ano'],
    ['ipi', 'IPI'],
    ['preco_sem_imposto', 'Preco s/ imposto'],
    ['preco_referencia', 'Preco c/ imposto ref.'],
    ['preco_sp', 'Preco SP'],
    ['preco_pr', 'Preco PR'],
    ['estoque', 'Estoque'],
    ['status_estoque', 'Status estoque'],
    ['grupo', 'Grupo'],
    ['categoria', 'Categoria'],
    ['montadora', 'Montadora'],
    ['detalhes', 'Detalhes/palavras-chave'],
    ['oem', 'OEM'],
    ['similar', 'Similar']
  ];
}

function renderImportMapping(plan) {
  if (!plan.headers.length) return '<div class="empty-state">Nenhum cabecalho encontrado.</div>';
  return `
    <div class="panel-header">
      <div><h2>Mapeamento de colunas</h2><p>Confirme para onde cada coluna da sua tabela deve ir.</p></div>
    </div>
    <div class="mapping-grid">
      ${plan.headers.map((header) => renderMappingRow(header, plan.mapping[header], plan.sampleRows)).join('')}
    </div>
  `;
}

function renderMappingRow(header, selected, sampleRows) {
  const normalized = normalizeHeader(header);
  const sample = sampleRows.map((row) => row[normalized]).filter(Boolean).slice(0, 2).join(' | ');
  return `
    <label class="mapping-row">
      <span>
        <strong>${escapeHtml(header)}</strong>
        <small>${escapeHtml(sample)}</small>
      </span>
      <select data-import-map="${escapeHtml(header)}">
        ${getImportFieldOptions().map(([value, label]) => `
          <option value="${escapeHtml(value)}"${value === selected ? ' selected' : ''}>${escapeHtml(label)}</option>
        `).join('')}
      </select>
    </label>
  `;
}

function getCurrentImportMapping() {
  return Object.fromEntries(
    Array.from(document.querySelectorAll('[data-import-map]')).map((select) => [
      select.dataset.importMap,
      select.value
    ])
  );
}

function getImportTemplate(type) {
  const templates = {
    PORTAL_ESTOQUE: {
      title: 'Lista de estoque',
      required: ['codigo', 'estoque'],
      optional: ['status estoque'],
      sample: 'codigo;estoque;status estoque\n7146505811;50+;DISPONIVEL\n6111032201;0;SEM ESTOQUE',
      notes: [
        'Atualiza somente estoque e status de estoque.',
        'Nao altera descricao, marca nem precos.'
      ]
    },
    PRECO_SP: {
      title: 'Tabela de preco SP',
      required: ['codigo', 'preco'],
      optional: ['codigo ips', 'preco c/imp', 'valor', 'pr.unit.(c/i)', 'pr apos desc'],
      sample: 'CODIGO IPS;PRECO C/IMP\n7146505811;522,49\n6111032201;184,90',
      notes: [
        'Atualiza somente o preco SP.',
        'Aceita cabecalhos como PRECO C/IMP, VALOR ou PR.UNIT.(C/I).',
        'Use virgula ou ponto para decimais.'
      ]
    },
    PRECO_PR: {
      title: 'Tabela de preco PR',
      required: ['codigo', 'preco'],
      optional: ['codigo ips', 'preco c/imp', 'valor', 'pr.unit.(c/i)', 'pr apos desc'],
      sample: 'CODIGO IPS;PRECO C/IMP\n7146505811;522,49\n6111032201;179,90',
      notes: [
        'Atualiza somente o preco PR.',
        'Aceita cabecalhos como PRECO C/IMP, VALOR ou PR.UNIT.(C/I).',
        'Use virgula ou ponto para decimais.'
      ]
    },
    CATALOGO_PESQUISA: {
      title: 'Catalogo de pesquisa',
      required: ['codigo'],
      optional: ['descricao', 'marca', 'aplicacao', 'ano', 'grupo', 'categoria', 'montadora', 'detalhes', 'oem', 'similar'],
      sample: 'codigo;descricao;marca;aplicacao;ano;grupo;categoria;montadora;similar\n7146505811;BOMBA DIR.HIDRAULICA;FIAT;PALIO E-TORQ;11/20;DIRECAO;BOMBA;FIAT;7146505810',
      notes: [
        'Enriquece a busca por descricao, aplicacao, montadora, OEM e similares.',
        'Nao precisa conter estoque ou preco.'
      ]
    },
    CRISTIANO: {
      title: 'Cadastro completo de produtos',
      required: ['codigo ou codigo ips'],
      optional: ['descricao', 'marca', 'aplicacao', 'ano', 'ipi', 'preco s/imp', 'preco c/imp', 'estoque', 'grupo', 'categoria', 'montadora', 'oem', 'similar'],
      sample: 'CODIGO IPS;DESCRICAO;MARCA;APLICACAO;ANO;IPI;PRECO S/IMP;PRECO C/IMP;ESTOQUE\n7146505811;BOMBA DIR.HIDRAULICA;FIAT;PALIO E-TORQ;11/20;0;395,00;522,49;50+',
      notes: [
        'Esse formato aceita a planilha com CODIGO IPS, DESCRICAO, MARCA, APLICACAO, ANO, IPI, PRECO S/IMP, PRECO C/IMP e ESTOQUE.',
        'PRECO C/IMP fica apenas como referencia visual nessa importacao e nao altera SP nem PR.',
        'Para atualizar preco estadual, use os tipos Preco SP ou Preco PR separadamente.',
        'Ideal para carga completa ou revisao geral.'
      ]
    }
  };
  return templates[type] || templates.CATALOGO_PESQUISA;
}

function renderImportTemplate(type) {
  const template = getImportTemplate(type);
  return `
    <div class="panel-header">
      <div><h2>Formato esperado</h2><p>${escapeHtml(template.title)}</p></div>
      <div class="actions-row">
        <button class="btn btn-secondary" id="copyImportTemplate" type="button">Copiar modelo</button>
        <button class="btn btn-ghost" id="fillImportTemplate" type="button">Usar exemplo</button>
      </div>
    </div>
    <div class="import-format">
      <div>
        <span>Obrigatorias</span>
        <strong>${template.required.map(escapeHtml).join(', ')}</strong>
      </div>
      <div>
        <span>Aceitas</span>
        <strong>${template.optional.map(escapeHtml).join(', ')}</strong>
      </div>
    </div>
    <pre class="import-sample"><code>${escapeHtml(template.sample)}</code></pre>
    <ul class="import-notes">
      ${template.notes.map((note) => `<li>${escapeHtml(note)}</li>`).join('')}
    </ul>
  `;
}

function renderImportPreview(plan) {
  const invalid = plan.invalidRows.length
    ? `<div class="import-warnings"><strong>${plan.invalidRows.length} linhas ignoradas</strong><span>${plan.invalidRows.slice(0, 5).map((row) => `Linha ${row.linha}: ${escapeHtml(row.motivo)}`).join(' | ')}</span></div>`
    : '';
  return `
    <div class="import-summary">
      <article><span>Linhas</span><strong>${plan.totalRows}</strong></article>
      <article><span>Validas</span><strong>${plan.validRows}</strong></article>
      <article><span>Novos</span><strong>${plan.newCount}</strong></article>
      <article><span>Atualizacoes</span><strong>${plan.existingCount}</strong></article>
      <article><span>Duplicados</span><strong>${plan.duplicates}</strong></article>
    </div>
    ${invalid}
    ${renderImportTable(plan.preview)}
  `;
}

function renderImportResult(summary) {
  return `
    <div class="import-summary">
      <article><span>Recebidos</span><strong>${summary.total_recebido}</strong></article>
      <article><span>Novos</span><strong>${summary.novos}</strong></article>
      <article><span>Atualizados</span><strong>${summary.atualizados}</strong></article>
      <article><span>Ignorados</span><strong>${summary.erros}</strong></article>
    </div>
  `;
}

function renderImportTable(products) {
  if (!products.length) return '<div class="empty-state">Nenhum item para exibir.</div>';
  return `
    <div class="table-wrap import-table">
      <table>
        <thead><tr><th>Codigo</th><th>Descricao</th><th>Estoque</th><th>SP</th><th>PR</th><th>Marca</th></tr></thead>
        <tbody>
          ${products.map((product) => `
            <tr>
              <td>${escapeHtml(product.codigo)}</td>
              <td>${escapeHtml(product.descricao)}</td>
              <td>${escapeHtml(product.estoque)}</td>
              <td>${product.preco_sp == null ? '' : money(product.preco_sp)}</td>
              <td>${product.preco_pr == null ? '' : money(product.preco_pr)}</td>
              <td>${escapeHtml(product.marca)}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}
