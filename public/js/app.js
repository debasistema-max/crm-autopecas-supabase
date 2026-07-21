const MODULES = {
  dashboard: { title: 'Dashboard', permission: 'dashboard', render: renderDashboard },
  products: { title: 'Produtos', permission: 'produtos', render: renderProducts },
  ordersReport: { title: 'Pedidos', permission: ['pedidos', 'novo_pedido'], render: renderOrdersReport },
  quoteReports: { title: 'Cotacoes', permission: ['cotacoes', 'nova_cotacao'], render: renderQuotationsReport },
  partners: { title: 'Parceiros de Negocios', permission: 'parceiros', render: renderBusinessPartners },
  sap: { title: 'Importacao SAP', permission: 'alimentacao', render: renderSapImport },
  importBatches: { title: 'Lotes de Importacao', permission: 'visualizar_lotes_importacao', render: renderImportBatches },
  cadastros: { title: 'Cadastros', permission: 'cadastros', render: renderCadastrosClientes },
  portalCadastros: { title: 'Portal Clientes', permission: 'usuarios', adminOnly: true, render: renderPortalCadastrosControle },
  companySettings: { title: 'Configuracoes da Empresa', permission: ['configuracoes_empresa', 'configuracoes'], adminOnly: true, render: renderCompanySettings },
  users: { title: 'Usuarios', permission: 'usuarios', render: renderUsers },
  logs: { title: 'Logs', permission: 'logs', render: renderLogs }
};

const MODULE_ALIASES = {
  orders: { module: 'ordersReport' },
  quoteCreate: { module: 'quoteReports', action: 'create' },
  settings: { module: 'companySettings' }
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
  window.addEventListener('hashchange', () => {
    const requested = location.hash.replace('#', '') || 'dashboard';
    const route = getModuleRoute(requested);
    if (MODULES[route.module]) openModule(requested);
  });

  setupNavigation();
  const initialHash = location.hash.replace('#', '') || 'dashboard';
  const initial = getModuleRoute(initialHash);
  openModule(MODULES[initial.module] ? initialHash : 'dashboard');
}

function applySessionToShell() {
  document.getElementById('userName').textContent = currentSession.nome || currentSession.usuario || 'Usuario';
  loadCompanySettings().catch((error) => console.warn(error));
}

function setupNavigation() {
  applyNavigationVisibility();
  document.querySelectorAll('.nav-item').forEach((button) => {
    button.addEventListener('click', () => openModule(button.dataset.module));
  });
}

function applyNavigationVisibility() {
  const allowed = Array.isArray(currentSession && currentSession.modules) ? currentSession.modules : null;
  document.querySelectorAll('.nav-item').forEach((button) => {
    const module = MODULES[button.dataset.module];
    const blockedByPermission = !!(module && !hasModuleAccess(module, allowed));
    const blockedByAdmin = !!(module && module.adminOnly && !isCurrentUserAdmin());
    button.hidden = blockedByPermission || blockedByAdmin;
  });
}

async function openModule(name) {
  const route = getModuleRoute(name);
  const moduleName = route.module;
  const module = MODULES[moduleName] || MODULES.dashboard;
  const allowed = currentSession.modules || [];
  const content = document.getElementById('content');
  document.querySelectorAll('.nav-item').forEach((item) => item.classList.toggle('is-active', item.dataset.module === moduleName));
  document.getElementById('pageTitle').textContent = module.title;
  if (location.hash !== `#${moduleName}`) {
    history.replaceState(null, '', `#${moduleName}`);
  }
  document.getElementById('sidebar').classList.remove('is-open');

  if (module.adminOnly && !isCurrentUserAdmin()) {
    content.innerHTML = '<div class="empty-state">Voce nao tem permissao para acessar este modulo.</div>';
    return;
  }

  if (!hasModuleAccess(module, allowed)) {
    content.innerHTML = '<div class="empty-state">Voce nao tem permissao para acessar este modulo.</div>';
    return;
  }

  await module.render(content, { action: route.action });
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
  if (!module) return false;
  if (isCurrentUserAdmin()) return true;
  const permissions = (Array.isArray(module.permission) ? module.permission : [module.permission]).filter(Boolean);
  if (!permissions.length) return true;
  if (!Array.isArray(allowed)) return false;
  return permissions.some((permission) => allowed.includes(permission));
}

function getModuleRoute(name) {
  const alias = MODULE_ALIASES[name];
  if (!alias) return { module: name };
  if (typeof alias === 'string') return { module: alias };
  return alias;
}
