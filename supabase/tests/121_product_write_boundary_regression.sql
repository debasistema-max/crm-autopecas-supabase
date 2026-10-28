-- Disposable fictional fixture only. Approval writer below tests the privilege
-- boundary; it is not a substitute for full SAP/import pipeline E2E validation.
begin;
do $$ begin
  if current_setting('crm.test_disposable',true) is distinct from 'on' then
    raise exception 'DISPOSABLE_FIXTURE_REQUIRED';
  end if;
end $$;
create function pg_temp.assert121(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'REG121:%',label; end if; end $$;
do $$ declare t text; begin
  foreach t in array array['products','product_sap_data','product_branch_prices','product_branch_stock','product_route_prices'] loop
    perform pg_temp.assert121(not has_table_privilege('authenticated','public.'||t,'insert'),'insert_denied');
    perform pg_temp.assert121(not has_any_column_privilege('authenticated','public.'||t,'insert'),'column_insert_denied');
    perform pg_temp.assert121(not has_table_privilege('authenticated','public.'||t,'update'),'update_denied');
    perform pg_temp.assert121(not has_any_column_privilege('authenticated','public.'||t,'update'),'column_update_denied');
    perform pg_temp.assert121(not has_table_privilege('authenticated','public.'||t,'delete'),'delete_denied');
    perform pg_temp.assert121(not has_table_privilege('authenticated','public.'||t,'truncate'),'truncate_denied');
    perform pg_temp.assert121(has_table_privilege('authenticated','public.'||t,'select'),'read_grant_preserved');
    perform pg_temp.assert121((select relrowsecurity from pg_class where oid=('public.'||t)::regclass),'rls_preserved');
  end loop;
end $$;
select pg_temp.assert121(not has_function_privilege('authenticated','public.import_products_transactional(jsonb)','execute'),'legacy_rpc_denied');
select pg_temp.assert121(not has_function_privilege('authenticated','public.commit_products_import_batch_v0_impl(uuid)','execute'),'delegate_denied');
select pg_temp.assert121(has_function_privilege('authenticated','public.commit_products_import_batch(uuid)','execute'),'supported_wrapper_kept');
select pg_temp.assert121(has_function_privilege('authenticated','public.set_product_active(text,boolean,boolean)','execute'),'activity_rpc_kept');

create table public.lab121_batches(id uuid primary key,owner_id uuid,status text);
insert into public.lab121_batches values
 ('70000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','DRAFT'),
 ('70000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','APPROVED');
revoke all on public.lab121_batches from public,anon,authenticated;
create function public.lab121_approved_writer(batch_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare b public.lab121_batches; t text;
begin
  if not public.is_app_session_active() or not public.can_approve_products_import() then
    raise exception 'LAB_APPROVAL_PERMISSION_REQUIRED';
  end if;
  select x.* into b from public.lab121_batches x where x.id=batch_id for update;
  if b.owner_id is distinct from auth.uid() then raise exception 'LAB_BATCH_DENIED'; end if;
  if b.status='COMMITTED' then return '{"already_committed":true}'::jsonb; end if;
  if b.status<>'APPROVED' then raise exception 'LAB_APPROVAL_REQUIRED'; end if;
  update public.products set preco_pr=140,preco_sp=140,ativo=true where codigo='LAB-PRODUCT';
  foreach t in array array['product_sap_data','product_branch_prices','product_branch_stock','product_route_prices'] loop
    execute format('update public.%I set amount=140 where product_code=$1',t) using 'LAB-PRODUCT';
  end loop;
  insert into public.logs(user_id,usuario,acao,entidade,id_entidade,dados_novos)
    select p.id,p.usuario,'LAB_APPROVED_IMPORT','lab121_batches',batch_id::text,'{"fixture":true}'::jsonb
      from public.profiles p where p.id=auth.uid();
  update public.lab121_batches set status='COMMITTED' where id=batch_id;
  return '{"already_committed":false}'::jsonb;
end $$;
revoke all on function public.lab121_approved_writer(uuid) from public,anon;
grant execute on function public.lab121_approved_writer(uuid) to authenticated;

select set_config('lab.uid','00000000-0000-4000-8000-000000000001',true),
 set_config('lab.sid','20000000-0000-4000-8000-000000000001',true);
-- Test both seller and ADMIN using the same browser database role.
do $$ declare perfil_value text; begin
  foreach perfil_value in array array['VENDEDOR','ADMIN'] loop
    update public.profiles set perfil=perfil_value where id=auth.uid();
    execute 'set local role authenticated';
    declare statement text; denied boolean; begin
      foreach statement in array array[
        'update public.products set preco_pr=1 where codigo=''LAB-PRODUCT''',
        'insert into public.products(codigo) values(''FORGED'')',
        'delete from public.products where codigo=''LAB-PRODUCT''',
        'update public.product_sap_data set amount=1',
        'update public.product_branch_prices set amount=1',
        'update public.product_branch_stock set amount=1',
        'update public.product_route_prices set amount=1',
        'select public.import_products_transactional(''{}''::jsonb)',
        'select public.commit_products_import_batch_v0_impl(''70000000-0000-4000-8000-000000000002''::uuid)'
      ] loop
        denied:=false;
        begin execute statement; exception when insufficient_privilege then denied:=true; end;
        perform pg_temp.assert121(denied,'browser_bypass_denied');
      end loop;
      perform pg_temp.assert121((select preco_pr from public.products where codigo='LAB-PRODUCT')=130,'ordinary_read_preserved');
    end;
    execute 'reset role';
  end loop;
end $$;

set local role authenticated;
do $$ declare message text; r jsonb; begin
  begin perform public.lab121_approved_writer('70000000-0000-4000-8000-000000000001');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert121(message='LAB_APPROVAL_REQUIRED','unapproved_batch_denied');
  r:=public.set_product_active('LAB-PRODUCT',false,true);
  perform pg_temp.assert121(r->>'ativo'='false','real_activity_rpc_still_works');
  r:=public.lab121_approved_writer('70000000-0000-4000-8000-000000000002');
  perform pg_temp.assert121(r->>'already_committed'='false','trusted_approved_writer_allowed');
  r:=public.lab121_approved_writer('70000000-0000-4000-8000-000000000002');
  perform pg_temp.assert121(r->>'already_committed'='true','fixture_idempotence');
end $$;
reset role;
select pg_temp.assert121((select preco_pr=140 and not ativo from public.products where codigo='LAB-PRODUCT'),'price_changed_but_inactive_override_preserved');
select pg_temp.assert121((select count(*) from public.logs where acao='LAB_APPROVED_IMPORT' and audit_source='SERVER')=1,'one_server_event');
do $$ declare t text; amount_value numeric; begin
  foreach t in array array['product_sap_data','product_branch_prices','product_branch_stock','product_route_prices'] loop
    execute format('select amount from public.%I where product_code=$1',t) into amount_value using 'LAB-PRODUCT';
    perform pg_temp.assert121(amount_value=140,'trusted_canonical_write');
  end loop;
end $$;

update public.profiles set perfil='SUPERVISOR' where id=auth.uid();
set local role authenticated;
do $$ declare message text; begin
  perform pg_temp.assert121(public.has_module('alimentacao'),'feeding_fixture_present');
  perform pg_temp.assert121(not public.can_approve_products_import(),'feeding_is_not_approval');
  begin perform public.lab121_approved_writer('70000000-0000-4000-8000-000000000001');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert121(message='LAB_APPROVAL_PERMISSION_REQUIRED','feeding_only_cannot_commit');
end $$;
reset role;

update public.profiles set perfil='ADMIN' where id=auth.uid();
update public.lab121_batches set status='APPROVED' where id='70000000-0000-4000-8000-000000000001';
update public.products set preco_pr=150 where codigo='LAB-PRODUCT';
create function pg_temp.reject121audit() returns trigger language plpgsql as $$begin raise exception 'LAB_AUDIT_FAILURE'; end $$;
create trigger lab121_reject before insert on public.logs for each row execute function pg_temp.reject121audit();
set local role authenticated;
do $$ declare message text; begin
  begin perform public.lab121_approved_writer('70000000-0000-4000-8000-000000000001');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert121(message='LAB_AUDIT_FAILURE','audit_failure_propagates');
end $$;
reset role;
select pg_temp.assert121((select preco_pr from public.products where codigo='LAB-PRODUCT')=150,'audit_failure_rolls_back_price');
select pg_temp.assert121((select status from public.lab121_batches where id='70000000-0000-4000-8000-000000000001')='APPROVED','audit_failure_rolls_back_batch');
rollback;
