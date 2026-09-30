begin;

do $$
declare
  owner_id uuid;
begin
  select p.id into owner_id
  from public.profiles p
  where lower(p.email) = 'deivid95@gmail.com'
    and p.ativo = true
  limit 1;

  if owner_id is null then
    raise exception 'Usuario owner do RADAR nao encontrado';
  end if;

  if not exists (
    select 1
    from public.prospecting_access_users
    where profile_id = owner_id
      and access_level = 'OWNER'
      and active
  ) then
    raise exception 'Owner do RADAR nao esta na allowlist';
  end if;

  if exists (
    select 1
    from public.role_permissions
    where modulo in ('prospeccao', 'prospeccao_admin')
      and perfil <> 'ADMIN'
      and permitido
  ) then
    raise exception 'Prospeccao continua habilitada para perfil nao ADMIN';
  end if;
end;
$$;

rollback;
