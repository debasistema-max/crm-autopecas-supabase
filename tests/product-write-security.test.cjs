const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const sql = fs.readFileSync('supabase/migrations/121_product_write_boundary.sql', 'utf8');
const store = fs.readFileSync('public/js/supabase_store.js', 'utf8');

test('canonical product writes are revoked at table and column level for browser roles', () => {
  for (const table of ['products', 'product_sap_data', 'product_branch_prices', 'product_branch_stock', 'product_route_prices']) {
    assert.ok(sql.includes(`'${table}'`));
  }
  assert.match(sql, /revoke insert,update,delete,truncate on public\.%I from public,anon,authenticated/);
  assert.match(sql, /revoke insert \(%s\),update \(%s\) on public\.%I from public,anon,authenticated/);
  assert.match(sql, /a.attnum>0 and not a.attisdropped/);
});

test('migration preserves SELECT, RLS, backend grants, product data and personal activity tables', () => {
  assert.doesNotMatch(sql, /revoke select|alter table|drop |delete from|update public\.|insert into|from service_role/i);
  assert.doesNotMatch(sql, /product_favorites|product_recent_views/);
  assert.match(sql, /^begin;/);
  assert.match(sql, /commit;\s*$/);
});

test('legacy immediate import and raw delegates cannot bypass approved wrappers', () => {
  assert.match(sql, /revoke all on function public.import_products_transactional\(jsonb\) from public,anon,authenticated/);
  for (const name of ['create', 'preview', 'approve', 'commit']) {
    assert.ok(sql.includes(`'${name}_products_import_batch_v0_impl'`));
    assert.doesNotMatch(sql, new RegExp(`revoke all on function public\\.${name}_products_import_batch\\(`));
  }
  assert.ok(sql.includes("'get_products_import_batch_details_v0_impl'"));
  assert.ok(sql.includes("'get_products_import_batches_report_v0_impl'"));
  assert.match(sql, /revoke all on function %s from public,anon,authenticated/);
  assert.doesNotMatch(sql, /create (?:or replace )?function|revoke.*set_product_active|revoke.*deactivate_products/i);
});

test('obsolete import script fails closed without any API call and is not loaded by entry points', async () => {
  const c = vm.createContext({ supabaseClient: new Proxy({}, { get() { assert.fail('unexpected API access'); } }) });
  vm.runInContext(fs.readFileSync('public/js/supabase_import_fix.js', 'utf8'), c);
  await assert.rejects(c.supabaseImportProducts({}), /Importacao antiga desativada/);
  for (const file of ['public/app.html', 'public/index.html']) {
    assert.doesNotMatch(fs.readFileSync(file, 'utf8'), /supabase_import_fix/);
  }
});

test('supported import adapters require a batch and keep approval and commit RPC contracts', async () => {
  const c = vm.createContext({ supabaseClient: new Proxy({}, { get() { assert.fail('unexpected API access'); } }) });
  vm.runInContext(store, c);
  await assert.rejects(c.supabaseImportProducts({}), /Gere a previa/);
  await assert.rejects(c.supabaseApproveProductsImport({}), /Gere a previa/);
  assert.match(store, /rpc\('commit_products_import_batch', \{ batch_id: batchId \}\)/);
  assert.match(store, /rpc\('approve_products_import_batch', \{ batch_id: batchId \}\)/);
  assert.match(store, /rpc\('set_product_active',/);
  assert.match(store, /rpc\('deactivate_products',/);
  assert.doesNotMatch(store, /import_products_transactional|_v0_impl/);
});

test('full-schema SQL regression refuses non-disposable/nonempty databases and exercises actual RPCs', () => {
  const regression = fs.readFileSync('supabase/tests/121_product_import_full_schema_regression.sql', 'utf8');
  assert.match(regression, /DISPOSABLE_DATABASE_REQUIRED/);
  assert.match(regression, /EMPTY_SCHEMA_REQUIRED/);
  assert.match(regression, /rollback;\s*$/);
  for (const rpc of ['create', 'preview', 'approve', 'commit']) {
    assert.ok(regression.includes(`public.${rpc}_products_import_batch(`));
  }
  assert.doesNotMatch(regression, /create (?:or replace )?function public\.(?:create|preview|approve|commit)_products_import_batch/i);
  for (const marker of ['REAL_FIELD_AUDIT_FAILED', 'REAL_ATOMIC_ROLLBACK_FAILED', 'FEED_COMMIT_ACCEPTED', 'SELLER_VALIDATION_ACCEPTED']) {
    assert.ok(regression.includes(marker));
  }
});

test('integration SQL uses real service/worker roles and checks replay, inactive and price preservation', () => {
  const regression = fs.readFileSync('supabase/tests/121_product_integrations_regression.sql', 'utf8');
  assert.match(regression, /DISPOSABLE_DATABASE_REQUIRED/);
  assert.match(regression, /EMPTY_SCHEMA_REQUIRED/);
  assert.match(regression, /set local role service_role;/);
  assert.match(regression, /set session authorization ips_catalog_worker;/);
  assert.match(regression, /reset session authorization;/);
  assert.match(regression, /rollback;\s*$/);
  for (const rpc of ['create_data_sync_batch', 'stage_data_sync_rows', 'validate_data_sync_batch',
    'commit_data_sync_batch_chunk', 'request_installed_catalog_sync', 'claim_installed_catalog_sync',
    'snapshot_installed_catalog_sync', 'finish_installed_catalog_sync']) {
    assert.ok(regression.includes(`public.${rpc}(`));
  }
  for (const marker of ['EXCEL_RETRY_DUPLICATED_AUDIT', 'WRONG_WORKER_TOKEN_ACCEPTED',
    'CATALOG_OVERWROTE_PRICE_ACTIVITY_OR_MANUAL_NOTES', 'BROWSER_CAN_EXECUTE_CATALOG_WORKER_RPC']) {
    assert.ok(regression.includes(marker));
  }
  assert.doesNotMatch(regression, /create (?:or replace )?function public\./i);
});
