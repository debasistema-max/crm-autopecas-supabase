const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const sql = fs.readFileSync('supabase/migrations/120_server_audit_boundary.sql', 'utf8');

test('browser DML is revoked at table and column level; legacy events are not relabeled as verified', () => {
  assert.match(sql, /revoke insert,update,delete on public.logs from public,anon,authenticated/);
  assert.match(sql, /revoke insert \(%s\), update \(%s\)/);
  assert.match(sql, /drop policy if exists logs_insert/);
  assert.match(sql, /audit_source text not null default 'LEGACY_UNVERIFIED'/);
  assert.doesNotMatch(sql, /update public.logs|delete from public.logs|truncate/i);
});

test('origin trigger is INVOKER and rejects browser roles even if a grant is restored', () => {
  const body = sql.slice(sql.indexOf('create function public.stamp_server_audit_origin'),
    sql.indexOf('create function public.audit_crm_record_mutation'));
  assert.match(body, /security invoker/);
  assert.match(body, /current_user not in \('postgres','supabase_admin','service_role'\)/);
  assert.match(body, /new.audit_source:='SERVER'/);
  assert.match(body, /new.data_hora:=clock_timestamp\(\)/);
});

test('real mutations generate an atomic audit with server actor and minimized values', () => {
  assert.match(sql, /after insert or update or delete/);
  for (const table of ['profiles', 'carriers', 'cadastros_clientes', 'company_settings', 'settings']) {
    assert.ok(sql.includes(`'${table}'`));
  }
  assert.match(sql, /where p.id=auth.uid\(\)/);
  assert.match(sql, /'changed_fields',changed_fields/);
  assert.match(sql, /k in \('perfil','ativo','status'\)/);
  assert.doesNotMatch(sql, /when others|dados_novos\)\s*values[^;]*after_row/);
  assert.match(sql, /k not in \('created_at','updated_at','ultimo_login'\)/);
});

test('session events come from actual winner transitions without changing claim/release implementations', () => {
  assert.match(sql, /new.active_session_id is not distinct from previous_id then return new/);
  assert.match(sql, /new.active_session_id is null then 'LOGOUT' else 'LOGIN'/);
  assert.match(sql, /where p.id=new.user_id/);
  assert.match(sql, /coalesce\(actor_name,'B2B'\)/);
  assert.match(sql, /after insert or update on public.app_sessions/);
  assert.doesNotMatch(sql, /(?:create|alter).*function public\.(claim_app_session|release_app_session)/i);
});

test('audit trigger helpers cannot be executed as public RPCs', () => {
  for (const name of ['stamp_server_audit_origin', 'audit_crm_record_mutation', 'audit_app_session_transition']) {
    assert.ok(sql.includes(`revoke all on function public.${name}() from public,anon,authenticated`));
  }
});

test('obsolete browser logging fails closed without even reading user identity', async () => {
  const c = vm.createContext({ supabaseClient: new Proxy({}, { get() { assert.fail('unexpected API access'); } }) });
  vm.runInContext(fs.readFileSync('public/js/supabase_store.js', 'utf8'), c);
  await assert.rejects(c.supabaseLog('CANCELAR_PEDIDO', 'orders', 'fictional', { usuario: 'FAKE ADMIN' }), /Auditoria exclusiva do servidor/);
});

test('core browser mutations no longer send separate audit events', () => {
  const store = fs.readFileSync('public/js/supabase_store.js', 'utf8');
  assert.equal((store.match(/supabaseLog\(/g) || []).length, 1);
  assert.doesNotMatch(store, /from\('logs'\)\.insert/);
  assert.doesNotMatch(fs.readFileSync('public/js/company_settings.js', 'utf8'), /supabaseLog/);
});

test('log UI distinguishes new server events from unverified history and escapes actors', () => {
  const c = vm.createContext({});
  vm.runInContext(fs.readFileSync('public/js/utils/format.js', 'utf8'), c);
  vm.runInContext(fs.readFileSync('public/js/users.js', 'utf8'), c);
  const html = c.renderLogsTable([
    { usuario: '<img>', audit_source: 'SERVER' },
    { usuario: 'LAB', audit_source: 'LEGACY_UNVERIFIED' },
    { usuario: 'OLD', audit_source: '<script>' }
  ]);
  assert.match(html, /<th>Origem<\/th>/);
  assert.match(html, /Servidor/);
  assert.equal((html.match(/Legado \(nao verificado\)/g) || []).length, 2);
  assert.ok(html.includes('&lt;img&gt;'));
  assert.ok(!html.includes('<script>'));
});

test('log queries request provenance; updated entry points invalidate audit-related scripts', () => {
  const store = fs.readFileSync('public/js/supabase_store.js', 'utf8');
  assert.match(store, /id_entidade, audit_source/);
  for (const file of ['public/app.html', 'public/index.html']) {
    const html = fs.readFileSync(file, 'utf8');
    assert.ok(html.includes('js/supabase_store.js?v=20261028-internal-users-1'));
    assert.ok(html.includes('js/company_settings.js?v=20261028-server-audit-1'));
  }
  assert.ok(fs.readFileSync('public/app.html', 'utf8').includes('js/users.js?v=20261028-internal-users-1'));
});
