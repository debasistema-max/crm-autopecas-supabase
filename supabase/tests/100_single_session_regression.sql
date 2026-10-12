-- Caller wraps this file in BEGIN / ROLLBACK. No fixture is committed.
do $$
declare v_uid uuid; v_a uuid:=gen_random_uuid(); v_b uuid:=gen_random_uuid(); v_rejected boolean;
begin
  select id into v_uid from public.profiles where ativo and perfil='ADMIN' limit 1;
  if v_uid is null then raise exception 'FIXTURE_ADMIN_NECESSARIA'; end if;
  perform set_config('test.app_user',v_uid::text,true);
  perform set_config('test.app_a',v_a::text,true);
  perform set_config('test.app_b',v_b::text,true);
  insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
    values(v_a,v_uid,now()+interval '1 second',now(),now()+interval '1 hour');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','session_id',v_a)::text,true);
  perform public.claim_app_session();
  update public.app_session_policy set enforced=true where id;
  if not public.is_app_session_active() then raise exception 'PRIMEIRA_SESSAO_BLOQUEADA'; end if;
  insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
    values(v_b,v_uid,now()+interval '2 seconds',now(),now()+interval '1 hour');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','session_id',v_b)::text,true);
  perform public.claim_app_session();
  if not public.is_app_session_active() then raise exception 'SEGUNDA_SESSAO_BLOQUEADA'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','session_id',v_a)::text,true);
  if public.is_app_session_active() then raise exception 'SESSAO_ANTERIOR_CONTINUA_ATIVA'; end if;
  v_rejected:=false;
  begin perform public.claim_app_session(); exception when sqlstate 'PT401' then v_rejected:=true; end;
  if not v_rejected then raise exception 'SESSAO_ANTERIOR_RECLAMOU_CONTA'; end if;
  perform public.release_app_session();
  if (select active_session_id from public.app_sessions where user_id=v_uid)<>v_b then raise exception 'LOGOUT_ANTIGO_DERRUBOU_NOVO'; end if;
  perform set_config('request.path','/rpc/get_commercial_dashboard_summary',true);
  v_rejected:=false;
  begin perform public.check_app_session_request(); exception when sqlstate 'PT401' then v_rejected:=true; end;
  if not v_rejected then raise exception 'PRE_REQUEST_NAO_BLOQUEOU_RPC'; end if;
  perform set_config('request.path','/rpc/get_app_session_status',true);
  perform public.check_app_session_request();
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','session_id',v_b)::text,true);
  perform public.release_app_session();
  delete from auth.sessions where id=v_b; -- only the disposable fixture
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','session_id',v_a)::text,true);
  v_rejected:=false;
  begin perform public.claim_app_session(); exception when sqlstate 'PT401' then v_rejected:=true; end;
  if not v_rejected then raise exception 'SESSAO_ANTERIOR_RESSUSCITOU'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','session_id',gen_random_uuid())::text,true);
  if public.is_app_session_active() then raise exception 'SESSAO_FORJADA_PERMITIDA'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated')::text,true);
  if public.is_app_session_active() then raise exception 'JWT_SEM_SESSION_ID_PERMITIDO'; end if;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  if not public.is_app_session_active() then raise exception 'AGENDADOR_BLOQUEADO'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_uid,'role','authenticated','session_id',v_a)::text,true);
end; $$;

set local role authenticated;
do $$ begin
  if exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'RLS_PERMITIU_SESSAO_ANTERIOR'; end if;
end; $$;
reset role;

do $$ begin
  if has_function_privilege('anon','public.commercial_create_document(text,jsonb)','EXECUTE')
    or has_function_privilege('anon','public.b2b_create_document(text,jsonb)','EXECUTE')
    then raise exception 'RPC_COMERCIAL_ANONIMA'; end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='cadastros_clientes' and policyname='cadastros_clientes_crm_update')
    then raise exception 'POLICY_CADASTROS_AUSENTE'; end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='app_active_session_gate' and permissive='RESTRICTIVE')
    then raise exception 'STORAGE_SEM_PROTECAO'; end if;
end; $$;
select 'PASS: takeover, stale replay, release, RLS, API guard, invalid JWT, scheduler and grants' result;
