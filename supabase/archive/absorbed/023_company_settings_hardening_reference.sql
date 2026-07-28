-- HISTORICAL REFERENCE ONLY - DO NOT APPLY.
-- Audited on 2026-07-28.
-- This hardening was absorbed by remote migration 023_company_settings.
-- The file is preserved outside the active migration flow only for traceability.

do $$
begin
  if to_regclass('public.company_settings') is null then
    raise notice 'company_settings does not exist yet; apply 023_company_settings first.';
    return;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'company_settings_state_len') then
    alter table public.company_settings
      add constraint company_settings_state_len check (state is null or char_length(state) <= 2) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'company_settings_currency_len') then
    alter table public.company_settings
      add constraint company_settings_currency_len check (char_length(currency) = 3) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'company_settings_timezone_len') then
    alter table public.company_settings
      add constraint company_settings_timezone_len check (char_length(timezone) between 1 and 80) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'company_settings_language_len') then
    alter table public.company_settings
      add constraint company_settings_language_len check (char_length(language) between 2 and 16) not valid;
  end if;
end;
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists company_settings_touch_updated_at on public.company_settings;
create trigger company_settings_touch_updated_at
before update on public.company_settings
for each row execute function public.touch_updated_at();

alter table public.company_settings enable row level security;

drop policy if exists company_settings_read on public.company_settings;
create policy company_settings_read
on public.company_settings
for select
using (auth.uid() is not null);

drop policy if exists company_settings_admin_write on public.company_settings;
create policy company_settings_admin_write
on public.company_settings
for all
using (public.is_admin())
with check (public.is_admin());

revoke all on public.company_settings from anon;
revoke all on public.company_settings from authenticated;
grant select on public.company_settings to authenticated;
grant insert, update, delete on public.company_settings to authenticated;

do $$
begin
  if to_regclass('public.settings') is not null then
    update public.settings
    set value = jsonb_set(
      coalesce(value, '{}'::jsonb),
      '{email_principal}',
      '""'::jsonb,
      true
    )
    where key = 'portal_cadastros'
      and value->>'email_principal' = 'financeiro@ipsbrasil.com.br';
  end if;
end;
$$;

create or replace function public.get_public_company_identity()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'company_name', company_name,
    'trade_name', trade_name,
    'logo_url', logo_url,
    'primary_color', primary_color,
    'secondary_color', secondary_color,
    'website', website,
    'phone', phone,
    'whatsapp', whatsapp,
    'email', email,
    'city', city,
    'state', state,
    'language', language
  )
  from public.company_settings
  where id = true;
$$;

grant execute on function public.get_public_company_identity() to anon, authenticated;
