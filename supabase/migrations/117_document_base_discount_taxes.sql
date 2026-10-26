begin;

-- Approved commercial snapshots are proportional to their base (including MVA
-- and the existing route policies). Never introduce an unapproved rule fallback.
create function public.apply_document_base_discount(source_price jsonb, discount_percent numeric)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public as $$
declare
  s jsonb:=coalesce(source_price->'undiscounted_price',source_price);
  r jsonb; breakdown jsonb; k text; amount numeric;
  base numeric; ipi numeric; st numeric; taxes numeric; expenses numeric;
  factor numeric; discounted_base numeric; discounted_taxes numeric; discounted_expenses numeric;
begin
  if discount_percent is null or discount_percent::text in ('NaN','Infinity','-Infinity')
     or discount_percent<0 or discount_percent>100 then raise exception 'DESCONTO_INVALIDO'; end if;
  if coalesce(s->>'status','') not in ('OK','OK_SEM_ST') then raise exception 'PRECO_FISCAL_INDISPONIVEL'; end if;
  base:=nullif(s->>'base_price','')::numeric;
  ipi:=coalesce(nullif(s->>'ipi_amount','')::numeric,nullif(s#>>'{tax_breakdown,ipi}','')::numeric);
  st:=coalesce(nullif(s->>'icms_st_amount','')::numeric,nullif(s#>>'{tax_breakdown,icms_st}','')::numeric);
  taxes:=nullif(s->>'total_taxes','')::numeric;
  expenses:=coalesce(nullif(s->>'total_expenses','')::numeric,0);
  if base is null or base<=0 or ipi is null or st is null or taxes is null
     or base::text in ('NaN','Infinity','-Infinity') or taxes::text in ('NaN','Infinity','-Infinity')
     or ipi<0 or st<0 or taxes<0 or expenses<0 or ipi::text in ('NaN','Infinity','-Infinity')
     or st::text in ('NaN','Infinity','-Infinity') or expenses::text in ('NaN','Infinity','-Infinity')
     or nullif(s->>'final_price','') is null
     or abs((s->>'final_price')::numeric-base-taxes-expenses)>0.02 then
    raise exception 'COMPOSICAO_FISCAL_INDISPONIVEL';
  end if;
  factor:=1-discount_percent/100;
  discounted_base:=round(base*factor,6);
  discounted_taxes:=round(taxes*factor,6);
  discounted_expenses:=round(expenses*factor,6);
  r:=s;
  breakdown:=coalesce(s->'tax_breakdown','{}'::jsonb);
  foreach k in array array['ipi','icms_st','icms_proprio','pis','cofins','fcp'] loop
    amount:=nullif(breakdown->>k,'')::numeric;
    if amount is not null then breakdown:=jsonb_set(breakdown,array[k],to_jsonb(round(amount*factor,6))); end if;
  end loop;
  foreach k in array array['ipi_amount','icms_st_amount','own_icms_amount','pis_amount','cofins_amount','fcp_amount'] loop
    amount:=nullif(s->>k,'')::numeric;
    if amount is not null then r:=jsonb_set(r,array[k],to_jsonb(round(amount*factor,6))); end if;
  end loop;
  return r||jsonb_build_object(
    'discount_basis','BASE_PRICE','discount_percent',discount_percent,
    'undiscounted_price',s,'original_base_price',base,
    'base_discount_amount',round(base-discounted_base,6),'base_price',discounted_base,
    'ipi_amount',round(ipi*factor,6),'icms_st_amount',round(st*factor,6),
    'tax_breakdown',breakdown,'total_taxes',discounted_taxes,'total_expenses',discounted_expenses,
    'final_price',round(discounted_base+discounted_taxes+discounted_expenses,4)
  );
end;
$$;
revoke all on function public.apply_document_base_discount(jsonb,numeric) from public,anon,authenticated;

-- Called only after the existing transactional CRM RPC has authorized and
-- priced the document. No existing document is modified by this migration.
create function public.finalize_document_base_discount(document_type text,target_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  t text; parent_col text; header text; totals record; actor public.profiles;
  previous_total numeric; owner_id uuid;
begin
  actor:=public.commercial_active_profile();
  if actor.id is null then raise exception 'SEM_PERMISSAO'; end if;
  if document_type='pedido' then t:='order_items';parent_col:='order_id';header:='orders';
  elsif document_type='cotacao' then t:='quotation_items';parent_col:='quotation_id';header:='quotations';
  else raise exception 'TIPO_DOCUMENTO_INVALIDO'; end if;
  execute format('select total,user_id from public.%I where id=$1 for update',header)
    into previous_total,owner_id using target_id;
  if owner_id is null then raise exception 'DOCUMENTO_NAO_ENCONTRADO'; end if;
  if actor.perfil<>'ADMIN' and owner_id<>actor.id then raise exception 'SEM_PERMISSAO'; end if;
  execute format($sql$
    with calc as materialized (
      select id,public.apply_document_base_discount(fiscal_details,desconto_percentual) as price
      from public.%I where %I=$1
    ) update public.%I i set
      preco_unitario=(c.price#>>'{undiscounted_price,final_price}')::numeric,
      preco_sem_imposto_unitario=(c.price->>'base_price')::numeric,
      imposto_unitario=(c.price->>'total_taxes')::numeric+(c.price->>'total_expenses')::numeric,
      preco_final_unitario=(c.price->>'final_price')::numeric,
      total_item=round((c.price->>'final_price')::numeric*i.quantidade,2),
      fiscal_details=c.price,fiscal_calculated_at=now()
    from calc c where i.id=c.id
  $sql$,t,parent_col,t) using target_id;
  execute format($sql$
    select round(sum((fiscal_details->>'original_base_price')::numeric*quantidade),2) as subtotal,
      round(sum((fiscal_details->>'base_discount_amount')::numeric*quantidade),2) as discount,
      round(sum(total_item),2) as total,
      round(sum((fiscal_details->>'ipi_amount')::numeric*quantidade),2) as ipi,
      round(sum((fiscal_details->>'icms_st_amount')::numeric*quantidade),2) as st
    from public.%I where %I=$1
  $sql$,t,parent_col) into totals using target_id;
  if totals.total is null then raise exception 'ITENS_OBRIGATORIOS'; end if;
  execute format('update public.%I set subtotal=$2,desconto_total=$3,total=$4 where id=$1',header)
    using target_id,totals.subtotal,totals.discount,totals.total;
  update public.customer_timeline_events set amount=totals.total
    where entity_id=target_id and event_type in ('PEDIDO_CRIADO','COTACAO_CRIADA');
  insert into public.logs(user_id,usuario,acao,entidade,id_entidade,dados_anteriores,dados_novos)
  values(actor.id,actor.usuario,'RECALCULAR_IMPOSTOS_DESCONTO_BASE',header,target_id::text,
    jsonb_build_object('total',previous_total),to_jsonb(totals)||jsonb_build_object('discount_basis','BASE_PRICE'));
  return jsonb_build_object('subtotal',totals.subtotal,'desconto_total',totals.discount,'total',totals.total,
    'ipi_total',totals.ipi,'st_total',totals.st,'discount_basis','BASE_PRICE');
end;
$$;
revoke all on function public.finalize_document_base_discount(text,uuid) from public,anon,authenticated;

alter function public.commercial_create_document(text,jsonb) rename to commercial_create_document_raw_117;
revoke all on function public.commercial_create_document_raw_117(text,jsonb) from public,anon,authenticated;
create function public.commercial_create_document(document_type text,payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare r jsonb;
begin
  r:=public.commercial_create_document_raw_117(document_type,payload);
  return r||public.finalize_document_base_discount(document_type,(r->>'id')::uuid);
end;
$$;

alter function public.commercial_update_document_items(text,jsonb) rename to commercial_update_document_items_raw_117;
revoke all on function public.commercial_update_document_items_raw_117(text,jsonb) from public,anon,authenticated;
create function public.commercial_update_document_items(document_type text,payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare r jsonb;
begin
  r:=public.commercial_update_document_items_raw_117(document_type,payload);
  return r||public.finalize_document_base_discount(document_type,(r->>'id')::uuid);
end;
$$;

-- Conversion must copy the saved snapshot, not apply a discount twice through
-- the legacy policy normalizer. Restore the already authorized copier here.
create or replace function public.convert_quotation_to_order(target_quotation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  return public.convert_quotation_to_order_raw_090(target_quotation_id);
end;
$$;
revoke all on function public.commercial_create_document(text,jsonb),public.commercial_update_document_items(text,jsonb)
  from public,anon;
grant execute on function public.commercial_create_document(text,jsonb),public.commercial_update_document_items(text,jsonb)
  to authenticated;

comment on function public.apply_document_base_discount(jsonb,numeric) is
  'Rebases approved route tax components on the discounted base; preserves the undiscounted evidence and never resolves fallback rules.';
commit;
