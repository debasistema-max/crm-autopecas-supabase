\set ON_ERROR_STOP on

do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null then
    raise exception 'TEST_029_REQUIRES_DATABASE_AT_MIGRATION_028';
  end if;
end;
$$;

select
  current_database() as test_029_source_db,
  format('test029_null_%s', pg_backend_pid()) as test_029_null_db,
  format('test029_invalid_%s', pg_backend_pid()) as test_029_invalid_db,
  format('test029_duplicate_%s', pg_backend_pid()) as test_029_duplicate_db,
  format('test029_v1_%s', pg_backend_pid()) as test_029_v1_db,
  format('test029_downstream_%s', pg_backend_pid()) as test_029_downstream_db
\gset

\connect postgres
create database :"test_029_null_db" template :"test_029_source_db";
create database :"test_029_invalid_db" template :"test_029_source_db";
create database :"test_029_duplicate_db" template :"test_029_source_db";
create database :"test_029_v1_db" template :"test_029_source_db";
create database :"test_029_downstream_db" template :"test_029_source_db";
\connect :"test_029_source_db"

create temporary table test_029_compatibility_baseline
on commit preserve rows
as
select
  md5(pg_get_functiondef(
    'public.commit_product_import_batch(uuid)'::regprocedure
  )) as import_commit_definition_md5,
  md5(pg_get_functiondef(
    'public.sync_legacy_product_stock_to_pr()'::regprocedure
  )) as legacy_stock_sync_definition_md5,
  (select count(*) from public.product_branch_stock) as stock_rows,
  (select coalesce(sum(physical_qty), 0) from public.product_branch_stock) as physical_qty,
  (select coalesce(sum(reserved_order_qty), 0) from public.product_branch_stock) as reserved_order_qty,
  (select count(*) from public.product_branch_prices) as price_rows,
  (select count(*) from public.stock_movements) as movement_rows;

\ir ../migrations/029_branch_order_contract.sql
\ir ../migrations/029_branch_order_contract.sql

begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then
    raise exception 'ASSERTION_FAILED: %', message;
  end if;
end;
$$;

create temporary table test_029_context (
  pr_branch_id uuid not null,
  sp_branch_id uuid not null,
  product_code text not null,
  admin_id uuid not null,
  supervisor_id uuid not null,
  seller_id uuid not null
) on commit drop;

insert into test_029_context
select
  (select id from public.branches where code = 'PR' and active and is_headquarters),
  (select id from public.branches where code = 'SP' and active),
  (select codigo from public.products order by codigo limit 1),
  '29000000-0000-4000-8000-000000000001'::uuid,
  '29000000-0000-4000-8000-000000000002'::uuid,
  '29000000-0000-4000-8000-000000000003'::uuid;

grant select on test_029_context to authenticated;

select pg_temp.assert_true(
  (select count(*) from test_029_context) = 1
  and (select pr_branch_id is not null and sp_branch_id is not null and product_code is not null
       from test_029_context),
  'canonical branches and a product must exist'
);

select pg_temp.assert_true(
  has_table_privilege('authenticated', 'public.orders', 'SELECT')
  and has_table_privilege('authenticated', 'public.order_items', 'SELECT')
  and has_table_privilege('authenticated', 'public.quotations', 'SELECT')
  and has_table_privilege('authenticated', 'public.quotation_items', 'SELECT')
  and has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.can_access_branch(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.is_active_branch_order_profile()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.is_branch_order_supervisor()', 'EXECUTE'),
  'historical and 029 read grants are incomplete'
);

create temporary table test_029_inventory_baseline on commit drop as
select
  (select count(*) from public.product_branch_stock) as stock_rows,
  (select coalesce(sum(physical_qty), 0) from public.product_branch_stock) as physical_qty,
  (select coalesce(sum(reserved_order_qty), 0) from public.product_branch_stock) as reserved_order_qty,
  (select count(*) from public.stock_movements) as movement_rows,
  (select count(*) from public.product_branch_prices) as price_rows;

select pg_temp.assert_true(
  (select count(*) from public.order_stock_contract_settings) = 1
  and (
    select not order_stock_contract_v1_enabled
    from public.order_stock_contract_settings
    where singleton
  ),
  'V1 feature flag must be a disabled singleton'
);

select pg_temp.assert_true(
  not has_table_privilege('anon', 'public.orders', 'SELECT')
  and not has_table_privilege('anon', 'public.quotations', 'SELECT')
  and not has_table_privilege('anon', 'public.order_stock_contract_settings', 'SELECT')
  and not has_table_privilege('authenticated', 'public.order_stock_contract_settings', 'INSERT')
  and not has_table_privilege('authenticated', 'public.order_stock_contract_settings', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.order_stock_contract_settings', 'DELETE'),
  'anon and authenticated flag privileges must be restricted'
);

select pg_temp.assert_true(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name in (
        'branch_id',
        'stock_contract_version',
        'logistics_status',
        'priority',
        'promised_at',
        'operational_version',
        'branch_locked_at',
        'approval_requested_at',
        'price_revalidation_required_at'
      )
  ) = 9,
  'orders contract columns are incomplete'
);

select pg_temp.assert_true(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quotations'
      and column_name in (
        'branch_id',
        'stock_contract_version',
        'priority',
        'promised_at',
        'operational_version'
      )
  ) = 5,
  'quotation contract columns are incomplete'
);

