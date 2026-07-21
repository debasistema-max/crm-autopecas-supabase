begin;

delete from public.role_permissions
where perfil = 'ADMIN'
  and modulo = 'configuracoes_empresa';

drop policy if exists company_settings_admin_write on public.company_settings;
drop policy if exists company_settings_read on public.company_settings;
drop trigger if exists company_settings_touch_updated_at on public.company_settings;
drop table if exists public.company_settings;

commit;
