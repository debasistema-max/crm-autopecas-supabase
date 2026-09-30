begin;

-- A planilha continua imutavel como fonte e conserva o resultado historico com
-- ICMS-ST. A politica abaixo altera somente o preco operacional consumido pelo
-- CRM/B2B, com vigencia datada e rastreavel.
create table if not exists public.commercial_tax_policies (
  code text primary key,
  origin_state text not null check (origin_state ~ '^[A-Z]{2}$'),
  destination_state text not null check (destination_state ~ '^[A-Z]{2}$'),
  calculation_mode text not null check (calculation_mode in ('IPI_ONLY')),
  effective_from date not null,
  effective_until date,
  active boolean not null default true,
  reason text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_until is null or effective_until >= effective_from)
);

alter table public.commercial_tax_policies enable row level security;
revoke all on public.commercial_tax_policies from public,anon,authenticated;
grant select,insert,update,delete on public.commercial_tax_policies to service_role;

insert into public.commercial_tax_policies(
  code,origin_state,destination_state,calculation_mode,effective_from,reason
) values(
  'SP_IPI_ONLY_2026_10_01','SP','SP','IPI_ONLY',date '2026-10-01',
  'Operacoes SP-SP passam a compor o preco comercial somente com IPI, sem ICMS-ST.'
)
on conflict(code) do update set
  origin_state=excluded.origin_state,
  destination_state=excluded.destination_state,
  calculation_mode=excluded.calculation_mode,
  effective_from=excluded.effective_from,
  reason=excluded.reason,
  updated_at=now();

create or replace function public.commercial_business_date()
returns date
language sql
stable
set search_path=public
as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

revoke all on function public.commercial_business_date() from public,anon;
grant execute on function public.commercial_business_date() to authenticated,service_role;