select pg_temp.assert_true(
  position(
    'BRANCH_IMPORT_V2:PRODUCT:'
    in pg_get_functiondef('public.commit_product_import_batch(uuid)'::regprocedure)
  ) > 0
  and position(
    'pg_advisory_xact_lock'
    in pg_get_functiondef('public.commit_product_import_batch(uuid)'::regprocedure)
  ) > 0,
  'migration 028 product lock contract changed or is missing'
);

do $$
declare
  v_pr uuid := (select pr_branch_id from test_029_context);
begin
  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority
    )
    values (
      'TEST-029-V1-BLOCKED',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'DRAFT',
      'NORMAL'
    );
    raise exception 'ASSERTION_FAILED: V1 insert was accepted while disabled';
  exception
    when sqlstate '0A000' then
      if sqlerrm <> 'ORDER_STOCK_CONTRACT_V1_DISABLED' then
        raise;
      end if;
  end;
end;
$$;

do $$
begin
  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      operational_version
    )
    values (
      'TEST-029-V0-BAD-VERSION',
      'PR',
      'TESTE ISOLADO',
      1
    );
    raise exception 'ASSERTION_FAILED: nonzero operational version was accepted in V0';
  exception
    when check_violation then null;
  end;
end;
$$;

insert into auth.users (
  id,
  aud,
  role,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
select admin_id, 'authenticated', 'authenticated', 'test-029-admin@example.invalid',
       '{}'::jsonb, '{}'::jsonb, now(), now()
from test_029_context
union all
select supervisor_id, 'authenticated', 'authenticated', 'test-029-supervisor@example.invalid',
       '{}'::jsonb, '{}'::jsonb, now(), now()
from test_029_context
union all
select seller_id, 'authenticated', 'authenticated', 'test-029-seller@example.invalid',
       '{}'::jsonb, '{}'::jsonb, now(), now()
from test_029_context;

insert into public.profiles (id, usuario, nome, email, perfil, ativo)
select admin_id, 'test_029_admin', 'Test 029 Admin',
       'test-029-admin@example.invalid', 'ADMIN'::public.user_profile, true
from test_029_context
union all
select supervisor_id, 'test_029_supervisor', 'Test 029 Supervisor',
       'test-029-supervisor@example.invalid', 'SUPERVISOR'::public.user_profile, true
from test_029_context
union all
select seller_id, 'test_029_seller', 'Test 029 Seller',
       'test-029-seller@example.invalid', 'VENDEDOR'::public.user_profile, true
from test_029_context;

insert into public.profile_branches (profile_id, branch_id, is_default, active)
select supervisor_id, pr_branch_id, true, true
from test_029_context
union all
select seller_id, pr_branch_id, true, true
from test_029_context;

insert into public.orders (
  numero_pedido,
  regiao,
  user_id,
  cliente
)
select 'TEST-029-V0-ORDER', 'PR', seller_id, 'TESTE ISOLADO'
from test_029_context;

insert into public.quotations (
  numero_cotacao,
  regiao,
  user_id,
  cliente
)
select 'TEST-029-V0-QUOTE', 'SP', seller_id, 'TESTE ISOLADO'
from test_029_context;

select pg_temp.assert_true(
  exists (
    select 1
    from public.orders o
    join public.branches b on b.id = o.branch_id
    where o.numero_pedido = 'TEST-029-V0-ORDER'
      and o.stock_contract_version = 0
      and o.logistics_status = 'LEGACY_UNMANAGED'
      and b.code = 'PR'
  )
  and exists (
    select 1
    from public.quotations q
    join public.branches b on b.id = q.branch_id
    where q.numero_cotacao = 'TEST-029-V0-QUOTE'
      and q.stock_contract_version = 0
      and b.code = 'SP'
  ),
  'V0 defaults or automatic branch mapping failed'
);

insert into public.order_items (
  order_id,
  item,
  codigo,
  quantidade
)
select o.id, 1, c.product_code, 1
from public.orders o
cross join test_029_context c
where o.numero_pedido = 'TEST-029-V0-ORDER';

insert into public.quotation_items (
  quotation_id,
  item,
  codigo,
  quantidade
)
select q.id, 1, c.product_code, 1
from public.quotations q
cross join test_029_context c
where q.numero_cotacao = 'TEST-029-V0-QUOTE';

do $$
declare
  v_order_id uuid := (
    select id from public.orders where numero_pedido = 'TEST-029-V0-ORDER'
  );
  v_quotation_id uuid := (
    select id from public.quotations where numero_cotacao = 'TEST-029-V0-QUOTE'
  );
  v_product text := (select product_code from test_029_context);
begin
  begin
    insert into public.order_items (order_id, item, codigo, quantidade)
    values (v_order_id, 2, v_product, 1);
    raise exception 'ASSERTION_FAILED: duplicate order product was accepted';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.quotation_items (quotation_id, item, codigo, quantidade)
    values (v_quotation_id, 2, v_product, 1);
    raise exception 'ASSERTION_FAILED: duplicate quotation product was accepted';
  exception
    when unique_violation then null;
  end;

  begin
    update public.order_items
    set branch_price = 10,
        branch_price_currency = 'BRL',
        branch_price_version = 1,
        branch_price_captured_at = now()
    where order_id = v_order_id;
    raise exception 'ASSERTION_FAILED: a V0 snapshot was accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = true
where singleton;

do $$
declare
  v_pr uuid := (select pr_branch_id from test_029_context);
begin
  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      stock_contract_version,
      logistics_status,
      priority
    )
    values (
      'TEST-029-V1-NO-BRANCH',
      'PR',
      'TESTE ISOLADO',
      1,
      'DRAFT',
      'NORMAL'
    );
    raise exception 'ASSERTION_FAILED: V1 order without branch was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority,
      promised_at
    )
    values (
      'TEST-029-V1-BAD-PROMISE',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'DRAFT',
      'NORMAL',
      now() - interval '1 day'
    );
    raise exception 'ASSERTION_FAILED: incoherent promise date was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority,
      operational_version
    )
    values (
      'TEST-029-V1-BAD-VERSION',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'DRAFT',
      'NORMAL',
      -1
    );
    raise exception 'ASSERTION_FAILED: negative operational version was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority
    )
    values (
      'TEST-029-V1-BAD-LOGISTICS',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'LEGACY_UNMANAGED',
      'NORMAL'
    );
    raise exception 'ASSERTION_FAILED: V1 legacy logistics was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority
    )
    values (
      'TEST-029-V1-BAD-PRIORITY',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'DRAFT',
      'INVALID'
    );
    raise exception 'ASSERTION_FAILED: invalid priority was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status
    )
    values (
      'TEST-029-V0-BAD-LOGISTICS',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      0,
      'DRAFT'
    );
    raise exception 'ASSERTION_FAILED: operational logistics was accepted in V0';
  exception
    when check_violation then null;
  end;
