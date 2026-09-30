-- Smoke test transacional das etapas 036-040 em homologacao.
-- Usa usuario ADMIN ativo existente e termina com rollback.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $preflight$
declare
  v_missing text[];
  v_admin uuid;
  v_bad_rls text[];
begin
  select array_agg(v.version order by v.version)
  into v_missing
  from unnest(array['036','037','038','039','040']) as v(version)
  where not exists (
    select 1
    from supabase_migrations.schema_migrations sm
    where sm.version = v.version
  );

  if v_missing is not null then
    raise exception 'Migrations ausentes no historico remoto: %', v_missing;
  end if;

  select id
  into v_admin
  from public.profiles
  where perfil = 'ADMIN'
    and ativo
  order by created_at nulls last
  limit 1;

  if v_admin is null then
    raise exception 'ADMIN ativo nao encontrado para smoke test.';
  end if;

  select array_agg(c.relname order by c.relname)
  into v_bad_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'orders',
      'order_items',
      'product_branch_stock',
      'stock_transfer_requests',
      'fiscal_tax_rules'
    )
    and c.relkind = 'r'
    and not c.relrowsecurity;

  if v_bad_rls is not null then
    raise exception 'Tabelas criticas sem RLS: %', v_bad_rls;
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
end
$preflight$;

set local role authenticated;

do $smoke$
declare
  v_transfer_summary jsonb;
  v_transfer_list jsonb;
  v_rule jsonb;
  v_rule_id uuid;
  v_rules jsonb;
  v_tax_rule public.fiscal_tax_rules;
  v_tax_calc jsonb;
begin
  v_transfer_summary := public.get_dashboard_transfer_summary();
  if v_transfer_summary is null or not (v_transfer_summary ? 'pending') or not (v_transfer_summary ? 'active') then
    raise exception 'Resumo de transferencias invalido: %', v_transfer_summary;
  end if;

  v_transfer_list := public.list_stock_transfer_requests(jsonb_build_object('limit', 5));
  if v_transfer_list is null then
    raise exception 'Listagem de transferencias retornou null.';
  end if;

  v_rule := public.save_fiscal_tax_rule(jsonb_build_object(
    'ncm', '12345678',
    'uf_origem', 'SP',
    'uf_destino', 'RJ',
    'operation_type', 'VENDA',
    'customer_type', 'GERAL',
    'icms_percent', 18,
    'ipi_percent', 4,
    'pis_percent', 1.65,
    'cofins_percent', 7.6,
    'effective_from', current_date::text,
    'active', true,
    'notes', 'Smoke homolog rollback'
  ));

  v_rule_id := nullif(v_rule->>'id', '')::uuid;
  if v_rule_id is null then
    raise exception 'Regra fiscal nao retornou id: %', v_rule;
  end if;

  v_rules := public.list_fiscal_tax_rules(jsonb_build_object('ncm', '12345678', 'uf_destino', 'RJ'));
  if jsonb_typeof(v_rules) <> 'array' or jsonb_array_length(v_rules) < 1 then
    raise exception 'Regra fiscal criada nao apareceu na listagem: %', v_rules;
  end if;

  select *
  into v_tax_rule
  from public.fiscal_tax_rules
  where id = v_rule_id;

  v_tax_calc := public.calculate_taxed_unit_price(100, v_tax_rule);
  if coalesce((v_tax_calc->>'final_price')::numeric, 0) <= 100 then
    raise exception 'Calculo fiscal nao aplicou impostos: %', v_tax_calc;
  end if;

  if public.normalize_ncm('12.345.678') <> '12345678' then
    raise exception 'Normalizacao de NCM falhou.';
  end if;

  perform public.delete_fiscal_tax_rule(v_rule_id);

  if to_regprocedure('public.commercial_update_document_items(text,jsonb)') is null then
    raise exception 'commercial_update_document_items ausente.';
  end if;

  if to_regprocedure('public.create_products_import_batch(jsonb)') is null then
    raise exception 'create_products_import_batch ausente.';
  end if;

  raise notice 'OK: smoke homolog 036-040 validado com rollback.';
end
$smoke$;

reset role;

rollback;
