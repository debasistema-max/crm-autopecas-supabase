begin;

do $$
begin
  if to_regclass('public.prospects') is null then
    raise exception 'Tabela public.prospects nao encontrada';
  end if;

  if to_regclass('public.prospecting_cnae_rules') is null then
    raise exception 'Tabela public.prospecting_cnae_rules nao encontrada';
  end if;

  if to_regprocedure('public.list_prospects(jsonb)') is null then
    raise exception 'Funcao public.list_prospects(jsonb) nao encontrada';
  end if;

  if to_regprocedure('public.refresh_prospect_crm_match(uuid)') is null then
    raise exception 'Funcao public.refresh_prospect_crm_match(uuid) nao encontrada';
  end if;

  if not exists (
    select 1
    from public.prospecting_cnae_rules
    where cnae = '4530703'
      and categoria = 'A'
      and ativo
  ) then
    raise exception 'Seed CNAE 4530703 ausente ou inativo';
  end if;

  if not exists (
    select 1
    from public.role_permissions
    where perfil = 'ADMIN'
      and modulo = 'prospeccao'
      and permitido
  ) then
    raise exception 'Permissao ADMIN/prospeccao ausente';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'prospects'
      and policyname = 'prospects_read'
  ) then
    raise exception 'Policy prospects_read ausente';
  end if;
end;
$$;

rollback;
