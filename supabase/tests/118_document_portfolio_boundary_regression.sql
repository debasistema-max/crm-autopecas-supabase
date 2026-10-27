-- Only run against the fictional authorization fixture in a disposable database.
-- This file does not create or select real customers and rolls back every test.
begin;
do $$ begin
  if current_setting('crm.test_disposable',true) is distinct from 'on' then
    raise exception 'DISPOSABLE_FIXTURE_REQUIRED';
  end if;
end $$;
create function pg_temp.assert118(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'REG118:%',label; end if; end $$;

select pg_temp.assert118(not has_function_privilege('anon','public.commercial_create_document(text,jsonb)','execute'),'anonymous_denied');
select pg_temp.assert118(not has_function_privilege('authenticated','public.commercial_create_document_raw_117(text,jsonb)','execute'),'raw_117_denied');
select pg_temp.assert118(not has_function_privilege('authenticated','public.commercial_create_document_raw_090(text,jsonb)','execute'),'raw_090_denied');
select pg_temp.assert118(not has_function_privilege('authenticated','public.assert_seller_client_scope(jsonb,boolean)','execute'),'guard_not_public');
select pg_temp.assert118(not has_function_privilege('authenticated','public.finalize_document_base_discount(text,uuid)','execute'),'finalizer_denied');
select pg_temp.assert118(not has_function_privilege('authenticated','public.convert_quotation_to_order_raw_090(uuid)','execute'),'conversion_delegate_denied');

-- The fixture supplies active sessions and product LAB-PRODUCT. The creation
-- bodies are the actual migration-117 chain; fiscal/operational services are stubs.
update public.clients set cnpj='00000000000101' where codigo_sap_cliente='LAB-A';
update public.clients set cnpj='00000000000202' where codigo_sap_cliente='LAB-B';
insert into public.quotations(id,user_id,cliente,codigo_sap_cliente,cnpj,client_id,status,regiao) values
 ('40000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','LAB ONLY','LAB-A','00000000000101','10000000-0000-4000-8000-000000000001','APROVADA','PR'),
 ('40000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','LAB ONLY','LAB-B','00000000000202','10000000-0000-4000-8000-000000000002','APROVADA','PR'),
 ('40000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000002','LAB ONLY','LAB-B','00000000000202','10000000-0000-4000-8000-000000000002','APROVADA','PR'),
 ('40000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001',U&'CLIENTE N\00c3O INFORMADO',null,null,null,'APROVADA','PR'),
 ('40000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000001','LAB ONLY','LAB-A','00000000000101','10000000-0000-4000-8000-000000000002','APROVADA','PR');
insert into public.quotation_items(quotation_id,item,codigo,quantidade,preco_unitario,desconto_percentual,preco_final_unitario,total_item)
 select id,1,'LAB-PRODUCT',1,130,0,130,130 from public.quotations where id::text like '40000000-%';
select set_config('lab.uid','00000000-0000-4000-8000-000000000001',true),
       set_config('lab.sid','20000000-0000-4000-8000-000000000001',true);
set local role authenticated;

do $$
declare
  base jsonb:='{"cliente":"LAB ONLY","regiao":"PR","cliente_estado":"PR","items":[{"codigo":"LAB-PRODUCT","quantidade":1}]}';
  own jsonb:=base||'{"codigo_sap_cliente":"LAB-A","cnpj":"00.000.000/0001-01"}';
  malicious jsonb; r jsonb; kind text; before_count bigint; after_count bigint; message text;
begin
  foreach kind in array array['pedido','cotacao'] loop
    r:=public.commercial_create_document(kind,own);
    perform pg_temp.assert118(r->>'id' is not null,kind||'_own_generic_allowed');
    if kind='pedido' then
      perform pg_temp.assert118(exists(select 1 from public.orders where id=(r->>'id')::uuid
        and client_id='10000000-0000-4000-8000-000000000001' and user_id=auth.uid()),'own_order_link');
      r:=public.commercial_create_order(own);
    else
      perform pg_temp.assert118(exists(select 1 from public.quotations where id=(r->>'id')::uuid
        and client_id='10000000-0000-4000-8000-000000000001' and user_id=auth.uid()),'own_quote_link');
      r:=public.commercial_create_quotation(own);
    end if;
    perform pg_temp.assert118(r->>'id' is not null,kind||'_wrapper_allowed');
    select (select count(*) from public.orders)+(select count(*) from public.quotations) into before_count;
    for malicious in select value from jsonb_array_elements(jsonb_build_array(
      base||'{"codigo_sap_cliente":"LAB-B"}',
      base||'{"cnpj":"00000000000202"}',
      base||'{"codigo_sap_cliente":"LAB-B","cnpj":"00000000000101"}',
      base||'{"codigo_sap_cliente":"LAB-A","cnpj":"00000000000202"}',
      own||'{"client_id":"10000000-0000-4000-8000-000000000002"}',
      base||'{"codigo_sap_cliente":"LAB-MISSING"}'
    )) loop
      message:=null;
      begin perform public.commercial_create_document(kind,malicious);
      exception when others then message:=sqlerrm; end;
      perform pg_temp.assert118(message='CLIENTE_FORA_DA_CARTEIRA',kind||'_direct_foreign_or_conflict_denied');
      message:=null;
      begin
        if kind='pedido' then perform public.commercial_create_order(malicious);
        else perform public.commercial_create_quotation(malicious); end if;
      exception when others then message:=sqlerrm; end;
      perform pg_temp.assert118(message='CLIENTE_FORA_DA_CARTEIRA',kind||'_wrapper_foreign_or_conflict_denied');
    end loop;
    select (select count(*) from public.orders)+(select count(*) from public.quotations) into after_count;
    perform pg_temp.assert118(before_count=after_count,kind||'_rejection_has_no_partial_document');
  end loop;

  r:=public.commercial_create_quotation(base-'cliente');
  perform pg_temp.assert118(r->>'id' is not null,'anonymous_quote_wrapper_preserved');
  r:=public.commercial_create_document('cotacao',base||jsonb_build_object('cliente',U&'CLIENTE N\00c3O INFORMADO'));
  perform pg_temp.assert118(r->>'id' is not null,'anonymous_quote_generic_preserved');
  message:=null;
  begin perform public.commercial_create_document('pedido',base);
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert118(message='CLIENTE_DA_CARTEIRA_OBRIGATORIO','anonymous_order_denied');
  message:=null;
  begin perform public.commercial_create_document(null,own);
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert118(message='TIPO_DOCUMENTO_INVALIDO','null_type_denied');
  message:=null;
  begin perform public.commercial_create_document('pedido',null);
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert118(message='DADOS_DOCUMENTO_INVALIDOS','null_payload_denied');
end $$;
reset role;

set local role authenticated;
do $$ declare r jsonb; message text; target_id uuid; before_count bigint; begin
  r:=public.convert_quotation_to_order('40000000-0000-4000-8000-000000000001');
  perform pg_temp.assert118(exists(select 1 from public.orders where id=(r->>'id_pedido')::uuid
    and client_id='10000000-0000-4000-8000-000000000001'),'own_conversion_allowed');
  r:=public.convert_quotation_to_order('40000000-0000-4000-8000-000000000001');
  perform pg_temp.assert118((r->>'already_converted')::boolean,'conversion_idempotence_preserved');
  select count(*) into before_count from public.orders;
  foreach target_id in array array['40000000-0000-4000-8000-000000000002'::uuid,'40000000-0000-4000-8000-000000000005'::uuid] loop
    message:=null;
    begin perform public.convert_quotation_to_order(target_id);
    exception when others then message:=sqlerrm; end;
    perform pg_temp.assert118(message='CLIENTE_FORA_DA_CARTEIRA','legacy_foreign_or_conflicting_conversion_denied');
  end loop;
  message:=null;
  begin perform public.convert_quotation_to_order('40000000-0000-4000-8000-000000000003');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert118(message='SEM_PERMISSAO','foreign_quote_owner_denied');
  message:=null;
  begin perform public.convert_quotation_to_order('40000000-0000-4000-8000-000000000004');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert118(message='CLIENTE_DA_CARTEIRA_OBRIGATORIO','anonymous_conversion_denied');
  perform pg_temp.assert118((select count(*) from public.orders)=before_count,'failed_conversions_no_partial_orders');
end $$;
reset role;

update public.role_permissions set permitido=false where perfil='VENDEDOR' and modulo in ('novo_pedido','nova_cotacao');
set local role authenticated;
do $$ declare kind text; message text; begin
  foreach kind in array array['pedido','cotacao'] loop
    message:=null;
    begin perform public.commercial_create_document(kind,'{"cliente":"LAB ONLY","codigo_sap_cliente":"LAB-A"}');
    exception when others then message:=sqlerrm; end;
    perform pg_temp.assert118(message='SEM_PERMISSAO',kind||'_without_creation_permission_denied');
  end loop;
end $$;
reset role;
update public.role_permissions set permitido=true where perfil='VENDEDOR' and modulo in ('novo_pedido','nova_cotacao');

update public.clients set ativo=false where codigo_sap_cliente='LAB-A';
set local role authenticated;
do $$ declare message text; begin
  begin perform public.commercial_create_order('{"codigo_sap_cliente":"LAB-A"}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert118(message='CLIENTE_FORA_DA_CARTEIRA','inactive_client_denied');
end $$;
reset role;
update public.clients set ativo=true where codigo_sap_cliente='LAB-A';

-- An ADMIN with an active session keeps the previous cross-portfolio workflow.
update public.profiles set perfil='ADMIN' where id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ declare r jsonb; begin
  r:=public.commercial_create_order('{"cliente":"LAB ONLY","codigo_sap_cliente":"LAB-B","regiao":"PR","cliente_estado":"PR","items":[{"codigo":"LAB-PRODUCT","quantidade":1}]}');
  perform pg_temp.assert118(r->>'id' is not null,'admin_workflow_preserved');
  r:=public.convert_quotation_to_order('40000000-0000-4000-8000-000000000002');
  perform pg_temp.assert118(r->>'id_pedido' is not null,'admin_conversion_preserved');
end $$;
reset role;
update public.profiles set ativo=false where id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ declare message text; begin
  begin perform public.commercial_create_document('pedido','{"codigo_sap_cliente":"LAB-A"}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert118(message='SEM_PERMISSAO','inactive_actor_denied');
end $$;
reset role;
rollback;
