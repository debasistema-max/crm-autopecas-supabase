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
      message = 'ROLLBACK_029_BLOCKED_DOWNSTREAM_MIGRATION';
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
        message = 'ROLLBACK_029_BLOCKED_V1_ENABLED';
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
        message = 'ROLLBACK_029_BLOCKED_ORDER_OPERATIONAL_USE';
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
        message = 'ROLLBACK_029_BLOCKED_QUOTATION_OPERATIONAL_USE';
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
        message = 'ROLLBACK_029_BLOCKED_ORDER_SNAPSHOT_USE';
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
        message = 'ROLLBACK_029_BLOCKED_QUOTATION_SNAPSHOT_USE';
    end if;
  end if;
end;
$$;

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
for select to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists order_items_read on public.order_items;
create policy order_items_read on public.order_items
for select to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (public.is_admin() or o.user_id = auth.uid())
  )
);

drop policy if exists quotations_read on public.quotations;
create policy quotations_read on public.quotations
for select to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists quotation_items_read on public.quotation_items;
create policy quotation_items_read on public.quotation_items
for select to authenticated
using (
  exists (
    select 1
    from public.quotations q
    where q.id = quotation_id
      and (public.is_admin() or q.user_id = auth.uid())
  )
);

drop trigger if exists order_items_enforce_branch_snapshot_029
  on public.order_items;
drop trigger if exists quotation_items_enforce_branch_snapshot_029
  on public.quotation_items;
drop trigger if exists orders_enforce_branch_contract_029
  on public.orders;
drop trigger if exists quotations_enforce_branch_contract_029
  on public.quotations;

drop index if exists public.order_items_order_product_unique_029;
drop index if exists public.quotation_items_quotation_product_unique_029;
drop index if exists public.orders_branch_logistics_v1_idx_029;
drop index if exists public.orders_branch_priority_v1_idx_029;
drop index if exists public.orders_owner_branch_v1_idx_029;
drop index if exists public.quotations_branch_v1_idx_029;
drop index if exists public.quotations_owner_branch_v1_idx_029;

alter table public.order_items
  drop constraint if exists order_items_branch_price_snapshot_check_029;
alter table public.quotation_items
  drop constraint if exists quotation_items_branch_price_snapshot_check_029;

alter table public.orders
  drop constraint if exists orders_contract_dates_check_029,
  drop constraint if exists orders_contract_coherence_check_029,
  drop constraint if exists orders_operational_version_check_029,
  drop constraint if exists orders_priority_check_029,
  drop constraint if exists orders_logistics_status_check_029,
  drop constraint if exists orders_stock_contract_version_check_029,
  drop constraint if exists orders_branch_id_fkey_029;

alter table public.quotations
  drop constraint if exists quotations_contract_dates_check_029,
  drop constraint if exists quotations_contract_coherence_check_029,
  drop constraint if exists quotations_operational_version_check_029,
  drop constraint if exists quotations_priority_check_029,
  drop constraint if exists quotations_stock_contract_version_check_029,
  drop constraint if exists quotations_branch_id_fkey_029;

alter table public.order_items
  drop column if exists branch_price_captured_at,
  drop column if exists branch_price_version,
  drop column if exists branch_price_currency,
  drop column if exists branch_price;

alter table public.quotation_items
  drop column if exists branch_price_captured_at,
  drop column if exists branch_price_version,
  drop column if exists branch_price_currency,
  drop column if exists branch_price;

alter table public.orders
  drop column if exists price_revalidation_required_at,
  drop column if exists approval_requested_at,
  drop column if exists branch_locked_at,
  drop column if exists operational_version,
  drop column if exists promised_at,
  drop column if exists priority,
  drop column if exists logistics_status,
  drop column if exists stock_contract_version,
  drop column if exists branch_id;

alter table public.quotations
  drop column if exists operational_version,
  drop column if exists promised_at,
  drop column if exists priority,
  drop column if exists stock_contract_version,
  drop column if exists branch_id;

drop policy if exists order_stock_contract_settings_admin_read_029
  on public.order_stock_contract_settings;
drop trigger if exists order_stock_contract_settings_touch_updated_at
  on public.order_stock_contract_settings;
drop table if exists public.order_stock_contract_settings;

drop function if exists public.enforce_branch_price_snapshot_parent();
drop function if exists public.enforce_branch_order_contract();
drop function if exists public.is_branch_order_supervisor();
drop function if exists public.is_active_branch_order_profile();

commit;
