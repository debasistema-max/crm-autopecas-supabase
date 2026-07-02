async function renderCadastrosClientes(container) {
  container.innerHTML = `
    <section class="panel">
      <div class="panel-header">
        <div>
          <h2>Cadastros de Clientes</h2>
          <p>Solicitacoes recebidas pelo portal publico.</p>
        </div>
      </div>
      <div class="field-grid">
        <label class="span-6">Pesquisar
          <input id="cadastroSearch" placeholder="Protocolo, codigo SAP, CNPJ, razao social ou cidade">
        </label>
        <label class="span-3">Status
          <select id="cadastroStatusFilter">
            <option value="">Todos</option>
            ${cadastroStatusOptions().map((status) => `<option value="${escapeHtml(status)}">${escapeHtml(status)}</option>`).join('')}
          </select>
        </label>
        <div class="span-3 actions-row align-end">
          <button class="btn btn-primary" id="cadastroFilterButton" type="button">Filtrar</button>
        </div>
      </div>
      <p id="cadastroMessage" class="form-message"></p>
    </section>
    <section class="panel" id="cadastrosList">
      <div class="empty-state">Carregando cadastros...</div>
    </section>
  `;

  const load = async () => {
    const message = document.getElementById('cadastroMessage');
    const list = document.getElementById('cadastrosList');
    message.textContent = '';
    list.innerHTML = '<div class="empty-state">Carregando cadastros...</div>';
    try {
      const rows = await supabaseListCadastrosClientes({
        termo: document.getElementById('cadastroSearch').value.trim(),
        status: document.getElementById('cadastroStatusFilter').value
      });
      list.innerHTML = renderCadastrosTable(rows);
      bindCadastroRows(load);
    } catch (error) {
      list.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    }
  };

  document.getElementById('cadastroFilterButton').addEventListener('click', load);
  document.getElementById('cadastroSearch').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') load();
  });
  await load();
}

function renderCadastrosTable(rows) {
  if (!rows.length) return '<div class="empty-state">Nenhum cadastro encontrado.</div>';
  return `
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Protocolo</th>
            <th>Empresa</th>
            <th>CNPJ</th>
            <th>Cidade/UF</th>
            <th>Contato</th>
            <th>Codigo SAP</th>
            <th>Status</th>
            <th>Observacoes internas</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${rows.map(renderCadastroRow).join('')}
        </tbody>
      </table>
    </div>
  `;
}

function renderCadastroRow(row) {
  return `
    <tr data-cadastro-id="${escapeHtml(row.id)}">
      <td>
        <strong>${escapeHtml(row.protocolo || '')}</strong>
        <small>${escapeHtml(formatDateTime(row.created_at))}</small>
      </td>
      <td>
        <strong>${escapeHtml(row.razao_social || row.nome_fantasia || '')}</strong>
        <small>${escapeHtml(row.segmento || '')}</small>
      </td>
      <td>${escapeHtml(formatCnpj(row.cnpj || ''))}</td>
      <td>${escapeHtml([row.cidade, row.estado].filter(Boolean).join('/'))}</td>
      <td>
        <strong>${escapeHtml(row.whatsapp || row.telefone || '')}</strong>
        <small>${escapeHtml(row.email_compras || '')}</small>
      </td>
      <td>
        <input data-cadastro-codigo-sap value="${escapeHtml(row.codigo_sap_cliente || '')}" placeholder="Codigo SAP">
      </td>
      <td>
        <select data-cadastro-status>
          ${cadastroStatusOptions().map((status) => `<option value="${escapeHtml(status)}"${status === row.status ? ' selected' : ''}>${escapeHtml(status)}</option>`).join('')}
        </select>
      </td>
      <td><textarea data-cadastro-notes>${escapeHtml(row.observacoes_internas || '')}</textarea></td>
      <td><button class="btn btn-secondary" type="button" data-save-cadastro>Salvar</button></td>
    </tr>
  `;
}

function bindCadastroRows(reload) {
  document.querySelectorAll('[data-save-cadastro]').forEach((button) => {
    button.addEventListener('click', async () => {
      const row = button.closest('[data-cadastro-id]');
      const message = document.getElementById('cadastroMessage');
      button.disabled = true;
      message.style.color = 'var(--muted)';
      message.textContent = 'Salvando cadastro...';
      try {
        await supabaseUpdateCadastroCliente({
          id: row.dataset.cadastroId,
          status: row.querySelector('[data-cadastro-status]').value,
          codigo_sap_cliente: row.querySelector('[data-cadastro-codigo-sap]').value,
          observacoes_internas: row.querySelector('[data-cadastro-notes]').value
        });
        message.style.color = 'var(--success)';
        message.textContent = 'Cadastro atualizado.';
        await reload();
      } catch (error) {
        message.style.color = 'var(--accent)';
        message.textContent = error.message;
      } finally {
        button.disabled = false;
      }
    });
  });
}

function cadastroStatusOptions() {
  return ['Novo', 'Em analise', 'Pendente', 'Aprovado', 'Reprovado', 'Finalizado SAP'];
}

function formatCnpj(value) {
  const digits = String(value || '').replace(/\D/g, '').slice(0, 14);
  return digits
    .replace(/^(\d{2})(\d)/, '$1.$2')
    .replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/\.(\d{3})(\d)/, '.$1/$2')
    .replace(/(\d{4})(\d)/, '$1-$2');
}

function formatDateTime(value) {
  if (!value) return '';
  return new Intl.DateTimeFormat(APP_CONFIG.locale, {
    dateStyle: 'short',
    timeStyle: 'short'
  }).format(new Date(value));
}
