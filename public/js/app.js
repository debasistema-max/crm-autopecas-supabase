const MODULES = {
  dashboard: { title: 'Dashboard', permission: 'dashboard', render: renderDashboard },
  products: { title: 'Produtos', permission: 'produtos', render: renderProducts },
  ordersReport: { title: 'Pedidos', permission: ['pedidos', 'novo_pedido'], render: renderOrdersReport },
  quoteReports: { title: 'Cotacoes', permission: ['cotacoes', 'nova_cotacao'], render: renderQuotationsReport },
  partners: { title: 'Parceiros de Negocios', permission: 'parceiros', render: renderBusinessPartners },
  sap: { title: 'Importacao SAP', permission: 'alimentacao', render: renderSapImport },
  cadastros: { title: 'Cadastros', permission: 'cadastros', render: renderCadastrosClientes },
  portalCadastros: { title: 'Portal Clientes', permission: 'usuarios', adminOnly: true, render: renderPortalCadastrosControle },
  users: { title: 'Usuarios', permission: 'usuarios', render: renderUsers },
  logs: { title: 'Logs', permission: 'logs', render: renderLogs }
};

const MODULE_ALIASES = {
  orders: 'ordersReport',
  quoteCreate: 'quoteReports'
};

let currentSession = null;

document.addEventListener('DOMContentLoaded', async () => {
  currentSession = getStoredSession();
  if (!currentSession || !getSessionId()) {
    window.location.href = 'index.html';
    return;
  }

  validateCurrentSession()
    .then((session) => {
      if (!session) throw new Error('Sessao expirada.');
      currentSession = session;
      bootstrapAppShell();
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
  const initialHash = location.hash.replace('#', '') || 'dashboard';
  const initial = MODULE_ALIASES[initialHash] || initialHash;
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
    const blockedByPermission = !!(module && !hasModuleAccess(module, allowed));
    const blockedByAdmin = !!(module && module.adminOnly && !isCurrentUserAdmin());
    button.hidden = blockedByPermission || blockedByAdmin;
  });
}

async function openModule(name) {
  const moduleName = MODULE_ALIASES[name] || name;
  const module = MODULES[moduleName] || MODULES.dashboard;
  const allowed = currentSession.modules || [];
  const content = document.getElementById('content');
  document.querySelectorAll('.nav-item').forEach((item) => item.classList.toggle('is-active', item.dataset.module === moduleName));
  document.getElementById('pageTitle').textContent = module.title;
  location.hash = moduleName;
  document.getElementById('sidebar').classList.remove('is-open');

  if (module.adminOnly && !isCurrentUserAdmin()) {
    content.innerHTML = '<div class="empty-state">Voce nao tem permissao para acessar este modulo.</div>';
    return;
  }

  if (!hasModuleAccess(module, allowed)) {
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

function isCurrentUserAdmin() {
  return String(currentSession && currentSession.perfil || '').toUpperCase() === 'ADMIN';
}

function hasModuleAccess(module, allowed) {
  if (!allowed.length) return true;
  const permissions = Array.isArray(module.permission) ? module.permission : [module.permission];
  return permissions.some((permission) => allowed.includes(permission));
}
