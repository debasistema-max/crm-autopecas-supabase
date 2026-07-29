begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $$
declare
  v_used boolean;
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null
     and exists (
       select 1
       from supabase_migrations.schema_migrations
       where version ~ '^[0-9]+$'
         and version::numeric > 29
     ) then
    raise exception using
      errcode = '55000',
      message = 'MIGRATION_029_REAPPLICATION_BLOCKED_DOWNSTREAM_MIGRATION';
  end if;

  if to_regclass('public.order_stock_contract_settings') is not null then
    execute
      'select exists (
         select 1
         from public.order_stock_contract_settings
         where singleton and order_stock_contract_v1_enabled
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'MIGRATION_029_REAPPLICATION_BLOCKED_V1_ENABLED';
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name = 'stock_contract_version'
  ) then
    execute
      'select exists (
         select 1
         from public.orders
         where stock_contract_version = 1
            or logistics_status <> ''LEGACY_UNMANAGED''
            or operational_version <> 0
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'MIGRATION_029_REAPPLICATION_BLOCKED_ORDER_USE';
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quotations'
      and column_name = 'stock_contract_version'
  ) then
    execute
      'select exists (
         select 1
         from public.quotations
         where stock_contract_version = 1
            or operational_version <> 0
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'MIGRATION_029_REAPPLICATION_BLOCKED_QUOTATION_USE';
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'order_items'
      and column_name = 'branch_price'
  ) then
    execute
      'select exists (
         select 1
         from public.order_items
         where branch_price is not null
            or branch_price_currency is not null
            or branch_price_version is not null
            or branch_price_captured_at is not null
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'MIGRATION_029_REAPPLICATION_BLOCKED_ORDER_SNAPSHOT_USE';
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quotation_items'
      and column_name = 'branch_price'
  ) then
    execute
      'select exists (
         select 1
         from public.quotation_items
         where branch_price is not null
            or branch_price_currency is not null
            or branch_price_version is not null
            or branch_price_captured_at is not null
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'MIGRATION_029_REAPPLICATION_BLOCKED_QUOTATION_SNAPSHOT_USE';
    end if;
  end if;
end;
$$;

do $$
declare
  v_missing text;
begin
  select string_agg(required_object, ', ' order by required_object)
  into v_missing
  from (
    values
      ('public.orders', to_regclass('public.orders')),
      ('public.order_items', to_regclass('public.order_items')),
      ('public.quotations', to_regclass('public.quotations')),
      ('public.quotation_items', to_regclass('public.quotation_items')),
      ('public.branches', to_regclass('public.branches')),
      ('public.profile_branches', to_regclass('public.profile_branches')),
      ('public.product_branch_stock', to_regclass('public.product_branch_stock')),
      ('public.product_branch_prices', to_regclass('public.product_branch_prices')),
      ('public.stock_movements', to_regclass('public.stock_movements'))
  ) required(required_object, object_oid)
  where object_oid is null;

  if v_missing is not null then
    raise exception using
      errcode = '42P01',
      message = 'MIGRATION_029_MISSING_PREREQUISITES',
      detail = v_missing;
  end if;
end;
$$;

lock table public.branches in share mode;
lock table public.orders, public.order_items,
  public.quotations, public.quotation_items
  in share row exclusive mode;

do $$
declare
  v_pr_count integer;
  v_sp_count integer;
  v_unmapped text;
  v_duplicates text;
