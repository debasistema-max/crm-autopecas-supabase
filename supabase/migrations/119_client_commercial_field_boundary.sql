begin;

-- All browser users share the authenticated database role. Grant only public
-- client fields here; privileged reads of the discount go through scoped RPCs.
revoke select on public.clients from public,anon,authenticated;
revoke select(commercial_discount_percent) on public.clients from public,anon,authenticated;
grant select(id,nome,cnpj,telefone,endereco,created_at,updated_at,codigo_sap_cliente,
  nome_fantasia,email,cidade,estado,ativo,observacoes,assigned_seller_id)
  on public.clients to authenticated;

create function public.find_business_client_scoped(lookup_field text,lookup_value text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare actor public.profiles; result jsonb; search_value text:=nullif(btrim(lookup_value),'');
begin
  if not coalesce(public.is_app_session_active(),false) then raise exception 'SEM_PERMISSAO'; end if;
  actor:=public.commercial_active_profile();
  if actor.id is null or not (actor.perfil::text='ADMIN' or public.has_module('parceiros')) then
    raise exception 'SEM_PERMISSAO';
  end if;
  if lookup_field is null or lookup_field not in ('codigo_sap_cliente','cnpj') then
    raise exception 'CAMPO_BUSCA_CLIENTE_INVALIDO';
  end if;
  if search_value is null then return null; end if;
  if lookup_field='cnpj' then
    search_value:=nullif(regexp_replace(search_value,'\D','','g'),'');
    if search_value is null then return null; end if;
  end if;
  select jsonb_build_object('id',c.id,'assigned_seller_id',c.assigned_seller_id)
    ||case when actor.perfil::text='VENDEDOR' then '{}'::jsonb
      else jsonb_build_object('commercial_discount_percent',c.commercial_discount_percent) end
    into result
  from public.clients c
  where (actor.perfil::text<>'VENDEDOR' or c.assigned_seller_id=actor.id)
    and ((lookup_field='codigo_sap_cliente' and c.codigo_sap_cliente=search_value)
      or (lookup_field='cnpj' and c.cnpj=search_value))
  order by c.created_at,c.id limit 1;
  return result;
end;
$$;
revoke all on function public.find_business_client_scoped(text,text) from public,anon,authenticated;
grant execute on function public.find_business_client_scoped(text,text) to authenticated;

-- Atomic replacement for browser upsert(...).select(discount). This is not a
-- new permission: only the staff already allowed by clients_write may save.
create function public.save_business_client_scoped(payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  actor public.profiles; target_id uuid; seller_id uuid;
  previous_discount numeric; previous_seller uuid; discount numeric; result jsonb;
  client_name text:=nullif(btrim(payload->>'nome'),'');
  email_value text:=nullif(btrim(payload->>'email'),'');
begin
  if not coalesce(public.is_app_session_active(),false) then raise exception 'SEM_PERMISSAO'; end if;
  actor:=public.commercial_active_profile();
  if actor.id is null or actor.perfil::text='VENDEDOR'
     or not (actor.perfil::text='ADMIN' or public.has_module('parceiros')) then
    raise exception 'SEM_PERMISSAO';
  end if;
  if jsonb_typeof(payload) is distinct from 'object' then raise exception 'DADOS_CLIENTE_INVALIDOS'; end if;
  if client_name is null then raise exception 'NOME_CLIENTE_OBRIGATORIO'; end if;
  if email_value is not null and email_value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'EMAIL_CLIENTE_INVALIDO';
  end if;
  target_id:=coalesce(nullif(btrim(payload->>'id'),'')::uuid,gen_random_uuid());
  seller_id:=nullif(btrim(payload->>'assigned_seller_id'),'')::uuid;
  discount:=coalesce(nullif(payload->>'commercial_discount_percent','')::numeric,0);
  if discount::text in ('NaN','Infinity','-Infinity') or discount<0
     or discount>coalesce(public.max_discount_percent(),10) then raise exception 'DESCONTO_CLIENTE_INVALIDO'; end if;
  -- Serialize same-ID upserts, including the case where the row is not created
  -- yet, so a non-ADMIN cannot race a newly created privileged discount.
  perform pg_advisory_xact_lock(hashtextextended('crm-client:'||target_id::text,0));
  select c.commercial_discount_percent,c.assigned_seller_id into previous_discount,previous_seller
    from public.clients c where c.id=target_id for update;
  if seller_id is distinct from previous_seller and seller_id is not null
     and not exists(select 1 from public.profiles p
       where p.id=seller_id and p.ativo and p.perfil::text='VENDEDOR') then
    raise exception 'VENDEDOR_CLIENTE_INVALIDO';
  end if;
  if actor.perfil::text<>'ADMIN' and discount is distinct from coalesce(previous_discount,0) then
    raise exception 'APENAS_ADMIN_ALTERA_DESCONTO_CLIENTE';
  end if;

  insert into public.clients as c(id,codigo_sap_cliente,nome,nome_fantasia,cnpj,telefone,email,
    endereco,cidade,estado,ativo,commercial_discount_percent,assigned_seller_id,observacoes)
  values(target_id,nullif(btrim(payload->>'codigo_sap_cliente'),''),client_name,
    nullif(btrim(payload->>'nome_fantasia'),''),nullif(regexp_replace(coalesce(payload->>'cnpj',''),'\D','','g'),''),
    nullif(btrim(payload->>'telefone'),''),email_value,nullif(btrim(payload->>'endereco'),''),
    nullif(btrim(payload->>'cidade'),''),nullif(upper(btrim(payload->>'estado')),''),
    coalesce((payload->>'ativo')::boolean,true),discount,seller_id,nullif(btrim(payload->>'observacoes'),''))
  on conflict(id) do update set codigo_sap_cliente=excluded.codigo_sap_cliente,nome=excluded.nome,
    nome_fantasia=excluded.nome_fantasia,cnpj=excluded.cnpj,telefone=excluded.telefone,email=excluded.email,
    endereco=excluded.endereco,cidade=excluded.cidade,estado=excluded.estado,ativo=excluded.ativo,
    commercial_discount_percent=excluded.commercial_discount_percent,
    assigned_seller_id=excluded.assigned_seller_id,observacoes=excluded.observacoes
  returning jsonb_build_object('id',c.id,'codigo_sap_cliente',c.codigo_sap_cliente,'nome',c.nome,
    'nome_fantasia',c.nome_fantasia,'cnpj',c.cnpj,'telefone',c.telefone,'email',c.email,
    'endereco',c.endereco,'cidade',c.cidade,'estado',c.estado,'ativo',c.ativo,
    'commercial_discount_percent',c.commercial_discount_percent,'assigned_seller_id',c.assigned_seller_id,
    'observacoes',c.observacoes) into result;

  insert into public.logs(user_id,usuario,acao,entidade,id_entidade,dados_anteriores,dados_novos)
  values(actor.id,actor.usuario,'SALVAR_CLIENTE','clients',target_id::text,
    jsonb_build_object('commercial_discount_percent',previous_discount,'assigned_seller_id',previous_seller),
    jsonb_build_object('commercial_discount_percent',discount,'assigned_seller_id',seller_id,
      'fields',array['codigo_sap_cliente','nome','nome_fantasia','cnpj','telefone','email',
        'endereco','cidade','estado','ativo','commercial_discount_percent','assigned_seller_id','observacoes']));
  return result;
end;
$$;
revoke all on function public.save_business_client_scoped(jsonb) from public,anon,authenticated;
grant execute on function public.save_business_client_scoped(jsonb) to authenticated;

comment on function public.find_business_client_scoped(text,text) is
  'Exact client lookup with portfolio scope; seller responses never include the internal discount.';
comment on function public.save_business_client_scoped(jsonb) is
  'Authorized client upsert and audit in one transaction; discount changes require ADMIN.';
commit;
