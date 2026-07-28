begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $$
begin
  if exists (
    select 1
    from public.profile_branches
  ) then
    raise exception 'ROLLBACK_BLOQUEADO: existem vinculos de usuarios com filiais';
  end if;

  if exists (
    select 1
    from public.branches
    where code not in ('PR', 'SP')
  ) then
    raise exception 'ROLLBACK_BLOQUEADO: existem filiais adicionais';
  end if;

  if exists (
    select 1
    from public.product_branch_stock
    where reserved_order_qty <> 0
       or reserved_transfer_qty <> 0
       or in_transit_qty <> 0
       or quarantined_qty <> 0
       or minimum_stock_qty <> 0
       or reorder_point_qty <> 0
       or target_stock_qty <> 0
       or auto_replenishment_enabled
       or replenishment_source_branch_id is not null
  ) then
    raise exception 'ROLLBACK_BLOQUEADO: a fundacao ja possui dados operacionais';
  end if;

  if exists (
    select 1
    from public.stock_movements
    where source not in ('MIGRACAO_FUNDACAO_027', 'LEGACY_PRODUCTS_SYNC')
  ) then
    raise exception 'ROLLBACK_BLOQUEADO: existem movimentacoes fora da compatibilidade legada';
  end if;
end;
$$;

drop trigger if exists products_insert_sync_legacy_stock_to_pr on public.products;
drop trigger if exists products_update_sync_legacy_stock_to_pr on public.products;
revoke all on function public.sync_legacy_product_stock_to_pr() from public, anon, authenticated;
drop function if exists public.sync_legacy_product_stock_to_pr();

drop policy if exists stock_movements_audit_read on public.stock_movements;
drop policy if exists product_branch_stock_commercial_read on public.product_branch_stock;
drop policy if exists profile_branches_admin_delete on public.profile_branches;
drop policy if exists profile_branches_admin_update on public.profile_branches;
drop policy if exists profile_branches_admin_insert on public.profile_branches;
drop policy if exists profile_branches_scoped_read on public.profile_branches;
drop policy if exists branches_admin_update on public.branches;
drop policy if exists branches_admin_insert on public.branches;
drop policy if exists branches_authenticated_read on public.branches;

revoke all on function public.can_access_branch(uuid), public.get_default_branch_id()
  from public, anon, authenticated;
drop function if exists public.can_access_branch(uuid);
drop function if exists public.get_default_branch_id();

drop trigger if exists stock_movements_immutable on public.stock_movements;
revoke all on function public.reject_stock_movement_mutation() from public, anon, authenticated;
drop function if exists public.reject_stock_movement_mutation();

drop trigger if exists product_branch_stock_touch_updated_at on public.product_branch_stock;
revoke all on function public.touch_product_branch_stock() from public, anon, authenticated;
drop function if exists public.touch_product_branch_stock();

drop trigger if exists profile_branches_touch_updated_at on public.profile_branches;
drop trigger if exists branches_touch_updated_at on public.branches;

drop table if exists public.stock_movements;
drop table if exists public.product_branch_stock;
drop table if exists public.profile_branches;
drop table if exists public.branches;

commit;
