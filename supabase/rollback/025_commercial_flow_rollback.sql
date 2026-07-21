begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

drop trigger if exists orders_commercial_timeline on public.orders;
drop trigger if exists quotations_commercial_timeline on public.quotations;
drop trigger if exists customer_notes_touch_updated_at on public.customer_notes;

drop function if exists public.capture_commercial_timeline_event();
drop function if exists public.convert_quotation_to_order(uuid);
drop function if exists public.toggle_customer_favorite(uuid, boolean);
drop function if exists public.delete_customer_note(uuid);
drop function if exists public.update_customer_note(uuid, text);
drop function if exists public.add_customer_note(uuid, text);
drop function if exists public.get_customer_commercial_profile(uuid);
drop function if exists public.commercial_update_quotation_status(uuid, text);
drop function if exists public.commercial_update_order_status(uuid, text);
drop function if exists public.commercial_update_document_status(text, uuid, text);
drop function if exists public.commercial_update_quotation_items(jsonb);
drop function if exists public.commercial_update_order_items(jsonb);
drop function if exists public.commercial_update_document_items(text, jsonb);
drop function if exists public.commercial_create_quotation(jsonb);
drop function if exists public.commercial_create_order(jsonb);
drop function if exists public.commercial_create_document(text, jsonb);
drop function if exists public.resolve_commercial_client(text, text);
drop function if exists public.can_access_commercial_client(uuid);
drop function if exists public.commercial_active_profile();

drop policy if exists quotation_order_conversions_scoped_read on public.quotation_order_conversions;
drop policy if exists customer_timeline_scoped_read on public.customer_timeline_events;
drop policy if exists customer_notes_scoped_read on public.customer_notes;
drop policy if exists customer_favorites_own_delete on public.customer_favorites;
drop policy if exists customer_favorites_own_insert on public.customer_favorites;
drop policy if exists customer_favorites_own_read on public.customer_favorites;

drop table if exists public.quotation_order_conversions;
drop table if exists public.customer_timeline_events;
drop table if exists public.customer_notes;
drop table if exists public.customer_favorites;

drop index if exists public.orders_client_lookup_idx;
drop index if exists public.quotations_client_lookup_idx;
drop sequence if exists public.order_commercial_number_seq;
drop sequence if exists public.quotation_commercial_number_seq;

delete from public.role_permissions where perfil = 'SUPERVISOR' and modulo = 'novo_pedido';

drop policy if exists orders_scoped_update on public.orders;
drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select
using (public.is_admin() or public.has_module('pedidos') or user_id = auth.uid());

drop policy if exists order_items_read on public.order_items;
create policy order_items_read on public.order_items for select
using (exists (select 1 from public.orders o where o.id = order_id and (public.is_admin() or o.user_id = auth.uid() or public.has_module('pedidos'))));

drop policy if exists quotations_scoped_update on public.quotations;
drop policy if exists quotations_read on public.quotations;
create policy quotations_read on public.quotations for select
using (public.is_admin() or public.has_module('cotacoes') or user_id = auth.uid());

drop policy if exists quotation_items_read on public.quotation_items;
create policy quotation_items_read on public.quotation_items for select
using (exists (select 1 from public.quotations q where q.id = quotation_id and (public.is_admin() or q.user_id = auth.uid() or public.has_module('cotacoes'))));

grant execute on function public.create_order(jsonb), public.create_quotation(jsonb), public.update_order_items(jsonb), public.update_quotation_items(jsonb), public.update_document_status(jsonb) to public, anon, authenticated;
grant all on public.orders, public.order_items, public.quotations, public.quotation_items to anon, authenticated;

commit;

-- This rollback preserves orders, quotations, products, clients, profiles and
-- company_settings. Notes, favorites, generated timeline events and conversion
-- links are complementary Phase 2B data and are removed by this rollback.