end;
$$;

insert into public.orders (
  numero_pedido,
  regiao,
  user_id,
  cliente,
  branch_id,
  stock_contract_version,
  logistics_status,
  priority,
  promised_at
)
select 'TEST-029-V1-ADMIN-PR', 'PR'::public.order_region, admin_id, 'TESTE ISOLADO',
       pr_branch_id, 1, 'DRAFT', 'NORMAL', now() + interval '1 day'
from test_029_context
union all
select 'TEST-029-V1-SELLER-PR', 'PR'::public.order_region, seller_id, 'TESTE ISOLADO',
       pr_branch_id, 1, 'DRAFT', 'HIGH', now() + interval '2 days'
from test_029_context
union all
select 'TEST-029-V1-SELLER-SP', 'SP'::public.order_region, seller_id, 'TESTE ISOLADO',
       sp_branch_id, 1, 'DRAFT', 'NORMAL', now() + interval '3 days'
from test_029_context;

insert into public.quotations (
  numero_cotacao,
  regiao,
  user_id,
  cliente,
  branch_id,
  stock_contract_version,
  priority,
  promised_at
)
select 'TEST-029-V1-QUOTE-PR', 'PR', seller_id, 'TESTE ISOLADO',
       pr_branch_id, 1, 'NORMAL', now() + interval '1 day'
