begin;

revoke all on function public.get_dashboard_summary(jsonb) from public, anon, authenticated, service_role;
drop function if exists public.get_dashboard_summary(jsonb);

drop index if exists public.quotations_dashboard_user_status_created_idx;
drop index if exists public.quotations_dashboard_status_created_idx;
drop index if exists public.orders_dashboard_user_status_created_idx;
drop index if exists public.orders_dashboard_status_created_idx;

-- A RPC get_dashboard_summary() legada e a RPC V2.1 permanecem intactas.
-- Nenhum dado comercial ou objeto das migrations 024/025 e removido.

commit;
