async function renderUsers(container) {
  container.innerHTML = '<div class="empty-state">Carregando usuarios...</div>';
  try {
    const users = await supabaseListUsers();
    container.innerHTML = `
      <section class="panel">
        <div class="panel-header">
          <div><h2>Usuarios</h2><p>Senha e permissoes permanecem protegidas no servidor.</p></div>
        </div>
        <form id="userForm" class="field-grid">
          <input id="userId" type="hidden">
          <label class="span-3">Usuario<input id="newUserLogin" required></label>
          <label class="span-3">Nome<input id="newUserName" required></label>
          <label class="span-3">Email<input id="newUserEmail" type="email"></label>
          <label class="span-2">Perfil
            <select id="newUserProfile"><option>VENDEDOR</option><option>SUPERVISOR</option><option>ADMIN</option></select>
          </label>
          <label class="span-3">Senha inicial<input id="newUserPassword" type="password"></label>
          <label class="span-2">Ativo
            <select id="newUserActive"><option value="true">Sim</option><option value="false">Nao</option></select>
          </label>
          <div class="span-12 actions-row">
            <button class="btn btn-primary" type="submit">Salvar usuario</button>
            <p id="userMessage" class="form-message"></p>
          </div>
        </form>
      </section>
      <section class="panel">${renderUsersTable(users)}</section>
    `;
    document.getElementById('userForm').addEventListener('submit', saveUserFromForm);
  } catch (error) {
    container.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
  }
}

function renderUsersTable(users) {
  if (!users.length) return '<div class="empty-state">Nenhum usuario encontrado.</div>';
  return `
    <div class="table-wrap">
      <table>
        <thead><tr><th>Usuario</th><th>Nome</th><th>Email</th><th>Perfil</th><th>Status</th><th>Ultimo login</th></tr></thead>
        <tbody>
          ${users.map((user) => `
            <tr>
              <td>${escapeHtml(user.usuario)}</td>
              <td>${escapeHtml(user.nome)}</td>
              <td>${escapeHtml(user.email)}</td>
              <td>${escapeHtml(user.perfil)}</td>
              <td><span class="status-pill ${user.ativo ? 'ok' : 'warn'}">${user.ativo ? 'Ativo' : 'Inativo'}</span></td>
              <td>${escapeHtml(user.ultimo_login)}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

async function saveUserFromForm(event) {
  event.preventDefault();
  const message = document.getElementById('userMessage');
  message.textContent = 'Salvando...';
  try {
    await supabaseSaveUser({
      id_usuario: document.getElementById('userId').value,
      usuario: document.getElementById('newUserLogin').value,
      nome: document.getElementById('newUserName').value,
      email: document.getElementById('newUserEmail').value,
      perfil: document.getElementById('newUserProfile').value,
      senha: document.getElementById('newUserPassword').value,
      ativo: document.getElementById('newUserActive').value === 'true'
    });
    message.style.color = 'var(--success)';
    message.textContent = 'Usuario salvo.';
    await renderUsers(document.getElementById('content'));
  } catch (error) {
    message.style.color = 'var(--accent)';
    message.textContent = error.message;
  }
}

async function renderLogs(container) {
  container.innerHTML = `
    <section class="panel">
      <div class="panel-header">
        <div><h2>Logs</h2><p>Acoes importantes registradas no Supabase.</p></div>
      </div>
      <form id="logsFilter" class="actions-row">
        <label>Usuario<input id="logsUser"></label>
        <label>Acao<input id="logsAction"></label>
        <button class="btn btn-primary" type="submit">Filtrar</button>
      </form>
    </section>
    <section class="panel" id="logsResults"><div class="empty-state">Carregando logs...</div></section>
  `;
  const load = async () => {
    const target = document.getElementById('logsResults');
  try {
      const logs = await supabaseGetLogs({
        usuario: document.getElementById('logsUser').value,
        acao: document.getElementById('logsAction').value
      });
      target.innerHTML = renderLogsTable(logs);
    } catch (error) {
      target.innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
    }
  };
  document.getElementById('logsFilter').addEventListener('submit', (event) => {
    event.preventDefault();
    load();
  });
  await load();
}

function renderLogsTable(logs) {
  if (!logs.length) return '<div class="empty-state">Nenhum log encontrado.</div>';
  return `
    <div class="table-wrap">
      <table>
        <thead><tr><th>Data</th><th>Usuario</th><th>Acao</th><th>Entidade</th><th>ID</th></tr></thead>
        <tbody>
          ${logs.map((log) => `
            <tr>
              <td>${escapeHtml(log.data_hora)}</td>
              <td>${escapeHtml(log.usuario)}</td>
              <td>${escapeHtml(log.acao)}</td>
              <td>${escapeHtml(log.entidade)}</td>
              <td>${escapeHtml(log.id_entidade)}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}