from test_029_context;

insert into public.order_items (
  order_id,
  item,
  codigo,
  quantidade,
  branch_price,
  branch_price_currency,
  branch_price_version,
  branch_price_captured_at
)
select o.id, 1, c.product_code, 1, 10, 'BRL', 1, now()
from public.orders o
cross join test_029_context c
where o.numero_pedido like 'TEST-029-V1-%'
  and o.numero_pedido in (
    'TEST-029-V1-ADMIN-PR',
    'TEST-029-V1-SELLER-PR',
    'TEST-029-V1-SELLER-SP'
  );

insert into public.quotation_items (
  quotation_id,
  item,
  codigo,
  quantidade,
  branch_price,
  branch_price_currency,
  branch_price_version,
  branch_price_captured_at
)
select q.id, 1, c.product_code, 1, 10, 'BRL', 1, now()
from public.quotations q
cross join test_029_context c
where q.numero_cotacao = 'TEST-029-V1-QUOTE-PR';

do $$
declare
  v_order_id uuid := (
    select id from public.orders where numero_pedido = 'TEST-029-V1-SELLER-PR'
  );
  v_product text := (select product_code from test_029_context);
begin
  begin
    update public.order_items
    set branch_price_currency = null
    where order_id = v_order_id;
    raise exception 'ASSERTION_FAILED: incomplete V1 snapshot was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.order_items (
      order_id,
      item,
      codigo,
      quantidade
    )
    values (v_order_id, 2, v_product, 1);
    raise exception 'ASSERTION_FAILED: missing V1 snapshot was accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = false
where singleton;

set local role authenticated;

select set_config(
  'request.jwt.claim.sub',
  (select admin_id::text from test_029_context),
  true
);
select pg_temp.assert_true(
  (select count(*) from public.orders where numero_pedido like 'TEST-029-%') = 4,
  'ADMIN must read all test orders'
);
select pg_temp.assert_true(
  (select count(*) from public.order_stock_contract_settings) = 1,
  'ADMIN must read the feature flag'
);

do $$
begin
  begin
    update public.order_stock_contract_settings
    set order_stock_contract_v1_enabled = true
    where singleton;
    raise exception 'ASSERTION_FAILED: authenticated ADMIN wrote the flag directly';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  (select supervisor_id::text from test_029_context),
  true
);
select pg_temp.assert_true(
  (select count(*) from public.orders where numero_pedido like 'TEST-029-V1-%') = 2,
  'SUPERVISOR must read V1 orders only in linked PR branch'
);
select pg_temp.assert_true(
  (select count(*) from public.order_stock_contract_settings) = 0,
  'SUPERVISOR must not read the feature flag'
);

select set_config(
  'request.jwt.claim.sub',
  (select seller_id::text from test_029_context),
  true
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V0-ORDER'
  ),
  'VENDEDOR must retain own V0 read access'
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V1-SELLER-PR'
  )
  and not exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V1-SELLER-SP'
  )
  and not exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V1-ADMIN-PR'
  ),
  'VENDEDOR V1 access must require ownership and linked branch'
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.quotations
    where numero_cotacao = 'TEST-029-V1-QUOTE-PR'
  ),
  'VENDEDOR must read own V1 quotation in linked branch'
);

reset role;

update public.profiles
set ativo = false
where id = (select seller_id from test_029_context);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  (select seller_id::text from test_029_context),
  true
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V0-ORDER'
  )
  and not exists (
    select 1
    from public.orders
    where numero_pedido in (
      'TEST-029-V1-SELLER-PR',
      'TEST-029-V1-SELLER-SP'
    )
  ),
  'inactive profile must retain legacy V0 behavior but lose all V1 access'
);
reset role;

