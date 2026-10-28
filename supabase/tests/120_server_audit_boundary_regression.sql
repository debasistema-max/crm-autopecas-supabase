-- Disposable fictional authorization fixture only. No real users or data.
begin;
do $$ begin
  if current_setting('crm.test_disposable',true) is distinct from 'on' then
    raise exception 'DISPOSABLE_FIXTURE_REQUIRED';
  end if;
end $$;
create function pg_temp.assert120(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'REG120:%',label; end if; end $$;
select pg_temp.assert120(not has_table_privilege('authenticated','public.logs','insert'),'browser_insert_denied');
select pg_temp.assert120(not has_any_column_privilege('authenticated','public.logs','insert'),'browser_column_insert_denied');
select pg_temp.assert120(not has_table_privilege('authenticated','public.logs','update'),'browser_update_denied');
select pg_temp.assert120(not has_table_privilege('authenticated','public.logs','delete'),'browser_delete_denied');
select pg_temp.assert120((select audit_source from public.logs where acao='LAB_OLD')='LEGACY_UNVERIFIED','legacy_not_certified');
select pg_temp.assert120(not has_function_privilege('authenticated','public.audit_crm_record_mutation()','execute'),'trigger_not_rpc');

select set_config('lab.uid','00000000-0000-4000-8000-000000000001',true),
  set_config('lab.sid','20000000-0000-4000-8000-000000000001',true);
update public.profiles set perfil='ADMIN' where id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
update public.profiles set ultimo_login=now() where id=auth.uid();
do $$ declare denied boolean; begin
  denied:=false;
  begin insert into public.logs(user_id,usuario,acao,audit_source)
    values(auth.uid(),'FAKE ADMIN','CANCELAR_PEDIDO','SERVER');
  exception when insufficient_privilege then denied:=true; end;
  perform pg_temp.assert120(denied,'forged_critical_event_denied_even_admin_browser');
  denied:=false;
  begin update public.logs set acao='FORGED'; exception when insufficient_privilege then denied:=true; end;
  perform pg_temp.assert120(denied,'rewrite_denied');
  denied:=false;
  begin delete from public.logs; exception when insufficient_privilege then denied:=true; end;
  perform pg_temp.assert120(denied,'delete_denied');
end $$;
reset role;
select pg_temp.assert120((select count(*) from public.logs where acao='SALVAR_USUARIO')=1,'timestamp_only_profile_update_not_a_change');
select pg_temp.assert120((select dados_anteriores#>>'{safe_fields,perfil}' from public.logs where acao='SALVAR_USUARIO')='VENDEDOR','profile_old_role');
select pg_temp.assert120((select dados_novos#>>'{safe_fields,perfil}' from public.logs where acao='SALVAR_USUARIO')='ADMIN','profile_new_role');

-- Defense in depth even if somebody accidentally restores an INSERT grant/policy.
grant insert on public.logs to authenticated;
create policy lab120_insert on public.logs for insert to authenticated with check(true);
set local role authenticated;
do $$ declare message text; begin
  begin insert into public.logs(acao,audit_source) values('FORGED','SERVER');
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert120(message='AUDITORIA_EXCLUSIVA_SERVIDOR','invoker_stamp_rejects_direct_writer');
end $$;
reset role;
drop policy lab120_insert on public.logs;
revoke insert on public.logs from authenticated;

set local role authenticated;
insert into public.carriers(id,nome,email) values('60000000-0000-4000-8000-000000000001','LAB ONLY','contact@example.invalid');
update public.carriers set telefone='fictional-contact' where id='60000000-0000-4000-8000-000000000001';
insert into public.settings(key,value) values('portal_cadastros','{"email":"private@example.invalid","password":"fictional-sensitive-value"}');
insert into public.company_settings(id,company_name,cnpj) values(true,'LAB ONLY','fictional-document');
select public.save_business_client_scoped('{"nome":"LAB ONLY","codigo_sap_cliente":"LAB-CLIENT-120"}') is not null;
reset role;
-- Public registrations are inserted by the trusted backend, not browser DML.
insert into public.cadastros_clientes(id,razao_social,status) values('60000000-0000-4000-8000-000000000002','LAB ONLY','Pendente');
select pg_temp.assert120((select count(*) from public.logs where acao='SALVAR_TRANSPORTADORA')=2,'one_event_per_actual_carrier_write');
select pg_temp.assert120(not exists(select 1 from public.logs where acao='SALVAR_TRANSPORTADORA'
  and (user_id is distinct from '00000000-0000-4000-8000-000000000001'::uuid or usuario<>'seller_a' or audit_source<>'SERVER')),'actor_and_source_derived');
select pg_temp.assert120(not exists(select 1 from public.logs where audit_source='SERVER'
  and dados_novos::text like '%@example.invalid%'),'no_contact_values');
select pg_temp.assert120(not exists(select 1 from public.logs where dados_novos::text like '%fictional-sensitive-value%'),'no_password_values');
select pg_temp.assert120((select count(*) from public.logs where acao='SALVAR_CLIENTE' and audit_source='SERVER')=1,'rpc_client_audit_preserved');

-- A failed audit must roll back the underlying profile/carrier mutation.
create function pg_temp.reject120() returns trigger language plpgsql as $$begin raise exception 'LAB_AUDIT_FAILURE'; end $$;
create trigger lab120_reject before insert on public.logs for each row execute function pg_temp.reject120();
set local role authenticated;
do $$ declare message text; begin
  begin update public.carriers set nome='MUST ROLLBACK' where id='60000000-0000-4000-8000-000000000001';
  exception when others then message:=sqlerrm; end;
  perform pg_temp.assert120(message='LAB_AUDIT_FAILURE','audit_failure_propagates');
end $$;
reset role;
select pg_temp.assert120((select nome from public.carriers where id='60000000-0000-4000-8000-000000000001')='LAB ONLY','mutation_rolled_back');
drop trigger lab120_reject on public.logs;

set local role authenticated;
delete from public.carriers where id='60000000-0000-4000-8000-000000000001';
reset role;
select pg_temp.assert120((select count(*) from public.logs where acao='EXCLUIR_CARRIERS' and audit_source='SERVER')=1,'actual_delete_audited');

set local role service_role;
insert into public.logs(acao,usuario,audit_source,data_hora) values('LAB_BACKEND_EVENT','LAB BACKEND','LEGACY_UNVERIFIED','1970-01-01');
reset role;
select pg_temp.assert120((select audit_source='SERVER' and data_hora>now()-interval '1 minute' from public.logs where acao='LAB_BACKEND_EVENT'),'trusted_backend_origin_and_time_stamped');

insert into auth.sessions(id,user_id,created_at) values('20000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001',now()+interval '1 minute');
select set_config('lab.sid','20000000-0000-4000-8000-000000000004',true);
set local role authenticated;
select public.claim_app_session();
select public.claim_app_session();
reset role;
select pg_temp.assert120((select count(*) from public.logs where acao='LOGIN')=1,'single_login_for_new_winner');
select pg_temp.assert120((select count(*) from public.logs where acao='SUBSTITUIR_SESSAO')=1,'replacement_audit_kept');
select set_config('lab.sid','20000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$ declare message text; begin
  begin perform public.claim_app_session(); exception when others then message:=sqlerrm; end;
  perform pg_temp.assert120(message='SESSAO_SUBSTITUIDA','stale_claim_denied');
  perform public.release_app_session();
end $$;
reset role;
select pg_temp.assert120((select count(*) from public.logs where acao='LOGOUT')=0,'stale_logout_cannot_forge_exit');
select set_config('lab.sid','20000000-0000-4000-8000-000000000004',true);
set local role authenticated;
select public.release_app_session();
select public.release_app_session();
reset role;
select pg_temp.assert120((select count(*) from public.logs where acao='LOGOUT')=1,'single_real_logout');

-- Audit failure also rolls back a claimed winner, without changing claim logic.
insert into auth.sessions(id,user_id,created_at) values('20000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000001',now()+interval '2 minutes');
select set_config('lab.sid','20000000-0000-4000-8000-000000000005',true);
create trigger lab120_reject before insert on public.logs for each row execute function pg_temp.reject120();
set local role authenticated;
do $$ declare message text; begin
  begin perform public.claim_app_session(); exception when others then message:=sqlerrm; end;
  perform pg_temp.assert120(message='LAB_AUDIT_FAILURE','claim_audit_failure_propagates');
end $$;
reset role;
select pg_temp.assert120((select active_session_id is null from public.app_sessions where user_id='00000000-0000-4000-8000-000000000001'),'failed_claim_did_not_change_winner');
drop trigger lab120_reject on public.logs;

-- Customer sessions have an Auth identity but no internal profiles FK row.
insert into auth.sessions(id,user_id) values('20000000-0000-4000-8000-000000000009','00000000-0000-4000-8000-000000000009');
insert into public.customer_portal_accounts(user_id,client_id,active,activation_pending)
 values('00000000-0000-4000-8000-000000000009','10000000-0000-4000-8000-000000000001',true,false);
select set_config('lab.uid','00000000-0000-4000-8000-000000000009',true),
  set_config('lab.sid','20000000-0000-4000-8000-000000000009',true);
set local role authenticated;
select public.claim_app_session();
select public.release_app_session();
reset role;
select pg_temp.assert120((select count(*) from public.logs where acao in ('LOGIN','LOGOUT')
  and id_entidade='00000000-0000-4000-8000-000000000009' and user_id is null and usuario='B2B' and audit_source='SERVER')=2,'b2b_session_fk_compatible');
select pg_temp.assert120((select audit_source from public.logs where acao='LAB_OLD')='LEGACY_UNVERIFIED','history_preserved');
select pg_temp.assert120(not exists(select 1 from public.logs where acao='FORGED' or acao='CANCELAR_PEDIDO'),'no_fabricated_events');
rollback;
