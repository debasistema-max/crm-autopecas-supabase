-- Empty isolated schema only. No real credentials or users.
begin;
do $$ begin
  if current_setting('crm.test_disposable',true) is distinct from 'on' then raise exception 'DISPOSABLE_DATABASE_REQUIRED'; end if;
  if exists(select 1 from auth.users) then raise exception 'EMPTY_SCHEMA_REQUIRED'; end if;
end $$;
insert into auth.users(id,email) values
 ('00000000-0122-4000-8000-000000000001','admin122@example.invalid'),
 ('00000000-0122-4000-8000-000000000002','seller122@example.invalid');
insert into public.profiles(id,usuario,nome,email,perfil) values
 ('00000000-0122-4000-8000-000000000001','lab122admin','LAB ADMIN','admin122@example.invalid','ADMIN'),
 ('00000000-0122-4000-8000-000000000002','lab122seller','LAB SELLER','seller122@example.invalid','VENDEDOR');
insert into auth.sessions(id,user_id,created_at) values
 ('10000000-0122-4000-8000-000000000001','00000000-0122-4000-8000-000000000001',now()),
 ('10000000-0122-4000-8000-000000000002','00000000-0122-4000-8000-000000000002',now());
insert into public.app_session_policy(id,enforced) values(true,true);
insert into public.app_sessions(user_id,active_session_id,auth_created_at) select user_id,id,created_at from auth.sessions;
create temporary table lab122_operations(label text primary key,id uuid);
grant select,insert on lab122_operations to authenticated,service_role;

select set_config('request.jwt.claims','{"sub":"00000000-0122-4000-8000-000000000002","role":"authenticated","session_id":"10000000-0122-4000-8000-000000000002"}',true);
set local role authenticated;
do $$ begin
  begin perform public.prepare_internal_user_provisioning('{}'::jsonb); raise exception 'SELLER_CAN_PREPARE';
  exception when raise_exception then if sqlerrm<>'APENAS_ADMIN' then raise; end if; end;
  begin perform public.complete_internal_user_provisioning(gen_random_uuid(),gen_random_uuid()); raise exception 'BROWSER_CAN_COMPLETE';
  exception when insufficient_privilege then null; end;
  begin perform public.cancel_internal_user_provisioning(gen_random_uuid()); raise exception 'BROWSER_CAN_CANCEL';
  exception when insufficient_privilege then null; end;
  begin perform count(*) from public.internal_user_provisioning; raise exception 'BROWSER_CAN_READ_JOURNAL';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0122-4000-8000-000000000001","role":"authenticated","session_id":"10000000-0122-4000-8000-000000000001"}',true);
set local role authenticated;
do $$ declare op uuid; p jsonb; begin
  if has_table_privilege(current_user,'public.profiles','insert') or has_any_column_privilege(current_user,'public.profiles','insert') then
    raise exception 'ADMIN_BROWSER_CAN_INSERT_PROFILE';
  end if;
  p:='{"usuario":"LAB122NEW","nome":"LAB NEW","email":"new122@example.invalid","perfil":"VENDEDOR","ativo":true}'::jsonb;
  op:=public.prepare_internal_user_provisioning(p);
  insert into lab122_operations values('success',op);
  begin perform public.prepare_internal_user_provisioning(p); raise exception 'DUPLICATE_OPERATION_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'CRIACAO_USUARIO_EM_ANDAMENTO' then raise; end if; end;
  begin perform public.prepare_internal_user_provisioning(p||'{"usuario":"lab122admin"}'::jsonb); raise exception 'DUPLICATE_LOGIN_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'USUARIO_DUPLICADO' then raise; end if; end;
  begin perform public.prepare_internal_user_provisioning(p||'{"email":"ADMIN122@EXAMPLE.INVALID"}'::jsonb); raise exception 'DUPLICATE_EMAIL_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'EMAIL_DUPLICADO' then raise; end if; end;
  begin perform public.prepare_internal_user_provisioning(p||'{"perfil":"OWNER"}'::jsonb); raise exception 'UNKNOWN_ROLE_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'DADOS_USUARIO_INVALIDOS' then raise; end if; end;
end $$;
reset role;
-- Simulate only the Auth API's new user output; no password or credential.
insert into auth.users(id,email,raw_app_meta_data)
 select '00000000-0122-4000-8000-000000000003','new122@example.invalid',
 jsonb_build_object('account_type','internal','provisioning_operation_id',id) from lab122_operations where label='success';
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
do $$ declare op uuid; r jsonb; begin
  select id into op from lab122_operations where label='success';
  begin perform public.complete_internal_user_provisioning(op,'00000000-0122-4000-8000-000000000002'); raise exception 'EXISTING_IDENTITY_REUSED';
  exception when raise_exception then if sqlerrm<>'AUTH_USUARIO_DIVERGENTE' then raise; end if; end;
  r:=public.complete_internal_user_provisioning(op,'00000000-0122-4000-8000-000000000003');
  if r->>'usuario'<>'lab122new' or r->>'perfil'<>'VENDEDOR' then raise exception 'SERVER_PROFILE_CREATION_FAILED'; end if;
  perform public.complete_internal_user_provisioning(op,'00000000-0122-4000-8000-000000000003');
  r:=public.cancel_internal_user_provisioning(op);
  if r->>'status'<>'COMMITTED' or r#>>'{profile,id}'<>'00000000-0122-4000-8000-000000000003'
    or r ? 'cleanup_user_id' then raise exception 'COMMITTED_ACCOUNT_CLEANUP_ALLOWED'; end if;
