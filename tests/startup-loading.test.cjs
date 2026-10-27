const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const read = file => fs.readFileSync(file, 'utf8');

function appHarness() {
  const listeners = {}, nodes = {}, order = [];
  const node = id => nodes[id] ||= { hidden: true, addEventListener() {} };
  const shell = { _hidden: true, get hidden() { return this._hidden; }, set hidden(value) { order.push('reveal'); this._hidden = value; } };
  const context = vm.createContext({
    document: { addEventListener(event, callback) { listeners[event] = callback; },
      getElementById: node, querySelector: () => shell },
    location: { hash: '#dashboard' }, window: { location: {}, addEventListener() {}, matchMedia: () => ({ addEventListener() {} }) },
    CrmUi: { observeResponsiveTables() {} }, clearStoredSession() { order.push('clear'); }
  });
  const source = read('public/js/app.js');
  for (const match of source.matchAll(/render: (\w+)/g)) context[match[1]] = () => {};
  vm.runInContext(source, context);
  return { context, listeners, nodes, node, order, shell };
}

test('initial HTML hides desktop and mobile menus and loads the logo without waiting for JavaScript', () => {
  const html = read('public/app.html');
  assert.match(html, /class="app-shell" hidden/);
  assert.match(html, /id="mobileNav"[^>]* hidden/);
  assert.match(html, /id="appStartup"[^>]*role="status"/);
  for (const file of ['public/index.html', 'public/app.html']) {
    const source = read(file);
    assert.match(source, /rel="preload" href="assets\/logo-ips-yokomitsu.png" as="image"/);
    assert.doesNotMatch(source, /logo-neutral.svg/);
    const tags = source.match(/<script\b[^>]*src=[^>]+>/g);
    assert.ok(tags.length > 0);
    assert.ok(tags.every(tag => /\bdefer\b/.test(tag)));
    assert.ok(tags.findIndex(tag => /session_guard.js/.test(tag)) < tags.findIndex(tag => /supabase_store.js/.test(tag)));
  }
});

test('slow session verification never boots the shell until trusted profile arrives', async () => {
  const h = appHarness();
  let resolve, bootstrap = 0;
  h.context.validateCurrentSession = () => new Promise(done => { resolve = done; });
  h.context.bootstrapAppShell = () => { bootstrap++; };
  h.listeners.DOMContentLoaded();
  await new Promise(setImmediate);
  assert.equal(bootstrap, 0);
  assert.equal(h.shell.hidden, true);
  resolve({ perfil: 'VENDEDOR', modules: ['produtos'] });
  await new Promise(setImmediate);
  assert.equal(bootstrap, 1);
  assert.equal(vm.runInContext('currentSession.perfil', h.context), 'VENDEDOR');
});

test('invalid and rejected sessions leave menus hidden and redirect to login', async () => {
  for (const failure of [null, new Error('offline')]) {
    const h = appHarness();
    h.context.validateCurrentSession = async () => { if (failure) throw failure; return null; };
    h.context.bootstrapAppShell = () => assert.fail('untrusted session');
    h.listeners.DOMContentLoaded();
    await new Promise(setImmediate);
    assert.equal(h.shell.hidden, true);
    assert.equal(h.context.window.location.href, 'index.html');
    assert.deepEqual(h.order, ['clear']);
  }
});

test('ADMIN and seller menu preparation both finish before revealing the shell', () => {
  for (const profile of ['ADMIN', 'VENDEDOR']) {
    const h = appHarness();
    for (const name of ['applySessionToShell', 'setupSidebarCollapse', 'setupNavigation', 'setupMobileNavigation', 'setupSellerNavigation']) {
      h.context[name] = () => { h.order.push(name); };
    }
    h.context.openModule = () => { h.order.push('openModule'); };
    vm.runInContext(`currentSession = { perfil: '${profile}', modules: [] }; bootstrapAppShell();`, h.context);
    assert.ok(h.order.indexOf('setupSellerNavigation') < h.order.indexOf('reveal'));
    assert.ok(h.order.indexOf('setupNavigation') < h.order.indexOf('reveal'));
    assert.ok(h.order.indexOf('reveal') < h.order.indexOf('openModule'));
    assert.equal(h.node('appStartup').hidden, true);
    assert.equal(h.shell.hidden, false);
  }
});

test('concurrent company identity consumers share one request without caching profile data', async () => {
  let calls = 0, finish;
  const context = vm.createContext({ document: { addEventListener() {} },
    isSupabaseReady: () => true, supabaseClient: { rpc: () => { calls++; return new Promise(resolve => { finish = resolve; }); } } });
  vm.runInContext(read('public/js/company_settings.js'), context);
  const applied = [];
  context.applyCompanyIdentity = settings => applied.push(settings.company_name);
  const first = context.loadCompanySettings(), second = context.loadCompanySettings();
  assert.equal(calls, 1);
  finish({ data: { company_name: 'Empresa Teste' } });
  const [a, b] = await Promise.all([first, second]);
  assert.equal(a, b);
  assert.deepEqual(applied, ['Empresa Teste']);
  await context.loadCompanySettings();
  assert.equal(calls, 1);
});

test('a pending public identity fetch cannot overwrite newer full settings', async () => {
  let finish;
  const context = vm.createContext({ document: { addEventListener() {} },
    isSupabaseReady: () => true, supabaseClient: { rpc: () => new Promise(resolve => { finish = resolve; }) } });
  vm.runInContext(read('public/js/company_settings.js'), context);
  context.applyCompanyIdentity = () => {};
  const pending = context.loadCompanySettings();
  vm.runInContext("cachedCompanySettings = { company_name: 'Nova identidade salva' };", context);
  finish({ data: { company_name: 'Identidade antiga' } });
  assert.equal((await pending).company_name, 'Nova identidade salva');
});