begin
  select count(*) into v_pr_count
  from public.branches
  where code = 'PR'
    and active
    and is_headquarters;

  select count(*) into v_sp_count
  from public.branches
  where code = 'SP'
    and active;

  if v_pr_count <> 1 or v_sp_count <> 1 then
    raise exception using
      errcode = '23514',
      message = 'MIGRATION_029_CANONICAL_BRANCHES_INVALID',
      detail = format('PR=%s, SP=%s', v_pr_count, v_sp_count);
  end if;

  select string_agg(format('%s:%s', source_id, region_value), ', ' order by source_id)
  into v_unmapped
  from (
    select id::text as source_id, left(regiao::text, 20) as region_value
    from public.orders o
    where o.regiao is not null
      and not exists (
        select 1
        from public.branches b
        where b.code = o.regiao::text
          and b.active
      )
    union all
    select id::text, left(regiao::text, 20)
    from public.quotations q
    where q.regiao is not null
      and not exists (
        select 1
        from public.branches b
        where b.code = q.regiao::text
          and b.active
      )
  ) unmapped;

  if v_unmapped is not null then
    raise exception using
      errcode = '23514',
      message = 'MIGRATION_029_UNMAPPABLE_REGION',
      detail = v_unmapped;
  end if;

  select string_agg(format('%s:%s', document_id, left(product_code, 80)), ', ' order by document_id, product_code)
  into v_duplicates
  from (
    select order_id::text as document_id, codigo as product_code
    from public.order_items
    group by order_id, codigo
    having count(*) > 1
  ) duplicates;

  if v_duplicates is not null then
    raise exception using
      errcode = '23505',
      message = 'MIGRATION_029_DUPLICATE_ORDER_PRODUCTS',
      detail = v_duplicates;
  end if;

  select string_agg(format('%s:%s', document_id, left(product_code, 80)), ', ' order by document_id, product_code)
  into v_duplicates
  from (
    select quotation_id::text as document_id, codigo as product_code
    from public.quotation_items
    group by quotation_id, codigo
    having count(*) > 1
  ) duplicates;

  if v_duplicates is not null then
    raise exception using
      errcode = '23505',
      message = 'MIGRATION_029_DUPLICATE_QUOTATION_PRODUCTS',
      detail = v_duplicates;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.orders'::regclass
      and t.tgname = 'orders_touch_updated_at'
      and not t.tgisinternal
      and t.tgenabled = 'O'
  ) or not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.quotations'::regclass
      and t.tgname = 'quotations_touch_updated_at'
      and not t.tgisinternal
      and t.tgenabled = 'O'
  ) then
    raise exception using
      errcode = '55000',
      message = 'MIGRATION_029_UPDATED_AT_TRIGGER_INVALID';
  end if;
end;
$$;

create table if not exists public.order_stock_contract_settings (
  singleton boolean primary key default true,
  order_stock_contract_v1_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint order_stock_contract_settings_singleton_check
    check (singleton)
);

insert into public.order_stock_contract_settings (
  singleton,
  order_stock_contract_v1_enabled
)
values (true, false)
on conflict (singleton) do nothing;

do $$
begin
  if not exists (
    select 1
    from public.order_stock_contract_settings
    where singleton
      and not order_stock_contract_v1_enabled
  ) or (
    select count(*)
    from public.order_stock_contract_settings
  ) <> 1 then
    raise exception using
      errcode = '23514',
      message = 'MIGRATION_029_V1_FLAG_MUST_BE_DISABLED_SINGLETON';
  end if;
end;
$$;

drop trigger if exists order_stock_contract_settings_touch_updated_at
  on public.order_stock_contract_settings;
create trigger order_stock_contract_settings_touch_updated_at
before update on public.order_stock_contract_settings
for each row execute function public.touch_updated_at();

alter table public.orders
  add column if not exists branch_id uuid,
  add column if not exists stock_contract_version smallint not null default 0,
  add column if not exists logistics_status text not null default 'LEGACY_UNMANAGED',
  add column if not exists priority text,
  add column if not exists promised_at timestamptz,
  add column if not exists operational_version bigint not null default 0,
  add column if not exists branch_locked_at timestamptz,
  add column if not exists approval_requested_at timestamptz,
  add column if not exists price_revalidation_required_at timestamptz;

alter table public.quotations
  add column if not exists branch_id uuid,
  add column if not exists stock_contract_version smallint not null default 0,
  add column if not exists priority text,
  add column if not exists promised_at timestamptz,
  add column if not exists operational_version bigint not null default 0;

alter table public.order_items
  add column if not exists branch_price numeric(14,4),
  add column if not exists branch_price_currency character(3),
  add column if not exists branch_price_version bigint,
  add column if not exists branch_price_captured_at timestamptz;

alter table public.quotation_items
  add column if not exists branch_price numeric(14,4),
  add column if not exists branch_price_currency character(3),
  add column if not exists branch_price_version bigint,
  add column if not exists branch_price_captured_at timestamptz;

create temporary table migration_029_orders_updated_at_before
on commit drop
as
select o.id, o.updated_at
from public.orders o
join public.branches b
  on b.code = o.regiao::text
 and b.active
where o.regiao is not null
  and o.branch_id is distinct from b.id;

create temporary table migration_029_quotations_updated_at_before
on commit drop
as
select q.id, q.updated_at
from public.quotations q
join public.branches b
  on b.code = q.regiao::text
 and b.active
