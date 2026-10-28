const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const source = fs.readFileSync('supabase/functions/crm-admin-users/index.ts', 'utf8');
const sql = fs.readFileSync('supabase/migrations/122_internal_user_provisioning.sql', 'utf8');
const op = '00000000-0122-4000-8000-000000000001';
const id = '00000000-0122-4000-8000-000000000002';
const password = ['fixture', 'only', '123'].join('-');
const payload = { usuario: 'lab', nome: 'LAB', email: 'lab@example.invalid', perfil: 'VENDEDOR', ativo: true, senha: password };

function harness(behavior = {}) {
  let handler;
  const calls = [];
  const profile = { id, usuario: 'lab', nome: 'LAB', email: 'lab@example.invalid', perfil: 'VENDEDOR', ativo: true };
  const caller = {
    auth: { async getUser() { calls.push('getUser'); return { data: { user: behavior.invalidUser ? null : { id: 'actor' } } }; } },
    async rpc(name, args) {
      calls.push(name);
      assert.ok(!JSON.stringify(args || {}).includes(password));
      if (name === 'get_app_session_status') return { data: { active: behavior.active !== false }, error: behavior.sessionError };
      if (name === 'is_admin') return { data: behavior.isAdmin !== false, error: behavior.permissionError };
      if (name === 'prepare_internal_user_provisioning') return behavior.prepareError
        ? { error: { message: behavior.prepareError } } : { data: op };
      assert.fail(name);
    }
  };
  const admin = {
    auth: { admin: {
      async createUser(input) {
        calls.push('createUser');
        assert.equal(input.password, password);
        assert.equal(input.app_metadata.provisioning_operation_id, op);
        assert.equal(input.app_metadata.account_type, 'internal');
        if (behavior.createThrows) throw Error('private-provider-detail');
        return behavior.createError ? { error: { message: 'private-provider-detail' } } : { data: { user: { id } } };
      },
      async deleteUser(target) {
        calls.push('deleteUser'); assert.equal(target, id);
        if (behavior.deleteThrows) throw Error('private-provider-detail');
        return { error: behavior.deleteError ? { message: 'private-provider-detail' } : null };
      }
    } },
    async rpc(name, args) {
      calls.push(name);
      assert.ok(!JSON.stringify(args).includes(password));
      assert.equal(args.operation_id, op);
      if (name === 'complete_internal_user_provisioning') {
        assert.equal(args.target_user_id, id);
        if (behavior.completeThrows) throw Error('private-provider-detail');
        return behavior.completeError ? { error: { message: 'private-provider-detail' } } : { data: profile };
      }
      if (name === 'cancel_internal_user_provisioning') {
        if (behavior.cancelThrows) throw Error('private-provider-detail');
        if (behavior.alreadyCommitted) return { data: { status: 'COMMITTED', profile } };
        return behavior.cancelError ? { error: {} } : { data: { status: 'CANCELLED', cleanup_user_id: behavior.unknownAuth ? null : id } };
      }
      if (name === 'finish_internal_user_cleanup') return { error: behavior.markError ? {} : null };
      assert.fail(name);
    }
  };
  const env = { SUPABASE_URL: behavior.badTarget ? 'https://unknown.supabase.co' : 'https://doenvnjzrecrtvwooaai.supabase.co',
    SUPABASE_ANON_KEY: 'fixture-public', SUPABASE_SERVICE_ROLE_KEY: 'fixture-server' };
  const context = vm.createContext({ Request, Response,
    createClient(url, key) { return key === 'fixture-public' ? caller : admin; },
    Deno: { env: { get: key => env[key] }, serve: fn => { handler = fn; } },
    console: { error() { assert.fail('sensitive error logging'); }, log() { assert.fail('unexpected logging'); } } });
  vm.runInContext(stripTypeScriptTypes(source.replace(/^import[^\n]+\n/, ''), { mode: 'transform' }), context);
  return { calls, async request(body = payload, headers = {}, method = 'POST') {
    const r = await handler(new Request('https://example.invalid/crm-admin-users', { method,
      headers: { Origin: 'https://debasistema-max.github.io', Authorization: 'Bearer fixture', ...headers },
      ...(method === 'POST' ? { body: JSON.stringify(body) } : {}) }));
    const data = await r.json();
    assert.ok(!JSON.stringify(data).includes(password));
    assert.ok(!JSON.stringify(data).includes('private-provider-detail'));
    assert.equal(r.headers.get('Cache-Control'), 'no-store');
    return { status: r.status, data };
  } };
}

test('provisioning rejects invalid identity, replaced session and non-ADMIN before any mutation', async () => {
  for (const behavior of [{ invalidUser: true }, { active: false }, { sessionError: {} }, { isAdmin: false }, { permissionError: {} }]) {
    const h = harness(behavior), r = await h.request();
    assert.ok([401, 403].includes(r.status));
    assert.ok(!h.calls.includes('prepare_internal_user_provisioning'));
    assert.ok(!h.calls.includes('createUser'));
  }
});

test('foreign origins, unknown projects, missing bearer and unsupported methods fail closed', async () => {
  for (const [behavior, headers, method, status] of [
    [{}, { Origin: 'https://evil.invalid' }, 'POST', 403],
    [{ badTarget: true }, {}, 'POST', 503], [{}, { Authorization: '' }, 'POST', 401], [{}, {}, 'GET', 405]
  ]) {
    const h = harness(behavior); assert.equal((await h.request(payload, headers, method)).status, status);
    assert.deepEqual(h.calls, []);
  }
});

