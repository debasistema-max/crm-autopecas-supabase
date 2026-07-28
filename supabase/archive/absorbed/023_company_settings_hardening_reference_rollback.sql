-- HISTORICAL REFERENCE ONLY - DO NOT APPLY.
-- Audited on 2026-07-28.
-- This rollback belongs to hardening absorbed by remote migration
-- 023_company_settings and is preserved only for traceability.

drop function if exists public.get_public_company_identity();

drop policy if exists company_settings_admin_write on public.company_settings;
drop policy if exists company_settings_read on public.company_settings;

create policy company_settings_read
on public.company_settings
for select
using (true);

create policy company_settings_admin_write
on public.company_settings
for all
using (public.is_admin())
with check (public.is_admin());

grant select on public.company_settings to anon, authenticated;
grant insert, update, delete on public.company_settings to authenticated;

alter table if exists public.company_settings
  drop constraint if exists company_settings_language_len;

alter table if exists public.company_settings
  drop constraint if exists company_settings_timezone_len;

alter table if exists public.company_settings
  drop constraint if exists company_settings_currency_len;

alter table if exists public.company_settings
  drop constraint if exists company_settings_state_len;