where q.regiao is not null
  and q.branch_id is distinct from b.id;

alter table public.orders disable trigger orders_touch_updated_at;
alter table public.quotations disable trigger quotations_touch_updated_at;

update public.orders o
set branch_id = b.id
from public.branches b
where o.regiao is not null
  and b.code = o.regiao::text
  and b.active
  and o.branch_id is distinct from b.id;

update public.quotations q
set branch_id = b.id
from public.branches b
where q.regiao is not null
  and b.code = q.regiao::text
  and b.active
  and q.branch_id is distinct from b.id;

alter table public.orders enable trigger orders_touch_updated_at;
alter table public.quotations enable trigger quotations_touch_updated_at;

do $$
begin
  if exists (
    select 1
    from migration_029_orders_updated_at_before old_row
    join public.orders o on o.id = old_row.id
    where o.updated_at is distinct from old_row.updated_at
  ) or exists (
    select 1
    from migration_029_quotations_updated_at_before old_row
    join public.quotations q on q.id = old_row.id
    where q.updated_at is distinct from old_row.updated_at
  ) then
    raise exception using
      errcode = '55000',
      message = 'MIGRATION_029_UPDATED_AT_BACKFILL_CHANGED';
  end if;
end;
$$;

alter table public.orders
  drop constraint if exists orders_branch_id_fkey_029,
  drop constraint if exists orders_stock_contract_version_check_029,
  drop constraint if exists orders_logistics_status_check_029,
  drop constraint if exists orders_priority_check_029,
  drop constraint if exists orders_operational_version_check_029,
  drop constraint if exists orders_contract_coherence_check_029,
  drop constraint if exists orders_contract_dates_check_029;

alter table public.orders
  add constraint orders_branch_id_fkey_029
    foreign key (branch_id) references public.branches(id) on delete restrict
    not valid,
  add constraint orders_stock_contract_version_check_029
    check (stock_contract_version in (0, 1)) not valid,
  add constraint orders_logistics_status_check_029
    check (logistics_status in (
      'LEGACY_UNMANAGED',
      'DRAFT',
      'READY_FOR_APPROVAL',
      'AWAITING_STOCK',
      'RESERVED',
      'CONSUMED',
      'CANCELLED'
    )) not valid,
  add constraint orders_priority_check_029
    check (priority is null or priority in ('LOW', 'NORMAL', 'HIGH', 'URGENT'))
    not valid,
  add constraint orders_operational_version_check_029
    check (operational_version >= 0) not valid,
  add constraint orders_contract_coherence_check_029
    check (
      (
        stock_contract_version = 0
        and logistics_status = 'LEGACY_UNMANAGED'
        and operational_version = 0
        and priority is null
        and promised_at is null
        and branch_locked_at is null
        and approval_requested_at is null
        and price_revalidation_required_at is null
      )
      or
      (
        stock_contract_version = 1
        and branch_id is not null
        and logistics_status <> 'LEGACY_UNMANAGED'
        and priority is not null
      )
    ) not valid,
  add constraint orders_contract_dates_check_029
    check (
      (promised_at is null or promised_at >= data_hora)
      and (branch_locked_at is null or branch_locked_at >= created_at)
      and (approval_requested_at is null or approval_requested_at >= created_at)
      and (
        price_revalidation_required_at is null
        or (
          approval_requested_at is not null
          and price_revalidation_required_at >= approval_requested_at
        )
      )
    ) not valid;

alter table public.quotations
  drop constraint if exists quotations_branch_id_fkey_029,
  drop constraint if exists quotations_stock_contract_version_check_029,
  drop constraint if exists quotations_priority_check_029,
  drop constraint if exists quotations_operational_version_check_029,
  drop constraint if exists quotations_contract_coherence_check_029,
  drop constraint if exists quotations_contract_dates_check_029;

alter table public.quotations
  add constraint quotations_branch_id_fkey_029
    foreign key (branch_id) references public.branches(id) on delete restrict
    not valid,
  add constraint quotations_stock_contract_version_check_029
    check (stock_contract_version in (0, 1)) not valid,
  add constraint quotations_priority_check_029
    check (priority is null or priority in ('LOW', 'NORMAL', 'HIGH', 'URGENT'))
    not valid,
  add constraint quotations_operational_version_check_029
    check (operational_version >= 0) not valid,
  add constraint quotations_contract_coherence_check_029
    check (
      (
        stock_contract_version = 0
        and operational_version = 0
        and priority is null
        and promised_at is null
      )
      or
      (
        stock_contract_version = 1
        and branch_id is not null
        and priority is not null
      )
    ) not valid,
  add constraint quotations_contract_dates_check_029
    check (promised_at is null or promised_at >= data_hora) not valid;

