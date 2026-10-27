const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/118_document_portfolio_boundary.sql', 'utf8');

test('shared document boundary enforces portfolio before legacy creation and fiscal finalization', () => {
  const body = sql.slice(sql.indexOf('create or replace function public.commercial_create_document'));
  const guard = body.indexOf("perform public.assert_seller_client_scope(payload,document_type='cotacao')");
  assert.ok(guard > 0);
  assert.ok(guard < body.indexOf('r:=public.commercial_create_document_raw_117'));
  assert.ok(body.indexOf('r:=public.commercial_create_document_raw_117') < body.indexOf('public.finalize_document_base_discount'));
  assert.match(body, /document_type is null or document_type not in/);
  assert.match(body, /jsonb_typeof\(payload\) is distinct from 'object'/);
});

test('all identifiers agree with the canonical client and ownership remains locked during creation', () => {
  assert.match(sql, /resolved_id:=public.resolve_commercial_client\(sap_code,clean_cnpj\)/);
  assert.match(sql, /where c.id=resolved_id for share/);
  assert.match(sql, /target.assigned_seller_id is distinct from actor.id/);
  assert.match(sql, /target.ativo is distinct from true/);
  assert.match(sql, /target.codigo_sap_cliente is distinct from sap_code/);
  assert.match(sql, /supplied_id is not null and target.id::text<>supplied_id/);
  assert.match(sql, /regexp_replace\(coalesce\(target.cnpj,''\),'\\D','','g'\)<>clean_cnpj/);
});

test('anonymous quotation exception cannot hide a supplied client identifier', () => {
  assert.match(sql, /allow_anonymous and sap_code is null and clean_cnpj is null and supplied_id is null/);
  assert.match(sql, /actor.id is null then raise exception 'SEM_PERMISSAO'/);
  assert.match(sql, /actor.perfil::text<>'VENDEDOR' then return/);
});

test('migration changes functions only and keeps anonymous callers and delegates denied', () => {
  assert.doesNotMatch(sql, /\b(drop|truncate|delete|insert|update)\s+(table|from|into|public\.)/i);
  assert.match(sql, /revoke all on function public.commercial_create_document\(text,jsonb\) from public,anon,authenticated/);
  assert.match(sql, /grant execute on function public.commercial_create_document\(text,jsonb\) to authenticated/);
  assert.match(sql, /public.commercial_create_document_raw_090\(text,jsonb\)/);
  assert.match(sql, /public.convert_quotation_to_order_internal_087\(uuid\) from public,anon,authenticated/);
  assert.equal((sql.match(/set search_path=pg_catalog,public/g) || []).length, 3);
});

test('conversion validates the saved client and owner before invoking the snapshot copier', () => {
  const body = sql.slice(sql.indexOf('create or replace function public.convert_quotation_to_order'));
  assert.match(body, /source.user_id is distinct from actor.id/);
  assert.match(body, /q.id=target_quotation_id for update/);
  assert.match(body, /'client_id',source.client_id,'codigo_sap_cliente',source.codigo_sap_cliente/);
  assert.ok(body.indexOf('perform public.assert_seller_client_scope') < body.indexOf('return public.convert_quotation_to_order_raw_090'));
});
