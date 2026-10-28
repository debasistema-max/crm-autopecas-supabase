begin;

-- Existing browser-written records cannot be retroactively certified.
alter table public.logs add column audit_source text not null default 'LEGACY_UNVERIFIED'
  check(audit_source in ('LEGACY_UNVERIFIED','SERVER'));
revoke insert,update,delete on public.logs from public,anon,authenticated;
do $$ declare columns_sql text; begin
  select string_agg(format('%I',attname),',' order by attnum) into columns_sql
    from pg_attribute where attrelid='public.logs'::regclass and attnum>0 and not attisdropped;
  execute format('revoke insert (%s), update (%s) on public.logs from public,anon,authenticated',columns_sql,columns_sql);
end $$;
drop policy if exists logs_insert on public.logs;

-- INVOKER is intentional: inspect the actual writer, including a trusted
-- SECURITY DEFINER caller, rather than turning every caller into the owner.
create function public.stamp_server_audit_origin()
returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
  if current_user not in ('postgres','supabase_admin','service_role') then
    raise exception 'AUDITORIA_EXCLUSIVA_SERVIDOR';
  end if;
  new.audit_source:='SERVER';
  new.data_hora:=clock_timestamp();
  return new;
end;
$$;
revoke all on function public.stamp_server_audit_origin() from public,anon,authenticated;
create trigger logs_server_origin before insert on public.logs
  for each row execute function public.stamp_server_audit_origin();

-- Browser-managed entities get their audit in the same transaction as the
-- real mutation. Only field names are retained, never password/contact values.
create function public.audit_crm_record_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  before_row jsonb; after_row jsonb; changed_fields jsonb; action_name text;
  safe_before jsonb; safe_after jsonb;
  actor_id uuid; actor_name text; record_key text;
begin
  before_row:=case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;
  after_row:=case when tg_op='DELETE' then '{}'::jsonb else to_jsonb(new) end;
  select coalesce(jsonb_agg(k order by k),'[]'::jsonb) into changed_fields
    from (select jsonb_object_keys(before_row||after_row) k) fields
    where k not in ('created_at','updated_at','ultimo_login')
      and before_row->k is distinct from after_row->k;
  if changed_fields='[]'::jsonb then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  action_name:=case tg_table_name
    when 'profiles' then 'SALVAR_USUARIO'
    when 'carriers' then 'SALVAR_TRANSPORTADORA'
    when 'cadastros_clientes' then case when tg_op='INSERT' then 'CRIAR_CADASTRO_CLIENTE' else 'ATUALIZAR_CADASTRO_CLIENTE' end
    when 'company_settings' then 'ATUALIZAR_CONFIG_EMPRESA'
    when 'settings' then case when coalesce(after_row->>'key',before_row->>'key')='portal_cadastros'
      then 'ATUALIZAR_CONFIG_PORTAL_CADASTROS' else 'ALTERAR_CONFIGURACAO' end
    else null end;
  if action_name is null then raise exception 'TABELA_AUDITORIA_INVALIDA'; end if;
  if tg_op='DELETE' then action_name:='EXCLUIR_'||upper(tg_table_name); end if;
  select coalesce(jsonb_object_agg(k,before_row->k),'{}'::jsonb) into safe_before
    from jsonb_object_keys(before_row) k where k in ('perfil','ativo','status');
  select coalesce(jsonb_object_agg(k,after_row->k),'{}'::jsonb) into safe_after
    from jsonb_object_keys(after_row) k where k in ('perfil','ativo','status');
  select p.id,p.usuario into actor_id,actor_name from public.profiles p where p.id=auth.uid();
  record_key:=coalesce(after_row->>'id',before_row->>'id',after_row->>'key',before_row->>'key');
  insert into public.logs(user_id,usuario,acao,entidade,id_entidade,dados_anteriores,dados_novos)
  values(actor_id,coalesce(actor_name,'BACKEND'),action_name,tg_table_name,record_key,
    jsonb_build_object('safe_fields',safe_before),
    jsonb_build_object('operation',tg_op,'changed_fields',changed_fields,'actor_auth_user_id',auth.uid(),'safe_fields',safe_after));
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.audit_crm_record_mutation() from public,anon,authenticated;
do $$ declare table_name text; begin
  foreach table_name in array array['profiles','carriers','cadastros_clientes','company_settings','settings'] loop
    execute format('create trigger server_record_audit after insert or update or delete on public.%I for each row execute function public.audit_crm_record_mutation()',table_name);
  end loop;
end $$;

-- Audit a winning application-session transition, not a claimed browser event.
-- Repeated claims/polls do not create extra LOGIN; stale logout changes no row.
create function public.audit_app_session_transition()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare previous_id uuid; actor_id uuid; actor_name text; event_name text;
begin
  if tg_op='UPDATE' then previous_id:=old.active_session_id; end if;
  if new.active_session_id is not distinct from previous_id then return new; end if;
  event_name:=case when new.active_session_id is null then 'LOGOUT' else 'LOGIN' end;
  select p.id,p.usuario into actor_id,actor_name from public.profiles p where p.id=new.user_id;
  insert into public.logs(user_id,usuario,acao,entidade,id_entidade,dados_novos)
  values(actor_id,coalesce(actor_name,'B2B'),event_name,'app_sessions',new.user_id::text,
    jsonb_build_object('session_transition',true));
  return new;
end;
$$;
revoke all on function public.audit_app_session_transition() from public,anon,authenticated;
create trigger app_sessions_server_audit after insert or update on public.app_sessions
  for each row execute function public.audit_app_session_transition();

comment on column public.logs.audit_source is
  'SERVER means emitted by trusted database/server code; legacy rows are not retroactively verified.';
commit;