alter table public.order_items
  drop constraint if exists order_items_branch_price_snapshot_check_029;

alter table public.order_items
  add constraint order_items_branch_price_snapshot_check_029
    check (
      (
        branch_price is null
        and branch_price_currency is null
        and branch_price_version is null
        and branch_price_captured_at is null
      )
      or
      (
        branch_price is not null
        and branch_price >= 0
        and branch_price_currency is not null
        and branch_price_currency = upper(branch_price_currency)
        and branch_price_currency ~ '^[A-Z]{3}$'
        and branch_price_version is not null
        and branch_price_version >= 1
        and branch_price_captured_at is not null
      )
    ) not valid;

alter table public.quotation_items
  drop constraint if exists quotation_items_branch_price_snapshot_check_029;

alter table public.quotation_items
  add constraint quotation_items_branch_price_snapshot_check_029
    check (
      (
        branch_price is null
        and branch_price_currency is null
        and branch_price_version is null
        and branch_price_captured_at is null
      )
      or
      (
        branch_price is not null
        and branch_price >= 0
        and branch_price_currency is not null
        and branch_price_currency = upper(branch_price_currency)
        and branch_price_currency ~ '^[A-Z]{3}$'
        and branch_price_version is not null
        and branch_price_version >= 1
        and branch_price_captured_at is not null
      )
    ) not valid;

alter table public.orders validate constraint orders_branch_id_fkey_029;
alter table public.orders validate constraint orders_stock_contract_version_check_029;
alter table public.orders validate constraint orders_logistics_status_check_029;
alter table public.orders validate constraint orders_priority_check_029;
alter table public.orders validate constraint orders_operational_version_check_029;
alter table public.orders validate constraint orders_contract_coherence_check_029;
alter table public.orders validate constraint orders_contract_dates_check_029;

alter table public.quotations validate constraint quotations_branch_id_fkey_029;
alter table public.quotations validate constraint quotations_stock_contract_version_check_029;
alter table public.quotations validate constraint quotations_priority_check_029;
alter table public.quotations validate constraint quotations_operational_version_check_029;
alter table public.quotations validate constraint quotations_contract_coherence_check_029;
alter table public.quotations validate constraint quotations_contract_dates_check_029;

alter table public.order_items
  validate constraint order_items_branch_price_snapshot_check_029;
alter table public.quotation_items
  validate constraint quotation_items_branch_price_snapshot_check_029;

create unique index if not exists order_items_order_product_unique_029
  on public.order_items (order_id, codigo);

create unique index if not exists quotation_items_quotation_product_unique_029
  on public.quotation_items (quotation_id, codigo);

create index if not exists orders_branch_logistics_v1_idx_029
  on public.orders (branch_id, logistics_status, updated_at desc, id)
  where stock_contract_version = 1;

create index if not exists orders_branch_priority_v1_idx_029
  on public.orders (branch_id, priority, promised_at, id)
  where stock_contract_version = 1;

create index if not exists orders_owner_branch_v1_idx_029
  on public.orders (user_id, branch_id, created_at desc, id)
  where stock_contract_version = 1;

create index if not exists quotations_branch_v1_idx_029
  on public.quotations (branch_id, updated_at desc, id)
  where stock_contract_version = 1;

create index if not exists quotations_owner_branch_v1_idx_029
  on public.quotations (user_id, branch_id, created_at desc, id)
  where stock_contract_version = 1;

create or replace function public.is_active_branch_order_profile()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.ativo
  )
$$;

create or replace function public.is_branch_order_supervisor()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.ativo
      and p.perfil = 'SUPERVISOR'
  )
$$;

create or replace function public.enforce_branch_order_contract()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_branch_id uuid;
  v_branch_count integer;
  v_v1_enabled boolean;
  v_invalid_items boolean;
