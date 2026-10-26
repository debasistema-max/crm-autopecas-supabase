begin;
set local statement_timeout='110s';
create function pg_temp.assert117(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'REG117:%',label; end if; end $$;
do $$ declare s jsonb; r jsonb; blocked boolean; begin
  s:='{"status":"OK","base_price":100,"ipi_amount":10,"icms_st_amount":20,"total_taxes":30,"final_price":130,"tax_breakdown":{"ipi":10,"icms_st":20,"icms_proprio":12}}';
  r:=public.apply_document_base_discount(s,10);
  perform pg_temp.assert117((r->>'base_price')::numeric=90,'discounted_base');
  perform pg_temp.assert117((r->>'ipi_amount')::numeric=9,'ipi_rebased');
  perform pg_temp.assert117((r->>'icms_st_amount')::numeric=18,'st_rebased');
  perform pg_temp.assert117((r->>'final_price')::numeric=117,'final');
  perform pg_temp.assert117(public.apply_document_base_discount(r,10)=r,'idempotent');
  perform pg_temp.assert117((public.apply_document_base_discount(r,20)->>'final_price')::numeric=104,'changed_discount');
  perform pg_temp.assert117((public.apply_document_base_discount(s,100)->>'final_price')::numeric=0,'full_discount');
  s:=s||'{"status":"OK_SEM_ST","icms_st_amount":0,"total_taxes":10,"final_price":110}';
  r:=public.apply_document_base_discount(s,10);
  perform pg_temp.assert117((r->>'final_price')::numeric=99 and (r->>'icms_st_amount')::numeric=0,'ipi_only');
  blocked:=false;
  begin perform public.apply_document_base_discount(s,101); exception when others then blocked:=true; end;
  perform pg_temp.assert117(blocked,'invalid_discount_blocked');
  blocked:=false;
  begin perform public.apply_document_base_discount(s||'{"status":"PRECO_FISCAL_INDISPONIVEL"}',10); exception when others then blocked:=true; end;
  perform pg_temp.assert117(blocked,'unapproved_price_blocked');
end $$;
select pg_temp.assert117(not has_function_privilege('anon','public.apply_document_base_discount(jsonb,numeric)','execute'),'anon_helper_denied');
select pg_temp.assert117(not has_function_privilege('authenticated','public.finalize_document_base_discount(text,uuid)','execute'),'internal_finalizer_denied');
select pg_temp.assert117(not has_function_privilege('authenticated','public.commercial_create_document_raw_117(text,jsonb)','execute'),'raw_create_denied');
select pg_temp.assert117(not has_function_privilege('authenticated','public.commercial_update_document_items_raw_117(text,jsonb)','execute'),'raw_update_denied');

create temp table reg117_context(uid uuid,sid uuid,code text);
insert into reg117_context select gen_random_uuid(),gen_random_uuid(),codigo
  from public.products where ativo and coalesce(ncm,'')<>'' order by codigo limit 1;
grant select on reg117_context to authenticated;
do $$ declare c record; begin
  select * into c from reg117_context;
  if c.code is null then raise exception 'REG117_NO_ACTIVE_FIXTURE'; end if;
  insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
    values(c.uid,'authenticated','authenticated',c.uid||'@example.invalid','{}','{}');
  insert into public.profiles(id,usuario,nome,email,perfil,ativo)
    values(c.uid,c.uid::text,'REG117',c.uid||'@example.invalid','ADMIN',true);
  insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
    values(c.sid,c.uid,now()-interval '2 minutes',now(),now()+interval '1 hour');
  insert into public.app_sessions(user_id,active_session_id,auth_created_at)
    values(c.uid,c.sid,now()-interval '2 minutes');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',c.uid,'role','authenticated','session_id',c.sid)::text,true);
end $$;
set local role authenticated;
do $$ declare candidate record; c text; source jsonb; expected jsonb; r jsonb; item record; kind text; failed boolean;
  test_discount numeric:=least(10,greatest(coalesce(public.max_discount_percent(),0),0));
begin
  for candidate in select codigo from public.products where ativo and coalesce(ncm,'')<>'' order by codigo limit 100 loop
    source:=public.get_product_commercial_price(candidate.codigo,'SP','SP',public.commercial_business_date(),'REVENDA');
    if source->>'status' in ('OK','OK_SEM_ST') then c:=candidate.codigo; exit; end if;
  end loop;
  if c is null then raise exception 'REG117_NO_APPROVED_SP_PRICE'; end if;
  foreach kind in array array['pedido','cotacao'] loop
    r:=public.commercial_create_document(kind,jsonb_build_object(
      'cliente','REG117 TRANSACAO COM ROLLBACK','regiao','SP','cliente_estado','SP','customer_type','REVENDA',
      'items',jsonb_build_array(jsonb_build_object('codigo',c,'quantidade',2,'desconto_percentual',test_discount))));
    if kind='pedido' then select * into item from public.order_items where order_id=(r->>'id')::uuid;
    else select * into item from public.quotation_items where quotation_id=(r->>'id')::uuid; end if;
    expected:=jsonb_build_object('final_price',round(round((source->>'base_price')::numeric*(1-test_discount/100),6)
      +round((source->>'total_taxes')::numeric*(1-test_discount/100),6)
      +round(coalesce((source->>'total_expenses')::numeric,0)*(1-test_discount/100),6),4));
    perform pg_temp.assert117(item.fiscal_details->>'discount_basis'='BASE_PRICE',kind||'_snapshot');
    perform pg_temp.assert117(item.preco_final_unitario=(expected->>'final_price')::numeric,kind||'_authoritative_total');
    perform pg_temp.assert117(item.imposto_unitario=(item.fiscal_details->>'total_taxes')::numeric+(item.fiscal_details->>'total_expenses')::numeric,kind||'_tax_snapshot');
    perform pg_temp.assert117((r->>'total')::numeric=item.total_item,kind||'_header_total');
    perform pg_temp.assert117((r->>'desconto_total')::numeric=round((item.fiscal_details->>'base_discount_amount')::numeric*2,2),kind||'_base_discount');
    r:=public.commercial_update_document_items(kind,jsonb_build_object('id',r->>'id','customer_type','REVENDA',
      'items',jsonb_build_array(jsonb_build_object('codigo',c,'quantidade',3,'desconto_percentual',test_discount/2))));
    if kind='pedido' then select * into item from public.order_items where order_id=(r->>'id')::uuid;
    else select * into item from public.quotation_items where quotation_id=(r->>'id')::uuid; end if;
    expected:=jsonb_build_object('final_price',round(round((source->>'base_price')::numeric*(1-test_discount/200),6)
      +round((source->>'total_taxes')::numeric*(1-test_discount/200),6)
      +round(coalesce((source->>'total_expenses')::numeric,0)*(1-test_discount/200),6),4));
    perform pg_temp.assert117(item.fiscal_details->>'discount_basis'='BASE_PRICE',kind||'_edited_snapshot');
    perform pg_temp.assert117(item.preco_final_unitario=(expected->>'final_price')::numeric,kind||'_edited_authoritative_total');
    perform pg_temp.assert117((item.fiscal_details->>'discount_percent')::numeric=test_discount/2,kind||'_edited_discount');
    perform pg_temp.assert117((r->>'total')::numeric=item.total_item,kind||'_edited_total');
  end loop;
  perform set_config('request.jwt.claims','{}',true);
  failed:=false;
  begin perform public.commercial_create_document('pedido','{}'); exception when others then failed:=true; end;
  perform pg_temp.assert117(failed,'no_session_denied');
end $$;
reset role;
rollback;
