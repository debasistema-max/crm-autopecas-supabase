-- Full real schema, fictional data only. Never run on a populated database.
begin;
do $$ begin
  if current_setting('crm.test_disposable',true) is distinct from 'on' then
    raise exception 'DISPOSABLE_DATABASE_REQUIRED';
  end if;
  if exists(select 1 from auth.users) or exists(select 1 from public.products)
    or exists(select 1 from public.products_import_batches) then raise exception 'EMPTY_SCHEMA_REQUIRED'; end if;
end $$;
insert into auth.users(id,email) values
 ('00000000-0121-4000-8000-000000000001','integration121@example.invalid');
insert into public.profiles(id,usuario,nome,email,perfil) values
 ('00000000-0121-4000-8000-000000000001','lab121admin','LAB ADMIN','integration121@example.invalid','ADMIN');
insert into auth.sessions(id,user_id,created_at) values
 ('10000000-0121-4000-8000-000000000001','00000000-0121-4000-8000-000000000001',now());
insert into public.app_session_policy(id,enforced) values(true,true);
insert into public.app_sessions(user_id,active_session_id,auth_created_at)
 select user_id,id,created_at from auth.sessions;
insert into public.branches(code,name,state,city,is_headquarters) values
 ('PR','LAB MATRIZ','PR','LAB PR',true),('SP','LAB FILIAL','SP','LAB SP',false);
insert into public.data_sync_sources(source_code,display_name,adapter_type)
 values('EXCEL_API','LAB EXCEL','HTTP_ADAPTER');
insert into public.products(codigo,descricao,marca,ano,preco_pr,preco_sp,detalhes) values
 ('9900000121','LAB PRODUCT','LAB BRAND','LAB YEAR',100,110,null),
 ('9900000123','LAB CATALOG',null,null,200,220,'LAB MANUAL NOTE');
select set_config('request.jwt.claims','{"sub":"00000000-0121-4000-8000-000000000001","role":"authenticated","session_id":"10000000-0121-4000-8000-000000000001"}',true);
set local role authenticated;
select public.set_product_active('9900000121',false,true)->>'ativo';
select public.set_product_active('9900000123',false,true)->>'ativo';
reset role;

-- Actual server role and actual chunked Excel pipeline, not owner bypass.
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
do $$ declare b uuid; r jsonb; original_audits bigint; attempt int; begin
  b:=(public.create_data_sync_batch(jsonb_build_object('source','EXCEL_API',
    'source_version','lab121-excel','source_updated_at',clock_timestamp(),
    'file_hash',repeat('a',64),'original_filename','lab-only.xlsx'))->>'batch_id')::uuid;
  perform public.stage_data_sync_rows(b,'[
    {"row_number":1,"area":"PRODUCT","product_code":"9900000121",
     "fields":{"description":"LAB UPDATED PRODUCT","brand":"","model":"LAB MODEL"}},
    {"row_number":2,"area":"STOCK","product_code":"9900000121","branch_code":"PR",
     "fields":{"stock_qty":0,"general_available_qty":0}},
    {"row_number":3,"area":"BASE_PRICE","product_code":"9900000121","branch_code":"PR",
     "fields":{"base_price":150,"currency":"BRL"}},
    {"row_number":4,"area":"ROUTE_PRICE","product_code":"9900000121","route":"PR-PR",
     "fields":{"base_price":150,"final_price":180,"total_taxes":30,"calculation_status":"OK","currency":"BRL"}}
  ]'::jsonb);
  r:=public.validate_data_sync_batch(b);
  if r->>'state'<>'PREVIEWED' or (r->>'error_count')::int<>0 then
    raise exception 'EXCEL_VALIDATION_FAILED: %',r;
  end if;
  for attempt in 1..10 loop
    r:=public.commit_data_sync_batch_chunk(b,2);
    exit when (r->>'done')::boolean;
  end loop;
  if not coalesce((r->>'done')::boolean,false)
    or (select state from public.products_import_batches where id=b)<>'COMMITTED' then
    raise exception 'EXCEL_CHUNK_COMMIT_FAILED: %',r;
  end if;
  if not exists(select 1 from public.products where codigo='9900000121'
      and descricao='LAB UPDATED PRODUCT' and marca='LAB BRAND' and ano='LAB YEAR' and not ativo)
    or not exists(select 1 from public.product_sap_data where product_code='9900000121' and model='LAB MODEL') then
    raise exception 'EXCEL_PRODUCT_SAP_OR_PRESERVATION_FAILED';
  end if;
  if not exists(select 1 from public.product_branch_stock s join public.branches br on br.id=s.branch_id
      where s.product_code='9900000121' and br.code='PR' and physical_qty=0 and sap_general_available_qty=0)
    or not exists(select 1 from public.product_branch_prices p join public.branches br on br.id=p.branch_id
      where p.product_code='9900000121' and br.code='PR' and sale_price=150)
    or not exists(select 1 from public.product_route_prices where product_code='9900000121' and route='PR-PR' and final_price=180) then
    raise exception 'EXCEL_CANONICAL_STOCK_PRICE_ROUTE_FAILED';
  end if;
  select count(*) into original_audits from public.products_import_audit where batch_id=b;
  if original_audits=0 then raise exception 'EXCEL_AUDIT_MISSING'; end if;
  r:=public.commit_data_sync_batch_chunk(b,2);
  if (select count(*) from public.products_import_audit where batch_id=b)<>original_audits then
    raise exception 'EXCEL_RETRY_DUPLICATED_AUDIT';
  end if;
  r:=public.create_data_sync_batch(jsonb_build_object('source','EXCEL_API',
    'source_version','lab121-excel','source_updated_at',clock_timestamp(),'file_hash',repeat('a',64)));
  if not (r->>'duplicate')::boolean or (r->>'batch_id')::uuid<>b then
    raise exception 'EXCEL_BATCH_IDEMPOTENCY_FAILED';
  end if;