begin
  if new.stock_contract_version = 1 then
    select s.order_stock_contract_v1_enabled
    into v_v1_enabled
    from public.order_stock_contract_settings s
    where s.singleton;

    if not coalesce(v_v1_enabled, false) then
      raise exception using
        errcode = '0A000',
        message = 'ORDER_STOCK_CONTRACT_V1_DISABLED';
    end if;
  end if;

  if new.branch_id is not null
     and not exists (
       select 1
       from public.branches b
       where b.id = new.branch_id
         and b.active
     ) then
    raise exception using
      errcode = '23514',
      message = 'ORDER_STOCK_CONTRACT_BRANCH_INACTIVE';
  end if;

  if new.stock_contract_version = 0 and new.regiao is not null then
    select count(*), min(b.id::text)::uuid
    into v_branch_count, v_branch_id
    from public.branches b
    where b.code = new.regiao::text
      and b.active;

    if v_branch_count <> 1 then
      raise exception using
        errcode = '23514',
        message = 'ORDER_STOCK_CONTRACT_REGION_NOT_MAPPABLE',
        detail = left(new.regiao::text, 20);
    end if;

    if new.branch_id is null then
      new.branch_id := v_branch_id;
    elsif new.branch_id <> v_branch_id then
      raise exception using
        errcode = '23514',
        message = 'ORDER_STOCK_CONTRACT_V0_BRANCH_REGION_MISMATCH';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.stock_contract_version is distinct from new.stock_contract_version then
    if tg_table_name = 'orders' then
      select exists (
        select 1
        from public.order_items i
        where i.order_id = new.id
          and (
            (new.stock_contract_version = 0 and i.branch_price is not null)
            or
            (
              new.stock_contract_version = 1
              and (
                i.branch_price is null
                or i.branch_price_currency is null
                or i.branch_price_version is null
                or i.branch_price_captured_at is null
              )
            )
          )
      )
      into v_invalid_items;
    else
      select exists (
        select 1
        from public.quotation_items i
        where i.quotation_id = new.id
          and (
            (new.stock_contract_version = 0 and i.branch_price is not null)
            or
            (
              new.stock_contract_version = 1
              and (
                i.branch_price is null
                or i.branch_price_currency is null
                or i.branch_price_version is null
                or i.branch_price_captured_at is null
              )
            )
          )
      )
      into v_invalid_items;
    end if;

    if v_invalid_items then
      raise exception using
        errcode = '23514',
        message = 'ORDER_STOCK_CONTRACT_ITEM_SNAPSHOT_MISMATCH';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.enforce_branch_price_snapshot_parent()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_contract_version smallint;
  v_snapshot_present boolean;
  v_snapshot_complete boolean;
begin
  v_snapshot_present :=
    new.branch_price is not null
    or new.branch_price_currency is not null
    or new.branch_price_version is not null
    or new.branch_price_captured_at is not null;

  v_snapshot_complete :=
    new.branch_price is not null
    and new.branch_price_currency is not null
    and new.branch_price_version is not null
    and new.branch_price_captured_at is not null;

  if tg_table_name = 'order_items' then
    select o.stock_contract_version
    into strict v_contract_version
    from public.orders o
    where o.id = new.order_id;
  else
    select q.stock_contract_version
    into strict v_contract_version
    from public.quotations q
    where q.id = new.quotation_id;
  end if;

  if v_contract_version = 0 and v_snapshot_present then
    raise exception using
      errcode = '23514',
      message = 'BRANCH_PRICE_SNAPSHOT_REQUIRES_V1';
  end if;

  if v_contract_version = 1 and not v_snapshot_complete then
    raise exception using
      errcode = '23514',
      message = 'BRANCH_PRICE_SNAPSHOT_REQUIRED_FOR_V1';
  end if;

  return new;
end;
$$;

drop trigger if exists orders_enforce_branch_contract_029 on public.orders;
create trigger orders_enforce_branch_contract_029
before insert or update of branch_id, regiao, stock_contract_version
on public.orders
for each row execute function public.enforce_branch_order_contract();

drop trigger if exists quotations_enforce_branch_contract_029 on public.quotations;
create trigger quotations_enforce_branch_contract_029
before insert or update of branch_id, regiao, stock_contract_version
on public.quotations
for each row execute function public.enforce_branch_order_contract();

drop trigger if exists order_items_enforce_branch_snapshot_029 on public.order_items;
create trigger order_items_enforce_branch_snapshot_029
before insert or update of order_id, branch_price, branch_price_currency,
  branch_price_version, branch_price_captured_at
on public.order_items
for each row execute function public.enforce_branch_price_snapshot_parent();

drop trigger if exists quotation_items_enforce_branch_snapshot_029
  on public.quotation_items;
