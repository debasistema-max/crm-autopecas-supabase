const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const migration = fs.readFileSync('supabase/migrations/119_client_commercial_field_boundary.sql', 'utf8');

function fixture() {
  const calls = [];
  let response = { data: null, error: null };
  const c = vm.createContext({ console,
    onlyDigits: value => String(value).replace(/\D/g, ''),
    isValidEmail: value => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value),
    supabaseClient: {
      from() { assert.fail('client access must go through a scoped RPC'); },
      async rpc(name, parameters) { calls.push({ name, parameters }); return response; }
    }
  });
  vm.runInContext(fs.readFileSync('public/js/supabase_store.js', 'utf8'), c);
  c.supabaseLog = () => assert.fail('audit must be atomic on the server');
  return { c, calls, respond: value => { response = value; } };
}

test('table-wide and secret-column SELECT are revoked; explicit ordinary fields retain RLS access', () => {
  assert.match(migration, /revoke select on public.clients from public,anon,authenticated/);
  assert.match(migration, /revoke select\(commercial_discount_percent\) on public.clients from public,anon,authenticated/);
  const grant = migration.match(/grant select\(([^)]+)\)\s+on public.clients to authenticated/)[1];
  assert.ok(grant.includes('id,nome,cnpj'));
  assert.ok(grant.includes('assigned_seller_id'));
  assert.ok(!grant.includes('commercial_discount_percent'));
  assert.doesNotMatch(migration, /disable row level security|drop policy|truncate|drop table/i);
});

test('lookup has a fixed field allowlist, server portfolio scope and no seller discount key', () => {
  const body = migration.slice(migration.indexOf('create function public.find_business_client_scoped'),
    migration.indexOf('create function public.save_business_client_scoped'));
  assert.match(body, /lookup_field not in \('codigo_sap_cliente','cnpj'\)/);
  assert.match(body, /c.assigned_seller_id=actor.id/);
  assert.match(body, /actor.perfil::text='VENDEDOR' then '\{\}'::jsonb/);
  assert.match(body, /actor:=public.commercial_active_profile\(\)/);
  assert.doesNotMatch(body, /(?:^|\n)\s*execute\b|\bformat\(/i);
});

test('save enforces staff and ADMIN discount permissions, records the authenticated actor and keeps audit in transaction', () => {
  const body = migration.slice(migration.indexOf('create function public.save_business_client_scoped'));
  assert.match(body, /actor.id is null or actor.perfil::text='VENDEDOR'/);
  assert.match(body, /public.has_module\('parceiros'\)/);
  assert.match(body, /actor.perfil::text<>'ADMIN' and discount is distinct from coalesce\(previous_discount,0\)/);
  assert.match(body, /public.max_discount_percent\(\)/);
  assert.match(body, /pg_advisory_xact_lock/);
  assert.match(body, /where c.id=target_id for update/);
  assert.match(body, /seller_id is distinct from previous_seller and seller_id is not null/);
  assert.match(body, /values\(actor.id,actor.usuario,'SALVAR_CLIENTE'/);
  assert.ok(body.indexOf('insert into public.logs') < body.indexOf('return result'));
  assert.doesNotMatch(body, /exception when|payload->>'(?:user_id|perfil|usuario)'/i);
});

test('new RPCs reject PUBLIC and anon, while authenticated execution is explicitly granted', () => {
  for (const signature of ['find_business_client_scoped(text,text)', 'save_business_client_scoped(jsonb)']) {
    assert.ok(migration.includes(`revoke all on function public.${signature} from public,anon,authenticated`));
    assert.ok(migration.includes(`grant execute on function public.${signature} to authenticated`));
  }
  assert.equal((migration.match(/security definer set search_path=pg_catalog,public/g) || []).length, 2);
  assert.equal((migration.match(/not coalesce\(public.is_app_session_active\(\),false\)/g) || []).length, 2);
});

test('save uses one server RPC with normalized fields; no direct table or duplicate browser audit', async () => {
  const h = fixture();
  const row = { id: 'fictional-client', commercial_discount_percent: 5 };
  h.respond({ data: row });
  assert.equal(await h.c.supabaseSaveBusinessClient({ id: row.id, nome: ' LAB ONLY ', cnpj: '00.000.000/0001-01',
    email: 'lab@example.invalid', commercial_discount_percent: 5, assigned_seller_id: 'fictional-seller' }), row);
  assert.equal(h.calls.length, 1);
  assert.equal(h.calls[0].name, 'save_business_client_scoped');
  assert.equal(h.calls[0].parameters.payload.nome, 'LAB ONLY');
  assert.equal(h.calls[0].parameters.payload.cnpj, '00000000000101');
  assert.equal(h.calls[0].parameters.payload.commercial_discount_percent, 5);
});

test('lookup uses the scoped endpoint and preserves null when a client is outside the visible scope', async () => {
  const h = fixture();
  assert.equal(await h.c.supabaseFindBusinessClient('codigo_sap_cliente', 'LAB-MISSING'), null);
  assert.equal(h.calls[0].name, 'find_business_client_scoped');
  assert.equal(h.calls[0].parameters.lookup_field, 'codigo_sap_cliente');
  assert.equal(h.calls[0].parameters.lookup_value, 'LAB-MISSING');
});

test('RPC errors never fall back to the old unprotected client queries', async () => {
  const h = fixture();
  h.respond({ error: new Error('LAB RPC unavailable') });
  await assert.rejects(h.c.supabaseFindBusinessClient('cnpj', '00000000000101'), /LAB RPC unavailable/);
  await assert.rejects(h.c.supabaseSaveBusinessClient({ nome: 'LAB ONLY' }), /LAB RPC unavailable/);
  assert.equal(h.calls.length, 2);
});

test('invalid discounts, empty names and invalid emails are rejected before any API call', async () => {
  for (const invalid of [NaN, Infinity, -1]) {
    const h = fixture();
    await assert.rejects(h.c.supabaseSaveBusinessClient({ nome: 'LAB ONLY', commercial_discount_percent: invalid }), /desconto comercial valido/);
    assert.equal(h.calls.length, 0);
  }
  const h = fixture();
  await assert.rejects(h.c.supabaseSaveBusinessClient({ nome: ' ' }), /nome do cliente/);
  await assert.rejects(h.c.supabaseSaveBusinessClient({ nome: 'LAB ONLY', email: 'invalid' }), /email valido/);
  assert.equal(h.calls.length, 0);
});

test('portal promotion preserves an existing discount and seller through the scoped lookup', async () => {
  const h = fixture();
  h.c.supabaseClient.rpc = async (name, params) => {
    h.calls.push({ name, parameters: params });
    if (name === 'find_business_client_scoped') return { data: { id: 'fictional-client', commercial_discount_percent: 6, assigned_seller_id: 'fictional-seller' } };
    return { data: params.payload };
  };
  const result = await h.c.supabaseSaveBusinessClientFromCadastro({ codigo_sap_cliente: 'LAB-A', razao_social: 'LAB ONLY', cnpj: '00000000000101' });
  assert.equal(result.id, 'fictional-client');
  assert.equal(result.commercial_discount_percent, 6);
  assert.equal(result.assigned_seller_id, 'fictional-seller');
  assert.equal(h.calls.length, 2);
});

test('entry points invalidate the store cache for the scoped client RPCs', () => {
  for (const file of ['public/app.html', 'public/index.html']) {
    assert.match(fs.readFileSync(file, 'utf8'), /js\/supabase_store\.js\?v=20261028-internal-users-1/);
  }
});
