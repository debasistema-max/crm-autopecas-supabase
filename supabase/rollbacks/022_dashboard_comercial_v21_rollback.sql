-- Rollback manual da migration 022_dashboard_comercial_v21.sql.
-- Executar somente se for necessario remover os objetos criados na V2.1.

drop function if exists public.get_commercial_dashboard_summary(jsonb);

delete from public.role_permissions
where perfil = 'ADMIN'
  and modulo = 'dashboard_comercial';

delete from public.role_permissions
where perfil = 'VENDEDOR'
  and modulo = 'dashboard';