create trigger quotation_items_enforce_branch_snapshot_029
before insert or update of quotation_id, branch_price, branch_price_currency,
  branch_price_version, branch_price_captured_at
on public.quotation_items
for each row execute function public.enforce_branch_price_snapshot_parent();

alter table public.order_stock_contract_settings enable row level security;

drop policy if exists order_stock_contract_settings_admin_read_029
  on public.order_stock_contract_settings;
create policy order_stock_contract_settings_admin_read_029
on public.order_stock_contract_settings
for select to authenticated
using (public.is_admin());

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
for select to authenticated
using (
  (
    stock_contract_version = 0
    and (public.is_admin() or user_id = auth.uid())
  )
  or
  (
    stock_contract_version = 1
    and (
      public.is_admin()
      or (
        public.is_active_branch_order_profile()
        and
        public.can_access_branch(branch_id)
        and (
          user_id = auth.uid()
          or public.is_branch_order_supervisor()
        )
      )
    )
  )
);

drop policy if exists order_items_read on public.order_items;
create policy order_items_read on public.order_items
for select to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (
        (
          o.stock_contract_version = 0
          and (public.is_admin() or o.user_id = auth.uid())
        )
        or
        (
          o.stock_contract_version = 1
          and (
            public.is_admin()
            or (
              public.is_active_branch_order_profile()
              and
              public.can_access_branch(o.branch_id)
              and (
                o.user_id = auth.uid()
                or public.is_branch_order_supervisor()
              )
            )
          )
        )
      )
  )
);

drop policy if exists quotations_read on public.quotations;
create policy quotations_read on public.quotations
for select to authenticated
using (
  (
    stock_contract_version = 0
    and (public.is_admin() or user_id = auth.uid())
  )
  or
  (
    stock_contract_version = 1
    and (
      public.is_admin()
      or (
        public.is_active_branch_order_profile()
        and
        public.can_access_branch(branch_id)
        and (
          user_id = auth.uid()
          or public.is_branch_order_supervisor()
        )
      )
    )
  )
);

drop policy if exists quotation_items_read on public.quotation_items;
create policy quotation_items_read on public.quotation_items
for select to authenticated
using (
  exists (
    select 1
    from public.quotations q
    where q.id = quotation_id
      and (
        (
          q.stock_contract_version = 0
          and (public.is_admin() or q.user_id = auth.uid())
        )
        or
        (
          q.stock_contract_version = 1
          and (
            public.is_admin()
            or (
              public.is_active_branch_order_profile()
              and
              public.can_access_branch(q.branch_id)
              and (
                q.user_id = auth.uid()
                or public.is_branch_order_supervisor()
              )
            )
          )
        )
      )
  )
);

revoke all on public.order_stock_contract_settings
  from public, anon, authenticated;
grant select on public.order_stock_contract_settings to authenticated;

revoke all on function public.enforce_branch_order_contract(),
  public.enforce_branch_price_snapshot_parent(),
  public.is_active_branch_order_profile(),
  public.is_branch_order_supervisor()
  from public, anon, authenticated;
grant execute on function public.is_active_branch_order_profile(),
  public.is_branch_order_supervisor()
  to authenticated;

do $$
begin
  if exists (
    select 1
    from public.orders
    where stock_contract_version <> 0
       or logistics_status <> 'LEGACY_UNMANAGED'
  ) then
    raise exception 'MIGRATION_029_BACKFILL_ORDER_CONTRACT_INVALID';
  end if;

  if exists (
    select 1
    from public.quotations
    where stock_contract_version <> 0
  ) then
    raise exception 'MIGRATION_029_BACKFILL_QUOTATION_CONTRACT_INVALID';
  end if;

  if exists (
    select 1
    from public.orders o
    join public.branches b on b.code = o.regiao::text and b.active
    where o.regiao is not null
      and o.branch_id is distinct from b.id
  ) or exists (
    select 1
    from public.quotations q
    join public.branches b on b.code = q.regiao::text and b.active
    where q.regiao is not null
      and q.branch_id is distinct from b.id
  ) then
    raise exception 'MIGRATION_029_BACKFILL_BRANCH_INVALID';
  end if;

  if (
    select count(*)
    from public.order_stock_contract_settings
  ) <> 1 or not exists (
    select 1
    from public.order_stock_contract_settings
    where singleton
      and not order_stock_contract_v1_enabled
  ) then
    raise exception 'MIGRATION_029_V1_FLAG_VALIDATION_FAILED';
  end if;
end;
$$;

commit;
