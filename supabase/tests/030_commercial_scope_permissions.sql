-- Validacao transacional das migrations 023-030.
-- Execute em homologacao apos aplicar 017..030. O rollback final remove todos os dados semeados.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $setup$
declare
  v_admin uuid := '10000000-0000-4000-8000-000000000001';
  v_supervisor uuid := '10000000-0000-4000-8000-000000000002';
  v_seller_in uuid := '10000000-0000-4000-8000-000000000003';
  v_seller_out uuid := '10000000-0000-4000-8000-000000000004';
  v_inactive uuid := '10000000-0000-4000-8000-000000000005';
  v_no_module uuid := '10000000-0000-4000-8000-000000000006';
  v_branch_sp uuid;
  v_branch_pr uuid;
  v_order_in uuid := '30000000-0000-4000-8000-000000000001';
  v_order_out uuid := '30000000-0000-4000-8000-000000000002';
  v_order_legacy uuid := '30000000-0000-4000-8000-000000000003';
  v_quote_in uuid := '40000000-0000-4000-8000-000000000001';
  v_quote_out uuid := '40000000-0000-4000-8000-000000000002';
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crm-test-admin@example.com', '', now(), now(), now()),
    (v_supervisor, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crm-test-supervisor@example.com', '', now(), now(), now()),
    (v_seller_in, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crm-test-vendedor-in@example.com', '', now(), now(), now()),
    (v_seller_out, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crm-test-vendedor-out@example.com', '', now(), now(), now()),
    (v_inactive, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crm-test-inativo@example.com', '', now(), now(), now()),
    (v_no_module, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'crm-test-sem-modulo@example.com', '', now(), now(), now());

  insert into public.profiles (id, usuario, nome, email, perfil, ativo)
  values
    (v_admin, 'crm_test_admin', 'CRM Test Admin', 'crm-test-admin@example.com', 'ADMIN', true),
    (v_supervisor, 'crm_test_supervisor', 'CRM Test Supervisor', 'crm-test-supervisor@example.com', 'SUPERVISOR', true),
    (v_seller_in, 'crm_test_vendedor_in', 'CRM Test Vendedor SP', 'crm-test-vendedor-in@example.com', 'VENDEDOR', true),
    (v_seller_out, 'crm_test_vendedor_out', 'CRM Test Vendedor PR', 'crm-test-vendedor-out@example.com', 'VENDEDOR', true),
    (v_inactive, 'crm_test_inativo', 'CRM Test Inativo', 'crm-test-inativo@example.com', 'VENDEDOR', false),
    (v_no_module, 'crm_test_sem_modulo', 'CRM Test Sem Modulo', 'crm-test-sem-modulo@example.com', 'VENDEDOR', true);

  insert into public.role_permissions (perfil, modulo, permitido)
  values
    ('ADMIN', 'dashboard', true),
    ('ADMIN', 'pedidos', true),
    ('ADMIN', 'cotacoes', true),
    ('SUPERVISOR', 'dashboard', true),
    ('SUPERVISOR', 'pedidos', true),
    ('SUPERVISOR', 'cotacoes', true),
    ('VENDEDOR', 'dashboard', true),
    ('VENDEDOR', 'pedidos', true),
    ('VENDEDOR', 'cotacoes', true)
  on conflict (perfil, modulo) do update set permitido = excluded.permitido;

  select id into v_branch_sp
  from public.branches
  where code = 'SP'
    and active
  limit 1;

  select id into v_branch_pr
  from public.branches
  where code = 'PR'
    and active
  limit 1;

  if v_branch_sp is null or v_branch_pr is null then
    raise exception 'Filiais SP/PR ativas sao obrigatorias para este teste.';
  end if;

  insert into public.profile_branches (profile_id, branch_id, is_default, active)
  values
    (v_supervisor, v_branch_sp, true, true),
    (v_seller_in, v_branch_sp, true, true),
    (v_seller_out, v_branch_pr, true, true),
    (v_no_module, v_branch_sp, true, true);

  update public.order_stock_contract_settings
  set order_stock_contract_v1_enabled = true
  where singleton;

  insert into public.orders (
    id, numero_pedido, regiao, user_id, vendedor, cliente, total, status,
    branch_id, stock_contract_version, logistics_status, priority, created_at, updated_at
  )
  values
    (v_order_in, 'TST-030-SP', 'SP', v_seller_in, 'CRM Test Vendedor SP', 'Cliente SP', 100, 'APROVADO', v_branch_sp, 1, 'READY_FOR_APPROVAL', 'NORMAL', now(), now()),
    (v_order_out, 'TST-030-PR', 'PR', v_seller_out, 'CRM Test Vendedor PR', 'Cliente PR', 250, 'APROVADO', v_branch_pr, 1, 'READY_FOR_APPROVAL', 'NORMAL', now(), now()),
    (v_order_legacy, 'TST-030-LEGACY', 'SP', v_seller_out, 'CRM Test Vendedor PR', 'Cliente Legado SP', 500, 'APROVADO', v_branch_sp, 0, 'LEGACY_UNMANAGED', null, now(), now());

  insert into public.quotations (
    id, numero_cotacao, regiao, user_id, vendedor, cliente, total, status,
    branch_id, stock_contract_version, priority, created_at, updated_at
  )
  values
    (v_quote_in, 'TST-COT-030-SP', 'SP', v_seller_in, 'CRM Test Vendedor SP', 'Cliente SP', 80, 'APROVADA', v_branch_sp, 1, 'NORMAL', now(), now()),
    (v_quote_out, 'TST-COT-030-PR', 'PR', v_seller_out, 'CRM Test Vendedor PR', 'Cliente PR', 140, 'APROVADA', v_branch_pr, 1, 'NORMAL', now(), now());
end
$setup$;

set local role authenticated;

do $validate_authenticated$
declare
  v_admin uuid := '10000000-0000-4000-8000-000000000001';
  v_supervisor uuid := '10000000-0000-4000-8000-000000000002';
  v_seller_in uuid := '10000000-0000-4000-8000-000000000003';
  v_seller_out uuid := '10000000-0000-4000-8000-000000000004';
  v_inactive uuid := '10000000-0000-4000-8000-000000000005';
  v_order_in uuid := '30000000-0000-4000-8000-000000000001';
  v_order_out uuid := '30000000-0000-4000-8000-000000000002';
  v_order_legacy uuid := '30000000-0000-4000-8000-000000000003';
  v_branch_sp uuid;
  v_summary jsonb;
  v_count int;
  v_rows int;
begin
  select id into v_branch_sp
  from public.branches
  where code = 'SP'
    and active
  limit 1;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_summary := public.get_dashboard_summary('{}'::jsonb);
  if (v_summary #>> '{access,scope}') <> 'all'
     or (v_summary #>> '{access,can_filter_seller}')::boolean is not true
     or (v_summary #>> '{kpis,orders_count}')::int < 3 then
    raise exception 'ADMIN dashboard global falhou: %', v_summary;
  end if;

  v_summary := public.get_dashboard_summary(jsonb_build_object('seller_id', v_seller_out::text));
  if (v_summary #>> '{access,scope}') <> 'filtered'
     or (v_summary #>> '{kpis,orders_count}')::int <> 2 then
    raise exception 'ADMIN filtro por vendedor falhou: %', v_summary;
  end if;

  perform set_config('request.jwt.claim.sub', v_supervisor::text, true);
  v_summary := public.get_dashboard_summary('{}'::jsonb);
  if (v_summary #>> '{access,scope}') <> 'branch_team'
     or (v_summary #>> '{access,can_filter_seller}')::boolean is not true
     or (v_summary #>> '{access,can_view_stock}')::boolean is not false
     or (v_summary #>> '{kpis,orders_count}')::int <> 1 then
    raise exception 'SUPERVISOR dashboard por filial falhou: %', v_summary;
  end if;

  v_summary := public.get_dashboard_summary(jsonb_build_object('seller_id', v_seller_in::text));
  if (v_summary #>> '{access,scope}') <> 'branch_team_filtered'
     or (v_summary #>> '{kpis,orders_count}')::int <> 1 then
    raise exception 'SUPERVISOR filtro interno falhou: %', v_summary;
  end if;

  begin
    perform public.get_dashboard_summary(jsonb_build_object('seller_id', v_seller_out::text));
    raise exception 'SUPERVISOR conseguiu filtrar vendedor fora da filial';
  exception
    when others then
      if sqlerrm not like '%VENDEDOR_INVALIDO%' then
        raise;
      end if;
  end;

  select count(*) into v_count from public.orders where id in (v_order_in, v_order_out, v_order_legacy);
  if v_count <> 1 then
    raise exception 'SUPERVISOR leitura direta deveria retornar 1 pedido v1 da filial, retornou %', v_count;
  end if;

  update public.company_settings
  set company_name = 'Nao deveria alterar'
  where id = true;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'SUPERVISOR conseguiu alterar company_settings';
  end if;

  perform set_config('request.jwt.claim.sub', v_seller_in::text, true);
  v_summary := public.get_dashboard_summary('{}'::jsonb);
  if (v_summary #>> '{access,scope}') <> 'own'
     or (v_summary #>> '{access,can_filter_seller}')::boolean is not false
     or (v_summary #>> '{kpis,orders_count}')::int <> 1 then
    raise exception 'VENDEDOR dashboard proprio falhou: %', v_summary;
  end if;

  begin
    perform public.get_dashboard_summary(jsonb_build_object('seller_id', v_seller_out::text));
    raise exception 'VENDEDOR conseguiu usar filtro de vendedor';
  exception
    when others then
      if sqlerrm not like '%FILTRO_VENDEDOR_NAO_PERMITIDO%' then
        raise;
      end if;
  end;

  select count(*) into v_count from public.orders where id in (v_order_in, v_order_out);
  if v_count <> 1 then
    raise exception 'VENDEDOR leitura direta deveria retornar apenas pedido proprio, retornou %', v_count;
  end if;

  begin
    insert into public.orders (numero_pedido, regiao, user_id, vendedor, cliente, total, branch_id, stock_contract_version)
    values ('TST-030-DIRECT', 'SP', v_seller_in, 'CRM Test Vendedor SP', 'Cliente Direto', 10, v_branch_sp, 1);
    raise exception 'VENDEDOR conseguiu inserir pedido diretamente na tabela';
  exception
    when insufficient_privilege then null;
    when check_violation then null;
  end;

  begin
    perform public.create_order('{}'::jsonb);
    raise exception 'RPC legado create_order ficou executavel para authenticated';
  exception
    when insufficient_privilege then null;
    when undefined_function then null;
  end;

  perform set_config('request.jwt.claim.sub', v_inactive::text, true);
  begin
    perform public.get_dashboard_summary('{}'::jsonb);
    raise exception 'Usuario inativo conseguiu acessar dashboard';
  exception
    when others then
      if sqlerrm not like '%SEM_PERMISSAO%' then
        raise;
      end if;
  end;
end
$validate_authenticated$;

reset role;
set local role postgres;

update public.role_permissions
set permitido = false
where perfil = 'VENDEDOR'
  and modulo in ('dashboard', 'dashboard_comercial');

set local role authenticated;

do $validate_no_module$
declare
  v_no_module uuid := '10000000-0000-4000-8000-000000000006';
begin
  perform set_config('request.jwt.claim.sub', v_no_module::text, true);
  begin
    perform public.get_dashboard_summary('{}'::jsonb);
    raise exception 'Usuario sem modulo conseguiu acessar dashboard';
  exception
    when others then
      if sqlerrm not like '%SEM_PERMISSAO%' then
        raise;
      end if;
  end;

  raise notice 'OK: escopos ADMIN/SUPERVISOR/VENDEDOR e bloqueios diretos validados.';
end
$validate_no_module$;

rollback;