select pg_temp.assert_true(
  (
    select row(
      count(*),
      coalesce(sum(physical_qty), 0),
      coalesce(sum(reserved_order_qty), 0)
    )
    from public.product_branch_stock
  ) = (
    select row(stock_rows, physical_qty, reserved_order_qty)
    from test_029_inventory_baseline
  )
  and (
    select count(*) from public.stock_movements
  ) = (
    select movement_rows from test_029_inventory_baseline
  )
  and (
    select count(*) from public.product_branch_prices
  ) = (
    select price_rows from test_029_inventory_baseline
  ),
  '029 tests changed stock, movements, reservations, or branch prices'
);

select 'PASS: migration 029 structural validation' as result;

rollback;

\ir ../rollback/029_branch_order_contract_rollback.sql

do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name in (
           'orders',
           'order_items',
           'quotations',
           'quotation_items'
         )
         and column_name in (
           'stock_contract_version',
           'logistics_status',
           'branch_price'
         )
     )
     or to_regclass('public.product_branch_prices') is null
     or to_regprocedure('public.commit_product_import_batch(uuid)') is null then
    raise exception 'ASSERTION_FAILED: rollback did not isolate 029 from 028';
  end if;
end;
$$;

\ir ../migrations/029_branch_order_contract.sql

do $$
begin
  if not exists (
    select 1
    from test_029_compatibility_baseline baseline
    where baseline.import_commit_definition_md5 = md5(pg_get_functiondef(
            'public.commit_product_import_batch(uuid)'::regprocedure
          ))
      and baseline.legacy_stock_sync_definition_md5 = md5(pg_get_functiondef(
            'public.sync_legacy_product_stock_to_pr()'::regprocedure
          ))
      and baseline.stock_rows = (select count(*) from public.product_branch_stock)
      and baseline.physical_qty = (
        select coalesce(sum(physical_qty), 0)
        from public.product_branch_stock
      )
      and baseline.reserved_order_qty = (
        select coalesce(sum(reserved_order_qty), 0)
        from public.product_branch_stock
      )
      and baseline.price_rows = (select count(*) from public.product_branch_prices)
      and baseline.movement_rows = (select count(*) from public.stock_movements)
  ) then
    raise exception 'ASSERTION_FAILED: migration 027 or 028 compatibility changed';
  end if;
end;
$$;

drop table test_029_compatibility_baseline;

\connect :"test_029_null_db"
alter table public.orders alter column regiao drop not null;
alter table public.quotations alter column regiao drop not null;
insert into public.orders (numero_pedido, regiao, cliente, updated_at)
values
  ('TEST-029-BACKFILL-PR', 'PR', 'TESTE ISOLADO', '2020-01-02 03:04:05+00'),
  ('TEST-029-BACKFILL-SP', 'SP', 'TESTE ISOLADO', '2020-01-02 03:04:05+00'),
  ('TEST-029-BACKFILL-NULL', null, 'TESTE ISOLADO', '2020-01-02 03:04:05+00');
insert into public.quotations (numero_cotacao, regiao, cliente, updated_at)
values
  ('TEST-029-BACKFILL-Q-PR', 'PR', 'TESTE ISOLADO', '2020-01-02 03:04:05+00'),
  ('TEST-029-BACKFILL-Q-SP', 'SP', 'TESTE ISOLADO', '2020-01-02 03:04:05+00'),
  ('TEST-029-BACKFILL-Q-NULL', null, 'TESTE ISOLADO', '2020-01-02 03:04:05+00');
\ir ../migrations/029_branch_order_contract.sql
do $$
begin
  if exists (
    select 1
    from public.orders o
    left join public.branches b on b.id = o.branch_id
    where o.numero_pedido like 'TEST-029-BACKFILL-%'
      and (
        o.stock_contract_version <> 0
        or o.logistics_status <> 'LEGACY_UNMANAGED'
        or o.updated_at <> '2020-01-02 03:04:05+00'::timestamptz
        or (o.regiao = 'PR' and b.code is distinct from 'PR')
        or (o.regiao = 'SP' and b.code is distinct from 'SP')
        or (o.regiao is null and o.branch_id is not null)
      )
  ) or exists (
    select 1
    from public.quotations q
    left join public.branches b on b.id = q.branch_id
    where q.numero_cotacao like 'TEST-029-BACKFILL-Q-%'
      and (
        q.stock_contract_version <> 0
        or q.updated_at <> '2020-01-02 03:04:05+00'::timestamptz
        or (q.regiao = 'PR' and b.code is distinct from 'PR')
        or (q.regiao = 'SP' and b.code is distinct from 'SP')
        or (q.regiao is null and q.branch_id is not null)
      )
  ) then
    raise exception 'ASSERTION_FAILED: PR/SP/NULL backfill or updated_at preservation';
  end if;