end $$;
reset role;
do $$ declare op uuid; begin
  select id into op from lab122_operations where label='success';
  if not exists(select 1 from public.internal_user_provisioning where id=op and status='COMMITTED' and profile_data is null)
    or (select count(*) from public.logs where acao='CRIAR_USUARIO_INTERNO' and id_entidade='00000000-0122-4000-8000-000000000003'
      and user_id='00000000-0122-4000-8000-000000000001' and audit_source='SERVER')<>1 then raise exception 'AUTHORITATIVE_AUDIT_OR_PII_CLEAR_FAILED'; end if;
end $$;

select set_config('request.jwt.claims','{"sub":"00000000-0122-4000-8000-000000000001","role":"authenticated","session_id":"10000000-0122-4000-8000-000000000001"}',true);
set local role authenticated;
insert into lab122_operations values('cancel',public.prepare_internal_user_provisioning(
 '{"usuario":"lab122cancel","nome":"LAB CANCEL","email":"cancel122@example.invalid","perfil":"SUPERVISOR","ativo":true}'));
insert into lab122_operations values('atomic',public.prepare_internal_user_provisioning(
 '{"usuario":"lab122atomic","nome":"LAB ATOMIC","email":"atomic122@example.invalid","perfil":"VENDEDOR","ativo":true}'));
reset role;
insert into auth.users(id,email,raw_app_meta_data)
 select case label when 'cancel' then '00000000-0122-4000-8000-000000000004'::uuid else '00000000-0122-4000-8000-000000000005'::uuid end,
 case label when 'cancel' then 'cancel122@example.invalid' else 'atomic122@example.invalid' end,
 jsonb_build_object('account_type','internal','provisioning_operation_id',id)
 from lab122_operations where label in ('cancel','atomic');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
do $$ declare op uuid; r jsonb; begin
  select id into op from lab122_operations where label='cancel';
  r:=public.cancel_internal_user_provisioning(op);
  if r->>'cleanup_user_id'<>'00000000-0122-4000-8000-000000000004' then raise exception 'CLEANUP_ID_NOT_MARKED_NEW_ACCOUNT'; end if;
  begin perform public.complete_internal_user_provisioning(op,'00000000-0122-4000-8000-000000000004'); raise exception 'LATE_COMPLETION_AFTER_CANCEL';
  exception when raise_exception then if sqlerrm<>'OPERACAO_ENCERRADA' then raise; end if; end;
  begin perform public.finish_internal_user_cleanup(op); raise exception 'UNDELETED_AUTH_MARKED_CLEAN';
  exception when raise_exception then if sqlerrm<>'LIMPEZA_AUTH_PENDENTE' then raise; end if; end;
end $$;
reset role;
delete from auth.users where id='00000000-0122-4000-8000-000000000004';
set local role service_role;
select public.finish_internal_user_cleanup((select id from lab122_operations where label='cancel'));
reset role;

-- A failed server audit must roll back the profile and journal status together.
create function pg_temp.lab122_fail_audit() returns trigger language plpgsql as $$ begin
 if new.acao='CRIAR_USUARIO_INTERNO' then raise exception 'LAB122_AUDIT_UNAVAILABLE'; end if;
 return new;
end $$;
create trigger lab122_fail_audit before insert on public.logs for each row execute function pg_temp.lab122_fail_audit();
set local role service_role;
do $$ begin
  begin perform public.complete_internal_user_provisioning((select id from lab122_operations where label='atomic'),
    '00000000-0122-4000-8000-000000000005'); raise exception 'FAILED_AUDIT_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'LAB122_AUDIT_UNAVAILABLE' then raise; end if; end;
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.profiles where id='00000000-0122-4000-8000-000000000005')
   or (select status from public.internal_user_provisioning where id=(select id from lab122_operations where label='atomic'))<>'PREPARED' then
   raise exception 'PROFILE_JOURNAL_ATOMICITY_FAILED';
 end if;
 if exists(select 1 from public.internal_user_provisioning where id=(select id from lab122_operations where label='cancel') and cleanup_required) then
   raise exception 'CLEANUP_RECONCILIATION_FAILED';
 end if;
end $$;
update public.app_sessions set active_session_id=null where user_id='00000000-0122-4000-8000-000000000001';
set local role service_role;
do $$ begin
  begin perform public.complete_internal_user_provisioning((select id from lab122_operations where label='atomic'),
    '00000000-0122-4000-8000-000000000005'); raise exception 'STALE_ADMIN_SESSION_COMPLETED_PROVISIONING';
  exception when raise_exception then if sqlerrm<>'SESSAO_ADMIN_INVALIDA' then raise; end if; end;
end $$;
reset role;
update public.app_sessions set active_session_id='10000000-0122-4000-8000-000000000001'
 where user_id='00000000-0122-4000-8000-000000000001';
update public.profiles set ativo=false where id='00000000-0122-4000-8000-000000000001';
set local role service_role;
do $$ begin
  begin perform public.complete_internal_user_provisioning((select id from lab122_operations where label='atomic'),
    '00000000-0122-4000-8000-000000000005'); raise exception 'INACTIVE_ADMIN_COMPLETED_PROVISIONING';
  exception when raise_exception then if sqlerrm<>'SESSAO_ADMIN_INVALIDA' then raise; end if; end;
end $$;
reset role;
select jsonb_build_object('status','PASS_INTERNAL_USER_PROVISIONING_122','fictional_data_only',true,
 'checks',jsonb_build_array('ADMIN prepare','seller denied','direct profile insert denied','service-only finalizers',
 'duplicate reservations/login/email','existing identity not reused','Auth operation marker binding','atomic profile audit',
 'repeated completion idempotent','committed identity never cleaned','cancel seals late completion','cleanup confirmed only after Auth deletion','inactive ADMIN rechecked at completion'));
rollback;