end $$;
reset role;

-- Request as an actual authenticated ADMIN, then claim as the dedicated worker.
select set_config('request.jwt.claims','{"sub":"00000000-0121-4000-8000-000000000001","role":"authenticated","session_id":"10000000-0121-4000-8000-000000000001"}',true);
set local role authenticated;
select public.request_installed_catalog_sync()->>'status';
do $$ begin
  if has_function_privilege(current_user,'public.finish_installed_catalog_sync(uuid,uuid,jsonb)','execute')
    or has_function_privilege(current_user,'public.claim_installed_catalog_sync()','execute') then
    raise exception 'BROWSER_CAN_EXECUTE_CATALOG_WORKER_RPC';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims','{}',true);
create temporary table lab121_worker_result(job_id uuid,batch_id uuid);
grant select,insert on lab121_worker_result to ips_catalog_worker;
set session authorization ips_catalog_worker;
do $$ declare job jsonb; snapshot jsonb; r jsonb; old_fields jsonb; new_fields jsonb; plan jsonb; begin
  if current_user<>'ips_catalog_worker' or session_user<>'ips_catalog_worker' then
    raise exception 'DEDICATED_WORKER_ROLE_NOT_USED';
  end if;
  begin update public.products set preco_pr=1 where codigo='9900000123';
    raise exception 'WORKER_HAS_DIRECT_PRODUCT_WRITE';
  exception when insufficient_privilege then null; end;
  job:=public.claim_installed_catalog_sync();
  if job is null then raise exception 'WORKER_CLAIM_FAILED'; end if;
  snapshot:=public.snapshot_installed_catalog_sync((job->>'id')::uuid,(job->>'claim_token')::uuid,'');
  select value - 'codigo' - 'catalog_line' - 'catalog_application' into old_fields
    from jsonb_array_elements(snapshot) where value->>'codigo'='9900000123';
  if old_fields is null then raise exception 'WORKER_SNAPSHOT_FAILED'; end if;
  new_fields:=old_fields||jsonb_build_object('categoria','LAB LINE','marca','LAB BRAND',
    'aplicacao','LAB APPLICATION','detalhes',E'LAB MANUAL NOTE\n[CATALOGO_IPS_INSTALADO]\nLAB DETAILS\n[/CATALOGO_IPS_INSTALADO]');
  plan:=jsonb_build_object('source','IPS_INSTALLED_CATALOG','source_version',repeat('b',64),
    'summary',jsonb_build_object('source_products',1,'matched',1,'updated',1,'unchanged',0,'unmatched',0),
    'changes',jsonb_build_array(jsonb_build_object('codigo','9900000123','before',old_fields,'after',new_fields)));
  begin
    perform public.finish_installed_catalog_sync((job->>'id')::uuid,gen_random_uuid(),plan);
    raise exception 'WRONG_WORKER_TOKEN_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'LOTE_OU_EXECUTOR_INVALIDO' then raise; end if; end;
  r:=public.finish_installed_catalog_sync((job->>'id')::uuid,(job->>'claim_token')::uuid,plan);
  if r->>'status'<>'completed' then raise exception 'WORKER_FINISH_FAILED'; end if;
  insert into lab121_worker_result values((job->>'id')::uuid,(r->>'batch_id')::uuid);
  r:=public.finish_installed_catalog_sync((job->>'id')::uuid,(job->>'claim_token')::uuid,plan);
  if r->>'status'<>'completed' then raise exception 'WORKER_RETRY_FAILED'; end if;
end $$;
reset session authorization;
do $$ declare b uuid; begin
  select batch_id into b from lab121_worker_result;
  if not exists(select 1 from public.products where codigo='9900000123'
    and categoria='LAB LINE' and aplicacao='LAB APPLICATION' and preco_pr=200 and preco_sp=220 and not ativo
    and public.installed_catalog_manual_notes(detalhes)='LAB MANUAL NOTE') then
    raise exception 'CATALOG_OVERWROTE_PRICE_ACTIVITY_OR_MANUAL_NOTES';
  end if;
  if (select count(*) from public.product_catalog_metadata_audit where batch_id=b)<>1
    or (select count(*) from public.logs where acao='SINCRONIZAR_CATALOGO_IPS' and id_entidade=b::text and audit_source='SERVER')<>1 then
    raise exception 'CATALOG_AUDIT_MISSING_OR_DUPLICATED';
  end if;
end $$;
select jsonb_build_object('status','PASS_PRODUCT_INTEGRATIONS_121','fictional_data_only',true,
 'checks',jsonb_build_array('real service-role Excel chunk pipeline','product and SAP writes',
   'canonical stock/base/route prices','empty and inactive preservation','Excel replay protection',
   'real dedicated catalog worker claim/snapshot/finish','bad token denied','browser worker RPC denied',
   'worker direct write denied','catalog price/activity/manual notes preservation','catalog audit and retry'));
rollback;
