begin;

set local statement_timeout = '60s';
set local lock_timeout = '10s';
set local search_path = public, extensions;

drop function if exists public.record_product_recent_view(text, integer);
drop function if exists public.get_top_selling_products(integer);
drop function if exists public.get_product_stock_history(text, integer);
drop function if exists public.get_product_price_history(text, integer);

do $$
begin
  if to_regclass('public.product_recent_views') is not null then
    drop policy if exists product_recent_views_delete_own on public.product_recent_views;
    drop policy if exists product_recent_views_update_own on public.product_recent_views;
    drop policy if exists product_recent_views_insert_own on public.product_recent_views;
    drop policy if exists product_recent_views_select_own on public.product_recent_views;
    drop policy if exists product_recent_views_own_write on public.product_recent_views;
    drop policy if exists product_recent_views_own_read on public.product_recent_views;
  end if;

  if to_regclass('public.product_favorites') is not null then
    drop policy if exists product_favorites_delete_own on public.product_favorites;
    drop policy if exists product_favorites_insert_own on public.product_favorites;
    drop policy if exists product_favorites_select_own on public.product_favorites;
    drop policy if exists product_favorites_own_write on public.product_favorites;
    drop policy if exists product_favorites_own_read on public.product_favorites;
  end if;
end;
$$;

drop table if exists public.product_recent_views;
drop table if exists public.product_favorites;

drop index if exists public.products_url_imagem_present_idx;
drop index if exists public.products_aplicacao_trgm_idx;
drop index if exists public.products_similar_trgm_idx;
drop index if exists public.products_oem_trgm_idx;
drop index if exists public.products_montadora_idx;
drop index if exists public.products_grupo_idx;
drop index if exists public.products_categoria_idx;

commit;