create or replace function public.apply_commercial_tax_policy(
  source_price jsonb,
  target_origin_state text,
  target_destination_state text,
  target_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_source jsonb:=coalesce(source_price,'{}'::jsonb);
  v_origin text:=public.normalize_fiscal_uf(target_origin_state);
  v_destination text:=public.normalize_fiscal_uf(target_destination_state);
  v_policy public.commercial_tax_policies;
  v_base numeric(16,6);
  v_ipi numeric(16,6);
  v_ipi_rate numeric(12,8);
  v_breakdown jsonb;
  v_warnings jsonb;
begin
  select * into v_policy
  from public.commercial_tax_policies p
  where p.active
    and p.origin_state=v_origin
    and p.destination_state=v_destination
    and p.effective_from<=target_date
    and (p.effective_until is null or p.effective_until>=target_date)
  order by p.effective_from desc,p.code
  limit 1;

  if v_policy.code is null then return v_source; end if;
  if upper(coalesce(v_source->>'status','')) not like 'OK%' then return v_source; end if;

  v_base:=nullif(v_source->>'base_price','')::numeric;
  v_ipi:=coalesce(
    nullif(v_source->>'ipi_amount','')::numeric,
    nullif(v_source#>>'{tax_breakdown,ipi}','')::numeric
  );
  if v_ipi is null and nullif(v_source->>'product_code','') is not null then
    select coalesce(p.ipi_rate,case when p.ipi is null then null else p.ipi/100 end)
      into v_ipi_rate
    from public.products p
    where p.codigo=v_source->>'product_code';
    if v_base is not null and v_ipi_rate is not null then
      v_ipi:=round(v_base*v_ipi_rate,6);
    end if;
  end if;

  if v_base is null or v_base<=0 or v_ipi is null or v_ipi<0 then
    return v_source||jsonb_build_object(
      'status','PRECO_FISCAL_INDISPONIVEL',
      'final_price',null,
      'total_taxes',null,
      'price_source','FISCAL_FALLBACK_BLOCKED',
      'tax_policy_applied',false,
      'tax_policy_code',v_policy.code,
      'warnings',coalesce(v_source->'warnings','[]'::jsonb)
        ||jsonb_build_array('BASE_OU_IPI_AUSENTE_PARA_POLITICA_SP')
    );
  end if;

  v_breakdown:=coalesce(v_source->'tax_breakdown','{}'::jsonb)
    ||jsonb_build_object('ipi',v_ipi,'icms_st',0,'pis',0,'cofins',0,'fcp',0);
  v_warnings:=coalesce(v_source->'warnings','[]'::jsonb)
    ||jsonb_build_array('SP_ICMS_ST_REMOVIDO_DESDE_2026_10_01');

  return v_source||jsonb_build_object(
    'source_final_price',v_source->'final_price',
    'source_total_taxes',v_source->'total_taxes',
    'source_tax_breakdown',v_source->'tax_breakdown',
    'total_taxes',round(v_ipi,2),
    'final_price',round(v_base,2)+round(v_ipi,2),
    'ipi_amount',v_ipi,
    'icms_st_amount',0,
    'pis_amount',0,
    'cofins_amount',0,
    'fcp_amount',0,
    'tax_breakdown',v_breakdown,
    'has_st',false,
    'status','OK_SEM_ST',
    'warnings',v_warnings,
    'price_source','EXCEL_ROUTE_PRICE_SP_IPI_ONLY',
    'calculation_profile','SP_IPI_ONLY',
    'calculation_method','BASE_PLUS_IPI',
    'tax_policy_applied',true,
    'tax_policy_code',v_policy.code,
    'tax_policy_effective_from',v_policy.effective_from,
    'tax_policy_reason',v_policy.reason
  );
end;
$$;

revoke all on function public.apply_commercial_tax_policy(jsonb,text,text,date)
  from public,anon,authenticated;

-- Mantem a assinatura publica e envolve o calculo existente. Assim todas as
-- telas internas recebem o mesmo resultado sem alterar o snapshot importado.
alter function public.get_product_commercial_price(text,text,text,date,text)
  rename to get_product_commercial_price_raw_090;
revoke all on function public.get_product_commercial_price_raw_090(text,text,text,date,text)
  from public,anon,authenticated;

create function public.get_product_commercial_price(
  product_code text,
  origin_branch text,
  destination_uf text,
  target_date date default public.commercial_business_date(),
  customer_type text default 'REVENDA'
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_origin text;
begin
  v_result:=public.get_product_commercial_price_raw_090(
    product_code,origin_branch,destination_uf,target_date,customer_type
  );
  v_origin:=coalesce(v_result->>'origin_state',upper(btrim(origin_branch)));
  return public.apply_commercial_tax_policy(v_result,v_origin,destination_uf,target_date);
end;
$$;

revoke all on function public.get_product_commercial_price(text,text,text,date,text)
  from public,anon;
grant execute on function public.get_product_commercial_price(text,text,text,date,text)
  to authenticated,service_role;

-- Recalcula o snapshot persistido depois que os fluxos legados criam ou editam
-- um documento. A data do cabecalho impede alteracao retroativa de pedidos.
create or replace function public.normalize_document_tax_policy(
  document_type text,
  target_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_origin text;
  v_destination text;
  v_created_at timestamptz;
  v_document_date date;
  v_owner_id uuid;
  v_owner_name text;
  v_item_count integer;
  v_valid_count integer;
  v_subtotal numeric(16,2);
  v_discount_total numeric(16,2);
  v_total numeric(16,2);
begin
  if document_type='pedido' then
    select o.regiao::text,coalesce(public.normalize_fiscal_uf(o.billing_uf),o.regiao::text),o.created_at,o.user_id,o.vendedor
      into v_origin,v_destination,v_created_at,v_owner_id,v_owner_name
    from public.orders o where o.id=target_id for update;
  elsif document_type='cotacao' then
    select q.regiao::text,coalesce(public.normalize_fiscal_uf(q.billing_uf),q.regiao::text),q.created_at,q.user_id,q.vendedor
      into v_origin,v_destination,v_created_at,v_owner_id,v_owner_name
    from public.quotations q where q.id=target_id for update;
  else
    raise exception 'TIPO_DOCUMENTO_INVALIDO';
  end if;
  if v_created_at is null then raise exception 'DOCUMENTO_NAO_ENCONTRADO'; end if;
  v_document_date:=(v_created_at at time zone 'America/Sao_Paulo')::date;

  if not exists(
    select 1 from public.commercial_tax_policies p
    where p.active and p.origin_state=v_origin and p.destination_state=v_destination
      and p.effective_from<=v_document_date
      and (p.effective_until is null or p.effective_until>=v_document_date)
  ) then
    return jsonb_build_object('tax_policy_applied',false);
  end if;

  if document_type='pedido' then
    select count(*) into v_item_count from public.order_items where order_id=target_id;
    with effective as (
      select i.id,public.apply_commercial_tax_policy(
        jsonb_build_object(
          'product_code',i.codigo,'route',v_origin||'-'||v_destination,
          'origin_state',v_origin,'destination_state',v_destination,
          'base_price',rp.base_price,'total_taxes',rp.total_taxes,'final_price',rp.final_price,
          'ipi_amount',rp.tax_breakdown->'ipi','own_icms_amount',rp.tax_breakdown->'icms_proprio',
          'icms_st_amount',rp.tax_breakdown->'icms_st','tax_breakdown',rp.tax_breakdown,
          'status',coalesce(rp.calculation_status,'OK'),'warnings','[]'::jsonb,
          'price_source','EXCEL_ROUTE_PRICE','route_price_source',rp.source,
          'route_price_version',rp.version,'route_price_source_version',rp.source_version,
          'route_price_source_updated_at',rp.source_updated_at,'route_price_batch_id',rp.source_batch_id
        ),v_origin,v_destination,v_document_date
      ) calc
      from public.order_items i
      join public.branches b on b.code=v_origin and b.active
      join public.product_route_prices rp on rp.product_code=i.codigo
        and rp.origin_branch_id=b.id and rp.route=v_origin||'-'||v_destination
      where i.order_id=target_id
    )
    select count(*) into v_valid_count from effective
    where calc->>'status' in ('OK','OK_SEM_ST') and (calc->>'tax_policy_applied')::boolean;
    if v_valid_count<>v_item_count then raise exception 'PRECO_IPI_SP_INDISPONIVEL'; end if;

    with effective as (
      select i.id,i.desconto_percentual,public.apply_commercial_tax_policy(
        jsonb_build_object(
          'product_code',i.codigo,'route',v_origin||'-'||v_destination,
          'origin_state',v_origin,'destination_state',v_destination,
          'base_price',rp.base_price,'total_taxes',rp.total_taxes,'final_price',rp.final_price,
          'ipi_amount',rp.tax_breakdown->'ipi','own_icms_amount',rp.tax_breakdown->'icms_proprio',
          'icms_st_amount',rp.tax_breakdown->'icms_st','tax_breakdown',rp.tax_breakdown,
          'status',coalesce(rp.calculation_status,'OK'),'warnings','[]'::jsonb,
          'price_source','EXCEL_ROUTE_PRICE','route_price_source',rp.source,
          'route_price_version',rp.version,'route_price_source_version',rp.source_version,
          'route_price_source_updated_at',rp.source_updated_at,'route_price_batch_id',rp.source_batch_id
        ),v_origin,v_destination,v_document_date
      ) calc
      from public.order_items i
      join public.branches b on b.code=v_origin and b.active
      join public.product_route_prices rp on rp.product_code=i.codigo
        and rp.origin_branch_id=b.id and rp.route=v_origin||'-'||v_destination
      where i.order_id=target_id
    )
    update public.order_items i set
      preco_unitario=(e.calc->>'final_price')::numeric,
      preco_final_unitario=round((e.calc->>'final_price')::numeric*(1-i.desconto_percentual/100),4),
      total_item=round((e.calc->>'final_price')::numeric*(1-i.desconto_percentual/100)*i.quantidade,2),
      preco_sem_imposto_unitario=(e.calc->>'base_price')::numeric,
      imposto_unitario=(e.calc->>'total_taxes')::numeric,
      fiscal_status=e.calc->>'status',
      fiscal_details=e.calc||jsonb_build_object('client_discount_percent',i.desconto_percentual),
      fiscal_calculated_at=now(),fiscal_origin_state=v_origin,fiscal_destination_state=v_destination
    from effective e where i.id=e.id;

    select round(sum(preco_unitario*quantidade),2),round(sum((preco_unitario-preco_final_unitario)*quantidade),2),round(sum(total_item),2)
      into v_subtotal,v_discount_total,v_total from public.order_items where order_id=target_id;
    update public.orders set subtotal=v_subtotal,desconto_total=v_discount_total,total=v_total where id=target_id;
  else
    select count(*) into v_item_count from public.quotation_items where quotation_id=target_id;
    with effective as (
      select i.id,public.apply_commercial_tax_policy(
        jsonb_build_object(
          'product_code',i.codigo,'route',v_origin||'-'||v_destination,
          'origin_state',v_origin,'destination_state',v_destination,
          'base_price',rp.base_price,'total_taxes',rp.total_taxes,'final_price',rp.final_price,
          'ipi_amount',rp.tax_breakdown->'ipi','own_icms_amount',rp.tax_breakdown->'icms_proprio',
          'icms_st_amount',rp.tax_breakdown->'icms_st','tax_breakdown',rp.tax_breakdown,
          'status',coalesce(rp.calculation_status,'OK'),'warnings','[]'::jsonb,
          'price_source','EXCEL_ROUTE_PRICE','route_price_source',rp.source,
          'route_price_version',rp.version,'route_price_source_version',rp.source_version,
          'route_price_source_updated_at',rp.source_updated_at,'route_price_batch_id',rp.source_batch_id
        ),v_origin,v_destination,v_document_date
      ) calc
      from public.quotation_items i
      join public.branches b on b.code=v_origin and b.active
      join public.product_route_prices rp on rp.product_code=i.codigo
        and rp.origin_branch_id=b.id and rp.route=v_origin||'-'||v_destination
      where i.quotation_id=target_id
    )
    select count(*) into v_valid_count from effective
    where calc->>'status' in ('OK','OK_SEM_ST') and (calc->>'tax_policy_applied')::boolean;
    if v_valid_count<>v_item_count then raise exception 'PRECO_IPI_SP_INDISPONIVEL'; end if;

    with effective as (
      select i.id,i.desconto_percentual,public.apply_commercial_tax_policy(
        jsonb_build_object(
          'product_code',i.codigo,'route',v_origin||'-'||v_destination,
          'origin_state',v_origin,'destination_state',v_destination,
          'base_price',rp.base_price,'total_taxes',rp.total_taxes,'final_price',rp.final_price,
          'ipi_amount',rp.tax_breakdown->'ipi','own_icms_amount',rp.tax_breakdown->'icms_proprio',
          'icms_st_amount',rp.tax_breakdown->'icms_st','tax_breakdown',rp.tax_breakdown,
          'status',coalesce(rp.calculation_status,'OK'),'warnings','[]'::jsonb,
          'price_source','EXCEL_ROUTE_PRICE','route_price_source',rp.source,
          'route_price_version',rp.version,'route_price_source_version',rp.source_version,
          'route_price_source_updated_at',rp.source_updated_at,'route_price_batch_id',rp.source_batch_id
        ),v_origin,v_destination,v_document_date
      ) calc
      from public.quotation_items i
      join public.branches b on b.code=v_origin and b.active
      join public.product_route_prices rp on rp.product_code=i.codigo
        and rp.origin_branch_id=b.id and rp.route=v_origin||'-'||v_destination
      where i.quotation_id=target_id
    )
    update public.quotation_items i set
      preco_unitario=(e.calc->>'final_price')::numeric,
      preco_final_unitario=round((e.calc->>'final_price')::numeric*(1-i.desconto_percentual/100),4),
      total_item=round((e.calc->>'final_price')::numeric*(1-i.desconto_percentual/100)*i.quantidade,2),
      preco_sem_imposto_unitario=(e.calc->>'base_price')::numeric,
      imposto_unitario=(e.calc->>'total_taxes')::numeric,
      fiscal_status=e.calc->>'status',
      fiscal_details=e.calc||jsonb_build_object('client_discount_percent',i.desconto_percentual),
      fiscal_calculated_at=now(),fiscal_origin_state=v_origin,fiscal_destination_state=v_destination
    from effective e where i.id=e.id;

    select round(sum(preco_unitario*quantidade),2),round(sum((preco_unitario-preco_final_unitario)*quantidade),2),round(sum(total_item),2)
      into v_subtotal,v_discount_total,v_total from public.quotation_items where quotation_id=target_id;
    update public.quotations set subtotal=v_subtotal,desconto_total=v_discount_total,total=v_total where id=target_id;
  end if;

  insert into public.logs(user_id,usuario,acao,entidade,id_entidade,dados_novos)
  values(v_owner_id,coalesce(v_owner_name,'SISTEMA'),'APLICAR_POLITICA_FISCAL_SP_IPI',
    case when document_type='pedido' then 'orders' else 'quotations' end,target_id::text,
    jsonb_build_object('policy','SP_IPI_ONLY_2026_10_01','subtotal',v_subtotal,
      'discount_total',v_discount_total,'total',v_total,'items',v_item_count));

  return jsonb_build_object('tax_policy_applied',true,'tax_policy_code','SP_IPI_ONLY_2026_10_01',
    'subtotal',v_subtotal,'desconto_total',v_discount_total,'total',v_total);
end;
$$;

revoke all on function public.normalize_document_tax_policy(text,uuid)
  from public,anon,authenticated;

-- Envolve criacao, edicao e conversao sem duplicar os fluxos comerciais.
alter function public.commercial_create_document(text,jsonb)
  rename to commercial_create_document_raw_090;
alter function public.commercial_create_document_raw_090(text,jsonb)
  set timezone='America/Sao_Paulo';
revoke all on function public.commercial_create_document_raw_090(text,jsonb)
  from public,anon,authenticated;
create function public.commercial_create_document(document_type text,payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb; v_policy jsonb;
begin
  v_result:=public.commercial_create_document_raw_090(document_type,payload);
  v_policy:=public.normalize_document_tax_policy(document_type,(v_result->>'id')::uuid);
  return v_result||v_policy;
end;
$$;

alter function public.commercial_update_document_items(text,jsonb)
  rename to commercial_update_document_items_raw_090;
alter function public.commercial_update_document_items_raw_090(text,jsonb)
  set timezone='America/Sao_Paulo';
revoke all on function public.commercial_update_document_items_raw_090(text,jsonb)
  from public,anon,authenticated;
create function public.commercial_update_document_items(document_type text,payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb; v_policy jsonb;
begin
  v_result:=public.commercial_update_document_items_raw_090(document_type,payload);
  v_policy:=public.normalize_document_tax_policy(document_type,(v_result->>'id')::uuid);
  return v_result||v_policy;
end;
$$;

alter function public.convert_quotation_to_order(uuid)
  rename to convert_quotation_to_order_raw_090;
revoke all on function public.convert_quotation_to_order_raw_090(uuid)
  from public,anon,authenticated;
create function public.convert_quotation_to_order(target_quotation_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb; v_policy jsonb;
begin
  v_result:=public.convert_quotation_to_order_raw_090(target_quotation_id);
  v_policy:=public.normalize_document_tax_policy('pedido',(v_result->>'id_pedido')::uuid);
  return v_result||v_policy;
end;
$$;

grant execute on function public.commercial_create_document(text,jsonb),
  public.commercial_update_document_items(text,jsonb),public.convert_quotation_to_order(uuid)
  to authenticated;

-- O B2B possuia leituras diretas da tabela importada. Os wrappers abaixo
-- garantem a mesma politica no catalogo, detalhe e gravacao do documento.
alter function public.b2b_search_catalog(text,text,boolean,integer)
  rename to b2b_search_catalog_raw_090;
revoke all on function public.b2b_search_catalog_raw_090(text,text,boolean,integer)
  from public,anon,authenticated;

create function public.b2b_search_catalog(search_term text,line_filter text,only_available boolean,limit_count integer)
returns table(
  product_code text,description text,brand text,application text,year text,image_url text,
  route text,final_price numeric,currency text,availability text,available_qty numeric,
  source_display_value text,pr_transfer_available_qty numeric,stock_updated_at timestamptz
)
language plpgsql stable security definer set search_path=public as $$
declare v_discount numeric:=0; v_target_date date:=public.commercial_business_date();
begin
  select coalesce(c.commercial_discount_percent,0) into v_discount
  from public.customer_portal_accounts a join public.clients c on c.id=a.client_id and c.ativo
  where a.user_id=auth.uid() and a.active;
  return query
  select r.product_code,r.description,r.brand,r.application,r.year,r.image_url,r.route,
    round((e.calc->>'final_price')::numeric*(1-v_discount/100),4),r.currency,
    r.availability,r.available_qty,r.source_display_value,r.pr_transfer_available_qty,r.stock_updated_at
  from public.b2b_search_catalog_raw_090(search_term,line_filter,only_available,limit_count) r
  join public.branches b on b.code=split_part(r.route,'-',1) and b.active
  join public.product_route_prices rp on rp.product_code=r.product_code and rp.origin_branch_id=b.id and rp.route=r.route
  cross join lateral (
    select public.apply_commercial_tax_policy(jsonb_build_object(
      'product_code',r.product_code,'route',r.route,'origin_state',split_part(r.route,'-',1),
      'destination_state',split_part(r.route,'-',2),'base_price',rp.base_price,
      'total_taxes',rp.total_taxes,'final_price',rp.final_price,'ipi_amount',rp.tax_breakdown->'ipi',
      'icms_st_amount',rp.tax_breakdown->'icms_st','tax_breakdown',rp.tax_breakdown,
      'status',coalesce(rp.calculation_status,'OK'),'warnings','[]'::jsonb
    ),split_part(r.route,'-',1),split_part(r.route,'-',2),v_target_date) calc
  ) e
  where e.calc->>'status' in ('OK','OK_SEM_ST');
end;
$$;

alter function public.b2b_get_catalog_product_detail(text)
  rename to b2b_get_catalog_product_detail_raw_090;
revoke all on function public.b2b_get_catalog_product_detail_raw_090(text)
  from public,anon,authenticated;

create function public.b2b_get_catalog_product_detail(p_product_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_raw jsonb; v_calc jsonb; v_discount numeric:=0; v_route text; v_target_date date:=public.commercial_business_date();
begin
  v_raw:=public.b2b_get_catalog_product_detail_raw_090(p_product_code);
  v_route:=v_raw->>'route';
  select coalesce(c.commercial_discount_percent,0) into v_discount
  from public.customer_portal_accounts a join public.clients c on c.id=a.client_id and c.ativo
  where a.user_id=auth.uid() and a.active;
  select public.apply_commercial_tax_policy(jsonb_build_object(
    'product_code',rp.product_code,'route',rp.route,'origin_state',split_part(rp.route,'-',1),
    'destination_state',split_part(rp.route,'-',2),'base_price',rp.base_price,
    'total_taxes',rp.total_taxes,'final_price',rp.final_price,'ipi_amount',rp.tax_breakdown->'ipi',
    'icms_st_amount',rp.tax_breakdown->'icms_st','tax_breakdown',rp.tax_breakdown,
    'status',coalesce(rp.calculation_status,'OK'),'warnings','[]'::jsonb
  ),split_part(rp.route,'-',1),split_part(rp.route,'-',2),v_target_date) into v_calc
  from public.product_route_prices rp join public.branches b on b.id=rp.origin_branch_id and b.active
  where rp.product_code=public.normalize_integration_product_code(p_product_code) and rp.route=v_route;
  if v_calc->>'status' not in ('OK','OK_SEM_ST') then raise exception 'PRECO_B2B_INDISPONIVEL'; end if;
  return v_raw||jsonb_build_object('final_price',round((v_calc->>'final_price')::numeric*(1-v_discount/100),4),
    'tax_policy_applied',coalesce((v_calc->>'tax_policy_applied')::boolean,false),
    'tax_policy_code',v_calc->>'tax_policy_code');
end;
$$;

alter function public.b2b_create_document(text,jsonb)
  rename to b2b_create_document_raw_090;
revoke all on function public.b2b_create_document_raw_090(text,jsonb)
  from public,anon,authenticated;
create function public.b2b_create_document(document_type text,payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb; v_policy jsonb;
begin
  v_result:=public.b2b_create_document_raw_090(document_type,payload);
  v_policy:=public.normalize_document_tax_policy(document_type,(v_result->>'id')::uuid);
  return v_result||v_policy;
end;
$$;

grant execute on function public.b2b_search_catalog(text,text,boolean,integer),
  public.b2b_get_catalog_product_detail(text),public.b2b_create_document(text,jsonb)
  to authenticated;

comment on table public.commercial_tax_policies is
  'Politicas comerciais datadas aplicadas sem modificar os precos-fonte importados.';
comment on function public.apply_commercial_tax_policy(jsonb,text,text,date) is
  'Aplica politica fiscal operacional datada e preserva no JSON os valores originais da fonte.';
comment on function public.get_product_commercial_price(text,text,text,date,text) is
  'Preco comercial efetivo; desde 01/10/2026 SP-SP usa base mais IPI e nao cobra ICMS-ST.';

commit;
