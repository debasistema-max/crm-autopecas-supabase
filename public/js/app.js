const MODULES = {
  dashboard: { title: 'Dashboard', permission: 'dashboard', render: renderDashboard },
  products: { title: 'Produtos', permission: 'produtos', render: renderProducts },
  orders: { title: 'Gerar Pedido', permission: 'novo_pedido', render: renderOrders },
  sap: { title: 'Importacao SAP', permission: 'alimentacao', render: renderSapImport },
  users: { title: 'Usuarios', permission: 'usuarios', render: renderUsers },
  logs: { title: 'Logs', permission: 'logs', render: renderLogs }
};

let currentSession = null;

document.addEventListener('DOMContentLoaded', async () => {
  currentSession = getStoredSession();
  if (!currentSession || !getSessionId()) {
    window.location.href = 'index.html';
    return;
  }

  bootstrapAppShell();

  validateCurrentSession()
    .then((session) => {
      if (!session) throw new Error('Sessao expirada.');
      currentSession = session;
      applySessionToShell();
      applyNavigationVisibility();
    })
    .catch(() => {
      clearStoredSession();
      window.location.href = 'index.html';
    });
});

function bootstrapAppShell() {
  applySessionToShell();
  document.getElementById('logoutButton').addEventListener('click', logoutCurrentUser);
  document.getElementById('menuButton').addEventListener('click', () => {
    document.getElementById('sidebar').classList.toggle('is-open');
  });

  setupNavigation();
  const initial = location.hash.replace('#', '') || 'dashboard';
  openModule(MODULES[initial] ? initial : 'dashboard');
}

function applySessionToShell() {
  document.getElementById('userName').textContent = currentSession.nome || currentSession.usuario || 'Usuario';
}

function setupNavigation() {
  applyNavigationVisibility();
  document.querySelectorAll('.nav-item').forEach((button) => {
    button.addEventListener('click', () => openModule(button.dataset.module));
  });
}

function applyNavigationVisibility() {
  const allowed = currentSession.modules || [];
  document.querySelectorAll('.nav-item').forEach((button) => {
    const module = MODULES[button.dataset.module];
    button.hidden = !!(module && allowed.length && !allowed.includes(module.permission));
  });
}

async function openModule(name) {
  const module = MODULES[name] || MODULES.dashboard;
  const allowed = currentSession.modules || [];
  const content = document.getElementById('content');
  document.querySelectorAll('.nav-item').forEach((item) => item.classList.toggle('is-active', item.dataset.module === name));
  document.getElementById('pageTitle').textContent = module.title;
  location.hash = name;
  document.getElementById('sidebar').classList.remove('is-open');

  if (allowed.length && !allowed.includes(module.permission)) {
    content.innerHTML = '<div class="empty-state">Voce nao tem permissao para acessar este modulo.</div>';
    return;
  }

  await module.render(content);
  content.focus();
}

async function logoutCurrentUser() {
  try {
    await supabaseLogout();
  } catch (error) {
    console.warn(error);
  } finally {
    clearStoredSession();
    window.location.href = 'index.html';
  }
}