end;
$$;

\connect :"test_029_invalid_db"
alter type public.order_region add value 'XX';
insert into public.orders (numero_pedido, regiao, cliente)
values ('TEST-029-INVALID-REGION', 'XX', 'TESTE ISOLADO');
\setenv PGDATABASE :test_029_invalid_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "MIGRATION_029_UNMAPPABLE_REGION" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  \quit 3
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null then
    raise exception 'ASSERTION_FAILED: invalid region did not abort migration 029';
  end if;
end;
$$;

\connect :"test_029_duplicate_db"
with new_order as (
  insert into public.orders (numero_pedido, regiao, cliente)
  values ('TEST-029-DUPLICATE', 'PR', 'TESTE ISOLADO')
  returning id
), product as (
  select codigo
  from public.products
  order by codigo
  limit 1
)
insert into public.order_items (order_id, item, codigo, quantidade)
select new_order.id, 1, product.codigo, 1 from new_order, product
union all
select new_order.id, 2, product.codigo, 1 from new_order, product;
\setenv PGDATABASE :test_029_duplicate_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "MIGRATION_029_DUPLICATE_ORDER_PRODUCTS" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  \quit 3
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null then
    raise exception 'ASSERTION_FAILED: duplicate product did not abort migration 029';
  end if;
end;
$$;

\connect :"test_029_v1_db"
\ir ../migrations/029_branch_order_contract.sql
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = true
where singleton;
insert into public.orders (
  numero_pedido,
  regiao,
  cliente,
  branch_id,
  stock_contract_version,
  logistics_status,
  priority
)
select
  'TEST-029-OPERATIONAL-V1',
  'PR',
  'TESTE ISOLADO',
  id,
  1,
  'DRAFT',
  'NORMAL'
from public.branches
where code = 'PR';
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = false
where singleton;
\setenv PGDATABASE :test_029_v1_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "MIGRATION_029_REAPPLICATION_BLOCKED_ORDER_USE" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  \quit 3
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null
     or not exists (
       select 1 from public.orders where stock_contract_version = 1
     ) then
    raise exception 'ASSERTION_FAILED: operational use did not block reapplication';
  end if;
end;
$$;
\setenv PGDATABASE :test_029_v1_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "ROLLBACK_029_BLOCKED_ORDER_OPERATIONAL_USE" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  \quit 3
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null
     or not exists (
       select 1 from public.orders where stock_contract_version = 1
     ) then
    raise exception 'ASSERTION_FAILED: V1 did not block rollback';
  end if;
end;
$$;
delete from public.orders where numero_pedido = 'TEST-029-OPERATIONAL-V1';
\ir ../rollback/029_branch_order_contract_rollback.sql

\connect :"test_029_downstream_db"
\ir ../migrations/029_branch_order_contract.sql
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('030', 'test_029_simulated_downstream', array[]::text[]);
\setenv PGDATABASE :test_029_downstream_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "ROLLBACK_029_BLOCKED_DOWNSTREAM_MIGRATION" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  \quit 3
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null then
    raise exception 'ASSERTION_FAILED: downstream migration did not block rollback';
  end if;
end;
$$;
delete from supabase_migrations.schema_migrations
where version = '030'
  and name = 'test_029_simulated_downstream';
\ir ../rollback/029_branch_order_contract_rollback.sql

\connect postgres
drop database :"test_029_null_db" with (force);
drop database :"test_029_invalid_db" with (force);
drop database :"test_029_duplicate_db" with (force);
drop database :"test_029_v1_db" with (force);
drop database :"test_029_downstream_db" with (force);
\connect :"test_029_source_db"
\setenv PGDATABASE :test_029_source_db

select 'PASS: all migration 029 lifecycle scenarios; disposable databases removed' as result;
