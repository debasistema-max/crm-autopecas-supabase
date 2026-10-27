begin;

-- All supplied identifiers must refer to the same active portfolio client.
-- Hold the client row until commit so reassignment cannot race document creation.
create or replace function public.assert_seller_client_scope(payload jsonb,allow_anonymous boolean)
returns void
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  actor public.profiles;
  target record;
  resolved_id uuid;
  sap_code text:=nullif(btrim(payload->>'codigo_sap_cliente'),'');
  clean_cnpj text:=nullif(regexp_replace(coalesce(payload->>'cnpj',''),'\D','','g'),'');
  supplied_id text:=nullif(btrim(payload->>'client_id'),'');
  client_name text:=nullif(btrim(payload->>'cliente'),'');
begin
  actor:=public.commercial_active_profile();
  if actor.id is null then raise exception 'SEM_PERMISSAO'; end if;
  if actor.perfil::text<>'VENDEDOR' then return; end if;
  if allow_anonymous and sap_code is null and clean_cnpj is null and supplied_id is null
     and (client_name is null or upper(client_name)=U&'CLIENTE N\00c3O INFORMADO') then return; end if;
  if sap_code is null and clean_cnpj is null then
    raise exception 'CLIENTE_DA_CARTEIRA_OBRIGATORIO';
  end if;
  resolved_id:=public.resolve_commercial_client(sap_code,clean_cnpj);
  select c.id,c.ativo,c.assigned_seller_id,c.codigo_sap_cliente,c.cnpj into target
    from public.clients c where c.id=resolved_id for share;
  if target.id is null or target.ativo is distinct from true
     or target.assigned_seller_id is distinct from actor.id
     or (sap_code is not null and target.codigo_sap_cliente is distinct from sap_code)
     or (clean_cnpj is not null and regexp_replace(coalesce(target.cnpj,''),'\D','','g')<>clean_cnpj)
     or (supplied_id is not null and target.id::text<>supplied_id) then
    raise exception 'CLIENTE_FORA_DA_CARTEIRA';
  end if;
end;
$$;
revoke all on function public.assert_seller_client_scope(jsonb,boolean) from public,anon,authenticated;

-- Keep the existing signature and fiscal pipeline. Enforce scope at the shared
-- entry point, including direct PostgREST calls that bypass the UI wrappers.
create or replace function public.commercial_create_document(document_type text,payload jsonb)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare r jsonb;
begin
  if document_type is null or document_type not in ('pedido','cotacao') then
    raise exception 'TIPO_DOCUMENTO_INVALIDO';
  end if;
  if jsonb_typeof(payload) is distinct from 'object' then raise exception 'DADOS_DOCUMENTO_INVALIDOS'; end if;
  perform public.assert_seller_client_scope(payload,document_type='cotacao');
  r:=public.commercial_create_document_raw_117(document_type,payload);
  return r||public.finalize_document_base_discount(document_type,(r->>'id')::uuid);
end;
$$;
revoke all on function public.commercial_create_document(text,jsonb) from public,anon,authenticated;
grant execute on function public.commercial_create_document(text,jsonb) to authenticated;

-- Conversion creates an order without passing through the generic creator.
-- Recheck the saved client against the current portfolio, not a browser payload.
create or replace function public.convert_quotation_to_order(target_quotation_id uuid)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare actor public.profiles; source record;
begin
  actor:=public.commercial_active_profile();
  if actor.id is null or not public.has_module('novo_pedido') or not public.has_module('cotacoes') then
    raise exception 'SEM_PERMISSAO';
  end if;
  select q.id,q.user_id,q.client_id,q.codigo_sap_cliente,q.cnpj,q.cliente into source
    from public.quotations q where q.id=target_quotation_id for update;
  if source.id is null then raise exception 'COTACAO_NAO_ENCONTRADA'; end if;
  if actor.perfil::text<>'ADMIN' and source.user_id is distinct from actor.id then
    raise exception 'SEM_PERMISSAO';
  end if;
  perform public.assert_seller_client_scope(jsonb_build_object(
    'client_id',source.client_id,'codigo_sap_cliente',source.codigo_sap_cliente,
    'cnpj',source.cnpj,'cliente',source.cliente),false);
  return public.convert_quotation_to_order_raw_090(target_quotation_id);
end;
$$;
revoke all on function public.convert_quotation_to_order(uuid) from public,anon,authenticated;
grant execute on function public.convert_quotation_to_order(uuid) to authenticated;

-- Defense in depth: the legacy delegates and finalizer remain server-only.
revoke all on function public.commercial_create_document_raw_117(text,jsonb),
  public.commercial_create_document_raw_090(text,jsonb),
  public.finalize_document_base_discount(text,uuid),
  public.convert_quotation_to_order_raw_090(uuid),
  public.convert_quotation_to_order_internal_087(uuid) from public,anon,authenticated;

comment on function public.commercial_create_document(text,jsonb) is
  'Shared CRM creation boundary: validates seller portfolio before the transactional fiscal pipeline.';
commit;