test('invalid password, existing-user payload and malformed field types never create Auth users', async () => {
  for (const body of [{ ...payload, senha: 'short' }, { ...payload, senha: 'x'.repeat(73) },
    { ...payload, id: 'existing' }, { ...payload, nome: {} }, [], null]) {
    const h = harness(); assert.equal((await h.request(body)).status, 400);
    assert.ok(!h.calls.includes('createUser'));
  }
});

test('only validated profile data goes to RPC; password goes to admin Auth API and never returns', async () => {
  const h = harness(), r = await h.request();
  assert.equal(r.status, 200); assert.equal(r.data.profile.id, id);
  assert.deepEqual(h.calls, ['getUser', 'get_app_session_status', 'is_admin', 'prepare_internal_user_provisioning',
    'createUser', 'complete_internal_user_provisioning']);
});

test('friendly duplicate errors stop before creating an Auth account', async () => {
  for (const code of ['USUARIO_DUPLICADO', 'EMAIL_DUPLICADO', 'CRIACAO_USUARIO_EM_ANDAMENTO']) {
    const h = harness({ prepareError: code }), r = await h.request();
    assert.equal(r.status, 400); assert.equal(r.data.error, code);
    assert.ok(!h.calls.includes('createUser'));
  }
  const h = harness({ prepareError: 'private-provider-detail' });
  assert.equal((await h.request()).data.error, 'CRIACAO_USUARIO_FALHOU');
});

test('a lost database response is reconciled as success without deleting the committed identity', async () => {
  const h = harness({ completeThrows: true, alreadyCommitted: true }), r = await h.request();
  assert.equal(r.status, 200); assert.equal(r.data.profile.id, id);
  assert.ok(!h.calls.includes('deleteUser'));
});

test('failed profile creation seals cancellation before deleting only the marked new Auth identity', async () => {
  const h = harness({ completeError: true }), r = await h.request();
  assert.equal(r.status, 409);
  assert.deepEqual(h.calls.slice(-3), ['cancel_internal_user_provisioning', 'deleteUser', 'finish_internal_user_cleanup']);
});

test('uncertain Auth creation, compensation failures and journal errors require reconciliation, never false success', async () => {
  for (const behavior of [{ createThrows: true, unknownAuth: true }, { createError: true, unknownAuth: true },
    { completeError: true, deleteError: true }, { completeError: true, deleteThrows: true },
    { completeError: true, cancelThrows: true }, { completeError: true, cancelError: true },
    { completeError: true, markError: true }]) {
    const h = harness(behavior), r = await h.request();
    assert.equal(r.status, 503); assert.equal(r.data.error, 'CRIACAO_USUARIO_REQUER_CONFERENCIA');
    assert.equal(r.data.operation_id, op);
    if (behavior.unknownAuth || behavior.cancelError || behavior.cancelThrows) assert.ok(!h.calls.includes('deleteUser'));
  }
});

test('journal is private, mutation RPCs are service-only and direct browser profile insertion is closed', () => {
  assert.match(sql, /internal_user_provisioning enable row level security/);
  assert.match(sql, /revoke all on public.internal_user_provisioning from public,anon,authenticated,service_role/);
  assert.match(sql, /revoke insert on public.profiles from public,anon,authenticated/);
  assert.match(sql, /revoke insert \(%s\)/);
  assert.match(sql, /public.is_app_session_active\(\) or not public.is_admin\(\)/);
  for (const rpc of ['complete_internal_user_provisioning(uuid,uuid)', 'cancel_internal_user_provisioning(uuid)', 'finish_internal_user_cleanup(uuid)']) {
    assert.ok(sql.includes(`grant execute on function public.${rpc} to service_role`));
  }
  assert.doesNotMatch(sql, /delete from auth.users|alter table public.profiles|grant .*internal_user_provisioning to authenticated/i);
  assert.match(sql, /profile_data=null/);
  assert.match(sql, /provisioning_operation_id' is distinct from op.id::text/);
  assert.match(sql, /op.status<>'PREPARED'/);
});

test('browser errors are allowlisted and do not leak backend error text', async () => {
  const context = vm.createContext({ supabaseClient: { functions: { async invoke() {
    return { error: { context: { async json() { return { error: 'private-provider-detail' }; } } } };
  } } } });
  const store = fs.readFileSync('public/js/supabase_store.js', 'utf8');
  vm.runInContext(store, context);
  await assert.rejects(context.supabaseSaveUser(payload), error => {
    assert.ok(!error.message.includes('private-provider-detail')); return true;
  });
  const saveBody = store.slice(store.indexOf('async function supabaseSaveUser('), store.indexOf('async function supabaseImportProducts('));
  assert.doesNotMatch(saveBody, /auth\.signUp|auth\.setSession/);
});

test('SQL regression requires an empty disposable schema and checks stale ADMIN sessions and atomicity', () => {
  const regression = fs.readFileSync('supabase/tests/122_internal_user_provisioning_regression.sql', 'utf8');
  assert.match(regression, /DISPOSABLE_DATABASE_REQUIRED/);
  assert.match(regression, /EMPTY_SCHEMA_REQUIRED/);
  assert.match(regression, /rollback;\s*$/);
  assert.match(regression, /STALE_ADMIN_SESSION_COMPLETED_PROVISIONING/);
  assert.match(regression, /INACTIVE_ADMIN_COMPLETED_PROVISIONING/);
  assert.match(regression, /PROFILE_JOURNAL_ATOMICITY_FAILED/);
  assert.match(sql, /for share of a,s/);
  assert.doesNotMatch(sql, /select u\.\* into target/);
});
