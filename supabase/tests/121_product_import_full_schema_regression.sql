-- Run only against an empty, disposable restoration of the real schema.
begin;
do $$ begin
  if current_setting('crm.test_disposable',true) is distinct from 'on' then
    raise exception 'DISPOSABLE_DATABASE_REQUIRED';
  end if;
  if exists(select 1 from auth.users) or exists(select 1 from public.products)
    or exists(select 1 from public.products_import_batches) then
    raise exception 'EMPTY_SCHEMA_REQUIRED';
  end if;
end $$;

insert into auth.users(id,email) values
 ('00000000-0121-4000-8000-000000000001','admin121@example.invalid'),
 ('00000000-0121-4000-8000-000000000002','feed121@example.invalid'),
 ('00000000-0121-4000-8000-000000000003','seller121@example.invalid');
insert into public.profiles(id,usuario,nome,email,perfil) values
 ('00000000-0121-4000-8000-000000000001','lab121admin','LAB ADMIN','admin121@example.invalid','ADMIN'),
 ('00000000-0121-4000-8000-000000000002','lab121feed','LAB FEED','feed121@example.invalid','SUPERVISOR'),
 ('00000000-0121-4000-8000-000000000003','lab121seller','LAB SELLER','seller121@example.invalid','VENDEDOR');
insert into public.role_permissions(perfil,modulo,permitido) values
 ('SUPERVISOR','alimentacao',true),('VENDEDOR','produtos',true);
insert into auth.sessions(id,user_id,created_at) values
 ('10000000-0121-4000-8000-000000000001','00000000-0121-4000-8000-000000000001',now()),
 ('10000000-0121-4000-8000-000000000002','00000000-0121-4000-8000-000000000002',now()),
 ('10000000-0121-4000-8000-000000000003','00000000-0121-4000-8000-000000000003',now());
insert into public.app_session_policy(id,enforced) values(true,true);
insert into public.app_sessions(user_id,active_session_id,auth_created_at)
 select user_id,id,created_at from auth.sessions;
insert into public.branches(code,name,state,city,is_headquarters) values
 ('PR','LAB MATRIZ','PR','LAB PR',true),('SP','LAB FILIAL','SP','LAB SP',false);
insert into public.products(codigo,descricao,preco_pr,preco_sp,estoque_quantidade,ano,ncm)
 values('9900000121','LAB EXISTING PRODUCT',100,110,7,'LAB YEAR','87089990');
create temporary table lab121_batches(label text primary key,id uuid);
grant select,insert on lab121_batches to authenticated;

