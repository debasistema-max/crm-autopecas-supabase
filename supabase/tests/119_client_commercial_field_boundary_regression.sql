-- Fictional authorization fixture only. Never run against production.
begin;
do $$ begin
  if current_setting('crm.test_disposable',true) is distinct from 'on' then
    raise exception 'DISPOSABLE_FIXTURE_REQUIRED';
  end if;
end $$;
create function pg_temp.assert119(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'REG119:%',label; end if; end $$;
select pg_temp.assert119(not has_table_privilege('authenticated','public.clients','select'),'no_table_select');
select pg_temp.assert119(has_column_privilege('authenticated','public.clients','nome','select'),'ordinary_column_select');
select pg_temp.assert119(not has_column_privilege('authenticated','public.clients','commercial_discount_percent','select'),'discount_column_denied');
select pg_temp.assert119(not has_function_privilege('anon','public.find_business_client_scoped(text,text)','execute'),'anonymous_lookup_denied');
select pg_temp.assert119(not has_function_privilege('anon','public.save_business_client_scoped(jsonb)','execute'),'anonymous_save_denied');
select pg_temp.assert119((select relrowsecurity from pg_class where oid='public.clients'::regclass),'rls_kept');

update public.clients set nome='LAB ONLY',cnpj=case codigo_sap_cliente
  when 'LAB-A' then '00000000000101' else '00000000000202' end;
insert into public.role_permissions values('SUPERVISOR','parceiros',true);
select set_config('lab.uid','00000000-0000-4000-8000-000000000001',true),
       set_config('lab.sid','20000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$ declare statement text; denied boolean; r jsonb; changed int; message text; begin
  perform pg_temp.assert119((select count(id) from public.clients)=1,'own_portfolio_only');
  perform pg_temp.assert119((select nome from public.clients limit 1)='LAB ONLY','ordinary_read_allowed');
  foreach statement in array array[
    'select commercial_discount_percent from public.clients',
    'select count(*) from public.clients where commercial_discount_percent>0',
    'select id from public.clients order by commercial_discount_percent',
    'select sum(commercial_discount_percent) from public.clients',
    'select to_jsonb(c) from public.clients c',
    'select * from public.clients'
  ] loop
    denied:=false;
    begin execute statement; exception when insufficient_privilege then denied:=true; end;
    perform pg_temp.assert119(denied,'direct_column_or_inference_denied');
  end loop;
  r:=public.find_business_client_scoped('codigo_sap_cliente','LAB-A');
  perform pg_temp.assert119(r->>'id'='10000000-0000-4000-8000-000000000001','own_lookup');
  perform pg_temp.assert119(not r ? 'commercial_discount_percent','lookup_has_no_secret_key');
  r:=public.find_business_client_scoped('cnpj','00.000.000/0001-01');
  perform pg_temp.assert119(r->>'id'='10000000-0000-4000-8000-000000000001','formatted_cnpj_lookup');
  perform pg_temp.assert119(public.find_business_client_scoped('codigo_sap_cliente','LAB-B') is null,'foreign_lookup_hidden');
  perform pg_temp.assert119(public.find_business_client_scoped('cnpj','00000000000202') is null,'foreign_cnpj_hidden');
  perform pg_temp.assert119(public.find_business_client_scoped('cnpj',' ') is null,'empty_lookup');
  message:=null;
  begin perform public.find_business_client_scoped('commercial_discount_percent','7.5');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='CAMPO_BUSCA_CLIENTE_INVALIDO','filter_allowlist');
  r:=public.list_business_clients_scoped('{}');
  perform pg_temp.assert119(jsonb_array_length(r)=1,'list_scope_preserved');
  perform pg_temp.assert119(r#>'{0,commercial_discount_percent}'='null'::jsonb,'list_discount_mask_preserved');
  update public.clients set commercial_discount_percent=0 where id='10000000-0000-4000-8000-000000000001';
  get diagnostics changed=row_count;
  perform pg_temp.assert119(changed=0,'seller_direct_write_denied');
  message:=null;
  begin perform public.save_business_client_scoped('{"nome":"LAB ONLY","perfil":"ADMIN","user_id":"00000000-0000-4000-8000-000000000002"}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='SEM_PERMISSAO','seller_rpc_write_denied');
end $$;
reset role;

select set_config('lab.sid','20000000-0000-4000-8000-000000000099',true);
set local role authenticated;
do $$ declare message text; begin
  begin perform public.find_business_client_scoped('codigo_sap_cliente','LAB-A');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='SEM_PERMISSAO','replaced_session_lookup_denied');
  message:=null;
  begin perform public.save_business_client_scoped('{"nome":"LAB ONLY"}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='SEM_PERMISSAO','replaced_session_save_denied');
end $$;
reset role;
select set_config('lab.sid','20000000-0000-4000-8000-000000000001',true);

update public.profiles set perfil='ADMIN' where id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ declare r jsonb; message text; begin
  r:=public.find_business_client_scoped('codigo_sap_cliente','LAB-B');
  perform pg_temp.assert119((r->>'commercial_discount_percent')::numeric=7.5,'admin_discount_lookup');
  r:=public.save_business_client_scoped('{"id":"50000000-0000-4000-8000-000000000001","nome":"LAB CREATED","codigo_sap_cliente":"LAB-NEW","commercial_discount_percent":5,"assigned_seller_id":"00000000-0000-4000-8000-000000000002"}');
  perform pg_temp.assert119((r->>'commercial_discount_percent')::numeric=5,'admin_create_discount');
  r:=public.save_business_client_scoped(r||'{"nome":"LAB UPDATED","commercial_discount_percent":6}');
  perform pg_temp.assert119(r->>'nome'='LAB UPDATED' and (r->>'commercial_discount_percent')::numeric=6,'admin_update_discount');
  message:=null;
  begin perform public.save_business_client_scoped('{"nome":"LAB BAD","commercial_discount_percent":11}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='DESCONTO_CLIENTE_INVALIDO','limit_kept');
  message:=null;
  begin perform public.save_business_client_scoped('{"nome":"LAB BAD","commercial_discount_percent":"NaN"}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='DESCONTO_CLIENTE_INVALIDO','nonfinite_denied');
end $$;
reset role;
select pg_temp.assert119((select count(*) from public.logs where acao='SALVAR_CLIENTE')=2,'two_server_audit_events');
select pg_temp.assert119((select dados_anteriores->>'commercial_discount_percent' from public.logs
  where acao='SALVAR_CLIENTE' and dados_novos->>'commercial_discount_percent'='6')='5','audit_before_after');
select pg_temp.assert119(not exists(select 1 from public.logs where dados_novos ? 'email' or dados_novos ? 'telefone'),'audit_no_contact_values');

-- An audit failure must abort the whole save rather than persist an unlogged edit.
create function pg_temp.reject119log() returns trigger language plpgsql as $$begin raise exception 'LAB_AUDIT_FAILURE'; end $$;
create trigger reject119log before insert on public.logs for each row execute function pg_temp.reject119log();
set local role authenticated;
do $$ declare message text; begin
  begin perform public.save_business_client_scoped('{"id":"50000000-0000-4000-8000-000000000001","nome":"MUST ROLLBACK","commercial_discount_percent":5}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='LAB_AUDIT_FAILURE','audit_failure_propagates');
end $$;
reset role;
select pg_temp.assert119((select nome from public.clients where id='50000000-0000-4000-8000-000000000001')='LAB UPDATED','audit_failure_rollback');
drop trigger reject119log on public.logs;

update public.profiles set perfil='SUPERVISOR' where id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ declare r jsonb; message text; begin
  r:=public.find_business_client_scoped('codigo_sap_cliente','LAB-B');
  perform pg_temp.assert119((r->>'commercial_discount_percent')::numeric=7.5,'authorized_staff_read_preserved');
  message:=null;
  begin perform public.save_business_client_scoped('{"id":"50000000-0000-4000-8000-000000000001","nome":"LAB ONLY","commercial_discount_percent":0}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='APENAS_ADMIN_ALTERA_DESCONTO_CLIENTE','staff_cannot_change_discount');
  r:=public.save_business_client_scoped('{"id":"50000000-0000-4000-8000-000000000001","nome":"LAB STAFF EDIT","commercial_discount_percent":6}');
  perform pg_temp.assert119(r->>'nome'='LAB STAFF EDIT','staff_can_save_other_fields');
end $$;
reset role;

update public.role_permissions set permitido=false where perfil='SUPERVISOR' and modulo='parceiros';
set local role authenticated;
do $$ declare message text; begin
  begin perform public.find_business_client_scoped('codigo_sap_cliente','LAB-A');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='SEM_PERMISSAO','staff_without_module_lookup_denied');
  message:=null;
  begin perform public.save_business_client_scoped('{"nome":"LAB ONLY"}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='SEM_PERMISSAO','staff_without_module_save_denied');
end $$;
reset role;

update public.profiles set perfil='ADMIN' where id='00000000-0000-4000-8000-000000000001';
update public.clients set assigned_seller_id='00000000-0000-4000-8000-000000000002'
  where id='50000000-0000-4000-8000-000000000001';
update public.profiles set ativo=false where id='00000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ declare r jsonb; message text; begin
  r:=public.save_business_client_scoped('{"id":"50000000-0000-4000-8000-000000000001","nome":"LAB LEGACY","commercial_discount_percent":6,"assigned_seller_id":"00000000-0000-4000-8000-000000000002"}');
  perform pg_temp.assert119(r->>'nome'='LAB LEGACY','unchanged_inactive_assignment_preserved');
  begin perform public.save_business_client_scoped('{"nome":"LAB NEW","assigned_seller_id":"00000000-0000-4000-8000-000000000002"}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='VENDEDOR_CLIENTE_INVALIDO','new_inactive_assignment_denied');
end $$;
reset role;

update public.profiles set ativo=false where id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ declare message text; begin
  perform pg_temp.assert119((select count(id) from public.clients)=0,'inactive_direct_read_denied');
  begin perform public.find_business_client_scoped('codigo_sap_cliente','LAB-A');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='SEM_PERMISSAO','inactive_lookup_denied');
  message:=null;
  begin perform public.save_business_client_scoped('{"nome":"LAB ONLY"}');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='SEM_PERMISSAO','inactive_save_denied');
end $$;
reset role;
select set_config('lab.uid','00000000-0000-4000-8000-000000000099',true);
set local role authenticated;
do $$ declare message text; begin
  begin perform public.find_business_client_scoped('codigo_sap_cliente','LAB-A');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert119(message='SEM_PERMISSAO','noninternal_denied');
end $$;
reset role;
rollback;
