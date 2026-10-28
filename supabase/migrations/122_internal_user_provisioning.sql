begin;

-- A private operation journal seals cancellation before compensating Auth calls.
-- Passwords and tokens never enter this table or any RPC.
create table public.internal_user_provisioning (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null,
  actor_session_id uuid not null,
  target_user_id uuid,
  profile_data jsonb,
  status text not null default 'PREPARED' check(status in ('PREPARED','COMMITTED','CANCELLED')),
  cleanup_required boolean not null default false,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
alter table public.internal_user_provisioning enable row level security;
revoke all on public.internal_user_provisioning from public,anon,authenticated,service_role;

create function public.prepare_internal_user_provisioning(profile_data jsonb)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare actor public.profiles; login_name text; display_name text; email_text text; role_text text; operation_id uuid;
begin
  if not public.is_app_session_active() or not public.is_admin() then raise exception 'APENAS_ADMIN'; end if;
  select p.* into actor from public.profiles p where p.id=auth.uid() and p.ativo and p.perfil='ADMIN';
  if actor.id is null then raise exception 'APENAS_ADMIN'; end if;
  if jsonb_typeof(profile_data) is distinct from 'object' then raise exception 'DADOS_USUARIO_INVALIDOS'; end if;
  login_name:=lower(btrim(profile_data->>'usuario'));
  display_name:=btrim(profile_data->>'nome');
  email_text:=lower(btrim(profile_data->>'email'));
  role_text:=profile_data->>'perfil';
  if login_name is null or login_name !~ '^[a-z0-9._-]{1,80}$'
    or coalesce(length(display_name),0) not between 1 and 160
    or coalesce(length(email_text),0) not between 3 and 254 or email_text !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
    or role_text is null or role_text not in ('ADMIN','SUPERVISOR','VENDEDOR')
    or jsonb_typeof(profile_data->'ativo') is distinct from 'boolean' then raise exception 'DADOS_USUARIO_INVALIDOS'; end if;
  perform pg_advisory_xact_lock(hashtextextended('internal-user-provisioning',0));
  if exists(select 1 from public.profiles p where lower(p.usuario)=login_name) then raise exception 'USUARIO_DUPLICADO'; end if;
  if exists(select 1 from public.profiles p where lower(p.email)=email_text)
    or exists(select 1 from auth.users u where lower(u.email)=email_text) then raise exception 'EMAIL_DUPLICADO'; end if;
  if exists(select 1 from public.internal_user_provisioning o where o.status='PREPARED'
    and (o.profile_data->>'usuario'=login_name or o.profile_data->>'email'=email_text)) then
    raise exception 'CRIACAO_USUARIO_EM_ANDAMENTO';
  end if;
  insert into public.internal_user_provisioning(actor_id,actor_session_id,profile_data)
  values(actor.id,(auth.jwt()->>'session_id')::uuid,jsonb_build_object('usuario',login_name,'nome',display_name,
    'email',email_text,'perfil',role_text,'ativo',profile_data->'ativo')) returning id into operation_id;
  return operation_id;
end $$;

create function public.complete_internal_user_provisioning(operation_id uuid, target_user_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare op public.internal_user_provisioning; actor public.profiles; target record; result public.profiles;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'APENAS_SERVIDOR'; end if;
  perform pg_advisory_xact_lock(hashtextextended('internal-user-provisioning',0));
  select o.* into op from public.internal_user_provisioning o where o.id=operation_id for update;
  if op.id is null then raise exception 'OPERACAO_INVALIDA'; end if;
  if op.status='COMMITTED' and op.target_user_id=complete_internal_user_provisioning.target_user_id then
    select p.* into result from public.profiles p where p.id=op.target_user_id;
    return jsonb_build_object('id',result.id,'usuario',result.usuario,'nome',result.nome,'email',result.email,'perfil',result.perfil,'ativo',result.ativo);
  end if;
  if op.status<>'PREPARED' or op.created_at<now()-interval '10 minutes' then raise exception 'OPERACAO_ENCERRADA'; end if;
  select p.* into actor from public.profiles p where p.id=op.actor_id and p.ativo and p.perfil='ADMIN' for share;
  if actor.id is null then raise exception 'SESSAO_ADMIN_INVALIDA'; end if;
  perform 1 from public.app_sessions a join auth.sessions s on s.id=a.active_session_id and s.user_id=a.user_id
    where a.user_id=op.actor_id and a.active_session_id=op.actor_session_id and (s.not_after is null or s.not_after>now())
    for share of a,s;
  if not found then raise exception 'SESSAO_ADMIN_INVALIDA'; end if;
  select u.id,u.email,u.raw_app_meta_data into target from auth.users u
    where u.id=complete_internal_user_provisioning.target_user_id for share;
  if target.id is null or target.raw_app_meta_data->>'account_type' is distinct from 'internal'
    or target.raw_app_meta_data->>'provisioning_operation_id' is distinct from op.id::text
    or lower(target.email) is distinct from op.profile_data->>'email'
    or exists(select 1 from public.customer_portal_accounts a where a.user_id=target.id) then raise exception 'AUTH_USUARIO_DIVERGENTE'; end if;
  if exists(select 1 from public.profiles p where lower(p.usuario)=op.profile_data->>'usuario') then raise exception 'USUARIO_DUPLICADO'; end if;
  if exists(select 1 from public.profiles p where lower(p.email)=op.profile_data->>'email') then raise exception 'EMAIL_DUPLICADO'; end if;
  insert into public.profiles(id,usuario,nome,email,perfil,ativo)
  values(target.id,op.profile_data->>'usuario',op.profile_data->>'nome',op.profile_data->>'email',
    (op.profile_data->>'perfil')::public.user_profile,(op.profile_data->>'ativo')::boolean) returning * into result;
  insert into public.logs(user_id,usuario,acao,entidade,id_entidade,dados_novos)
  values(actor.id,actor.usuario,'CRIAR_USUARIO_INTERNO','profiles',target.id::text,
    jsonb_build_object('operation_id',op.id,'perfil',result.perfil,'ativo',result.ativo));
  update public.internal_user_provisioning set status='COMMITTED',target_user_id=target.id,profile_data=null,finished_at=now() where id=op.id;
  return jsonb_build_object('id',result.id,'usuario',result.usuario,'nome',result.nome,'email',result.email,'perfil',result.perfil,'ativo',result.ativo);
end $$;

create function public.cancel_internal_user_provisioning(operation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare op public.internal_user_provisioning; target_id uuid; result public.profiles;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'APENAS_SERVIDOR'; end if;
  select o.* into op from public.internal_user_provisioning o where o.id=operation_id for update;
  if op.id is null then raise exception 'OPERACAO_INVALIDA'; end if;
  if op.status='COMMITTED' then
    select p.* into result from public.profiles p where p.id=op.target_user_id;
    return jsonb_build_object('status','COMMITTED','profile',jsonb_build_object('id',result.id,'usuario',result.usuario,
      'nome',result.nome,'email',result.email,'perfil',result.perfil,'ativo',result.ativo));
  end if;
  -- Never select/delete by the supplied email alone. Only the exact server marker.
  select u.id into target_id from auth.users u
    where u.raw_app_meta_data->>'account_type'='internal'
      and u.raw_app_meta_data->>'provisioning_operation_id'=op.id::text;
  if target_id is not null and exists(select 1 from public.profiles p where p.id=target_id) then
    raise exception 'RECONCILIACAO_OBRIGATORIA';
  end if;
  update public.internal_user_provisioning set status='CANCELLED',target_user_id=target_id,
    profile_data=null,cleanup_required=true,finished_at=now() where id=op.id;
  return jsonb_build_object('status','CANCELLED','cleanup_user_id',target_id);
end $$;

create function public.finish_internal_user_cleanup(operation_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare op public.internal_user_provisioning;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'APENAS_SERVIDOR'; end if;
  select o.* into op from public.internal_user_provisioning o where o.id=operation_id for update;
  if op.id is null or op.status<>'CANCELLED' or op.target_user_id is null then raise exception 'RECONCILIACAO_OBRIGATORIA'; end if;
  if exists(select 1 from auth.users u where u.id=op.target_user_id) then raise exception 'LIMPEZA_AUTH_PENDENTE'; end if;
  update public.internal_user_provisioning set cleanup_required=false where id=op.id;
  insert into public.logs(user_id,usuario,acao,entidade,id_entidade,dados_novos)
  values(op.actor_id,(select usuario from public.profiles where id=op.actor_id),'CANCELAR_CRIACAO_USUARIO',
    'internal_user_provisioning',op.id::text,jsonb_build_object('cleanup_completed',true));
end $$;

revoke all on function public.prepare_internal_user_provisioning(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.prepare_internal_user_provisioning(jsonb) to authenticated;
revoke all on function public.complete_internal_user_provisioning(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.cancel_internal_user_provisioning(uuid) from public,anon,authenticated,service_role;
revoke all on function public.finish_internal_user_cleanup(uuid) from public,anon,authenticated,service_role;
grant execute on function public.complete_internal_user_provisioning(uuid,uuid) to service_role;
grant execute on function public.cancel_internal_user_provisioning(uuid) to service_role;
grant execute on function public.finish_internal_user_cleanup(uuid) to service_role;

-- Profile edits remain governed by existing RLS; new identities are server-only.
revoke insert on public.profiles from public,anon,authenticated;
do $$ declare cols text; begin
  select string_agg(format('%I',attname),',' order by attnum) into cols
    from pg_attribute where attrelid='public.profiles'::regclass and attnum>0 and not attisdropped;
  execute format('revoke insert (%s) on public.profiles from public,anon,authenticated',cols);
end $$;
commit;