select set_config('request.jwt.claims','{"sub":"00000000-0121-4000-8000-000000000001","role":"authenticated","session_id":"10000000-0121-4000-8000-000000000001"}',true);
set local role authenticated;
do $$ declare r jsonb; b uuid; count_before bigint; begin
  if not public.is_app_session_active() or not public.can_approve_products_import() then
    raise exception 'ADMIN_SESSION_FIXTURE_INVALID';
  end if;
  perform public.set_product_active('9900000121',false,true);
  r:=public.create_products_import_batch('{"import_type":"PRECO_PR","region":"PR","source_name":"LAB ONLY","file_hash":"lab121-valid","products":[{"codigo":"9900000121","preco_pr":90},{"codigo":"9900000122","descricao":"LAB NEW PRODUCT","preco_pr":50}]}'::jsonb);
  b:=(r->>'batch_id')::uuid;
  insert into lab121_batches values('valid',b);
  if b is null or r->>'status'<>'validated' or (r#>>'{summary,errorCount}')::int<>0 then
    raise exception 'REAL_CREATE_VALIDATION_FAILED';
  end if;
  r:=public.preview_products_import_batch(b);
  if (r#>>'{summary,newCount}')::int<>1 or (r#>>'{summary,updatedCount}')::int<>1 then
    raise exception 'REAL_PREVIEW_COUNTS_FAILED';
  end if;
  if (select preco_pr from public.products where codigo='9900000121')<>100
    or exists(select 1 from public.products where codigo='9900000122') then
    raise exception 'PREVIEW_CHANGED_DEFINITIVE_DATA';
  end if;
  r:=public.approve_products_import_batch(b);
  if r->>'status'<>'approved' then raise exception 'REAL_APPROVAL_FAILED'; end if;
  r:=public.commit_products_import_batch(b);
  if r->>'status'<>'imported' then raise exception 'REAL_COMMIT_FAILED'; end if;
  if not exists(select 1 from public.products where codigo='9900000121' and preco_pr=90
    and preco_sp=110 and ano='LAB YEAR' and ncm='87089990' and not ativo)
    or not exists(select 1 from public.products where codigo='9900000122' and preco_pr=50) then
    raise exception 'REAL_COMMIT_VALUES_OR_PRESERVATION_FAILED';
  end if;
  if not exists(select 1 from public.products_import_audit where batch_id=b
    and codigo='9900000121' and field_name='preco_pr' and old_value='100'::jsonb and new_value='90'::jsonb) then
    raise exception 'REAL_FIELD_AUDIT_FAILED';
  end if;
  if not exists(select 1 from public.logs where id_entidade=b::text
    and acao='IMPORTAR_PRODUTOS' and audit_source='SERVER') then
    raise exception 'REAL_SERVER_AUDIT_FAILED';
  end if;
  select count(*) into count_before from public.products_import_audit where batch_id=b;
  begin
    perform public.commit_products_import_batch(b);
    raise exception 'REPEATED_COMMIT_ACCEPTED';
  exception when raise_exception then
    if sqlerrm<>'LOTE_JA_IMPORTADO' then raise; end if;
  end;
  if (select count(*) from public.products_import_audit where batch_id=b)<>count_before then
    raise exception 'REPEATED_COMMIT_DUPLICATED_AUDIT';
  end if;
  begin
    perform public.create_products_import_batch('{"import_type":"PRECO_PR","region":"PR","file_hash":"lab121-valid","products":[{"codigo":"9900000121","preco_pr":90}]}'::jsonb);
    raise exception 'REPEATED_FILE_ACCEPTED';
  exception when raise_exception then
    if sqlerrm<>'ARQUIVO_JA_IMPORTADO' then raise; end if;
  end;
  raise notice 'PASS: real ADMIN create/preview/approve/commit, preservation, audit and replay protection';
end $$;
reset role;

-- Blocking errors must stop the real approval and commit wrappers.
set local role authenticated;
do $$ declare item jsonb; r jsonb; b uuid; begin
  for item in select value from jsonb_array_elements('[
    {"codigo":"","preco_pr":1},
    {"codigo":"9900000121","preco_pr":0},
    {"codigo":"9900000121","preco_pr":-1},
    {"codigo":"9900000121","preco_pr":90,"estoque_quantidade":-1}
  ]'::jsonb) loop
    r:=public.create_products_import_batch(jsonb_build_object('import_type','PRECO_PR','region','PR','products',jsonb_build_array(item)));
    b:=(r->>'batch_id')::uuid;
    if r->>'status'<>'failed' or (r#>>'{summary,errorCount}')::int<1 then
      raise exception 'CRITICAL_ERROR_NOT_REPORTED';
    end if;
    begin perform public.approve_products_import_batch(b); raise exception 'INVALID_APPROVAL_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'IMPORTACAO_BLOQUEADA_COM_ERROS' then raise; end if; end;
    begin perform public.commit_products_import_batch(b); raise exception 'INVALID_COMMIT_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'IMPORTACAO_BLOQUEADA_COM_ERROS' then raise; end if; end;
  end loop;
  r:=public.create_products_import_batch('{"import_type":"PRECO_PR","region":"PR","products":[{"codigo":"9900000121","preco_pr":90},{"codigo":"9900000121","preco_pr":90}]}'::jsonb);
  if (r#>>'{summary,errorCount}')::int<>2 then raise exception 'DUPLICATES_NOT_BLOCKED'; end if;
  r:=public.create_products_import_batch('{"import_type":"CADASTRO_COMPLETO","region":"PR","products":[{"codigo":"9900000123"}]}'::jsonb);
  if (r#>>'{summary,errorCount}')::int<>1 then raise exception 'EMPTY_DESCRIPTION_NOT_BLOCKED'; end if;
  r:=public.create_products_import_batch('{"import_type":"PRECO_PR","region":"PR","products":[{"codigo":"9900000121","preco_pr":9}]}'::jsonb);
  if r->>'status'<>'validated' or (r#>>'{summary,errorCount}')::int<>0
    or (r#>>'{summary,warningCount}')::int<1 then raise exception 'PRICE_WARNING_NOT_NONBLOCKING'; end if;
  r:=public.approve_products_import_batch((r->>'batch_id')::uuid);
  if r->>'status'<>'approved' then raise exception 'PRICE_WARNING_BLOCKED_APPROVAL'; end if;
  raise notice 'PASS: empty code/description, zero/negative price, negative stock, duplicates blocked; large price change is warning';
end $$;
reset role;

-- Hypothetical feeding-only supervisor: no approval permission is seeded.
select set_config('request.jwt.claims','{"sub":"00000000-0121-4000-8000-000000000002","role":"authenticated","session_id":"10000000-0121-4000-8000-000000000002"}',true);
set local role authenticated;
do $$ declare r jsonb; b uuid; begin
  if public.can_approve_products_import() then raise exception 'FEED_FIXTURE_HAS_APPROVAL'; end if;
  r:=public.create_products_import_batch('{"import_type":"PRECO_PR","region":"PR","products":[{"codigo":"9900000121","preco_pr":80}]}'::jsonb);
  b:=(r->>'batch_id')::uuid;
  r:=public.preview_products_import_batch(b);
  if r->>'status'<>'validated' then raise exception 'FEED_VALIDATION_FAILED'; end if;
  begin perform public.approve_products_import_batch(b); raise exception 'FEED_APPROVAL_ACCEPTED';
  exception when sqlstate 'P2812' then null; end;
  begin perform public.commit_products_import_batch(b); raise exception 'FEED_COMMIT_ACCEPTED';
  exception when sqlstate 'P2812' then null; end;
  begin perform public.commit_products_import_batch_v0_impl(b); raise exception 'DELEGATE_ACCEPTED';
  exception when insufficient_privilege then null; end;
  begin update public.products set preco_pr=1 where codigo='9900000121'; raise exception 'DIRECT_UPDATE_ACCEPTED';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS: feeding-only validation preserved; approval, commit, raw delegate and direct writes denied';
end $$;
reset role;

-- A seller without feeding permission cannot even create a validation batch.
select set_config('request.jwt.claims','{"sub":"00000000-0121-4000-8000-000000000003","role":"authenticated","session_id":"10000000-0121-4000-8000-000000000003"}',true);
set local role authenticated;
do $$ begin
  begin
    perform public.create_products_import_batch('{"import_type":"PRECO_PR","region":"PR","products":[{"codigo":"9900000121","preco_pr":80}]}'::jsonb);
    raise exception 'SELLER_VALIDATION_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'SEM_PERMISSAO' then raise; end if; end;
  begin
    perform public.import_products_transactional('{}'::jsonb);
    raise exception 'LEGACY_IMPORT_ACCEPTED';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS: seller cannot stage without feeding permission or call obsolete import';
end $$;
reset role;

-- A server audit failure must roll back actual product and batch mutations.
select set_config('request.jwt.claims','{"sub":"00000000-0121-4000-8000-000000000001","role":"authenticated","session_id":"10000000-0121-4000-8000-000000000001"}',true);
set local role authenticated;
do $$ declare r jsonb; b uuid; begin
  r:=public.create_products_import_batch('{"import_type":"PRECO_PR","region":"PR","products":[{"codigo":"9900000121","preco_pr":70}]}'::jsonb);
  b:=(r->>'batch_id')::uuid;
  perform public.approve_products_import_batch(b);
  insert into lab121_batches values('rollback',b);
end $$;
reset role;
create function pg_temp.lab121_fail_audit() returns trigger language plpgsql as $$ begin
  if new.acao='IMPORTAR_PRODUTOS' then raise exception 'LAB121_AUDIT_UNAVAILABLE'; end if;
  return new;
end $$;
create trigger lab121_fail_audit before insert on public.logs for each row execute function pg_temp.lab121_fail_audit();
set local role authenticated;
do $$ declare b uuid; begin
  select id into b from lab121_batches where label='rollback';
  begin perform public.commit_products_import_batch(b); raise exception 'AUDIT_FAILURE_COMMIT_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'LAB121_AUDIT_UNAVAILABLE' then raise; end if; end;
  if (select preco_pr from public.products where codigo='9900000121')<>90
    or (select status from public.products_import_batches where id=b)<>'approved'
    or exists(select 1 from public.products_import_audit where batch_id=b) then
    raise exception 'REAL_ATOMIC_ROLLBACK_FAILED';
  end if;
  raise notice 'PASS: actual commit rolls back product, audit and status on log failure';
end $$;
reset role;
select jsonb_build_object('status','PASS_FULL_SCHEMA_IMPORT_121','fictional_data_only',true,
  'real_rpcs',jsonb_build_array('create_products_import_batch','preview_products_import_batch',
    'approve_products_import_batch','commit_products_import_batch','set_product_active'),
  'checks',jsonb_build_array('ADMIN approved import','feed-only denied approval and commit',
    'seller denied staging','empty code and description','zero and negative price','negative stock',
    'duplicate codes','large price change warning','new product','duplicate file and commit',
    'manual inactive and absent field preservation','field before/after audit','server provenance',
    'atomic rollback on audit failure'));
rollback;
