-- Fictional fixtures only. The runner creates this isolated, disposable database.
begin;
do $$ begin
  if current_database() <> 'crm_catalog123_test' then
    raise exception 'DISPOSABLE_CATALOG_DATABASE_REQUIRED';
  end if;
end $$;

create function pg_temp.assert(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'TEST_FAILED:%', label; end if; end $$;

select pg_temp.assert(not has_function_privilege('anon', 'public.finish_installed_catalog_sync(uuid,uuid,jsonb)', 'execute'), 'anon_denied');
select pg_temp.assert(not has_function_privilege('authenticated', 'public.finish_installed_catalog_sync(uuid,uuid,jsonb)', 'execute'), 'browser_denied');
select pg_temp.assert(has_function_privilege('ips_catalog_worker', 'public.finish_installed_catalog_sync(uuid,uuid,jsonb)', 'execute'), 'worker_allowed');
select pg_temp.assert(not has_table_privilege('ips_catalog_worker', 'public.products', 'update'), 'worker_no_direct_update');

do $$
declare
  candidate text;
  origin text := 'https://pub-1c42f71f3a974244953a13b83a68b545.r2.dev/';
  job uuid;
  token uuid;
  before_value jsonb;
  after_value jsonb;
  plan jsonb;
  result jsonb;
  protected jsonb;
  count_before bigint;
begin
  select jsonb_build_object('url_imagem',url_imagem,'marca',marca,'aplicacao',aplicacao,
    'categoria',categoria,'montadora',montadora,'oem',oem,'similar',"similar",'detalhes',detalhes),
    to_jsonb(p)-array['url_imagem','marca','aplicacao','categoria','montadora','oem','similar','detalhes']
    into before_value, protected from public.products p where codigo='TEST-CATALOG-123';
  foreach candidate in array array['png','PNG','PnG','jpg','JPG','jpeg','JpEg','webp','WEBP'] loop
    insert into public.installed_catalog_sync_requests(requested_by,status,claim_token,lease_until)
      values('00000000-0000-0000-0000-000000000123','running',gen_random_uuid(),now()+interval '5 minutes')
      returning id,claim_token into job,token;
    after_value := before_value || jsonb_build_object('url_imagem',origin||'test.'||candidate,
      'detalhes',E'Manual\n\n[CATALOGO_IPS_INSTALADO]\nTeste\n[/CATALOGO_IPS_INSTALADO]');
    plan := jsonb_build_object('source','IPS_INSTALLED_CATALOG','source_version',repeat('a',64),
      'summary',jsonb_build_object('source_products',1,'matched',1,'updated',1,'unchanged',0,'unmatched',0),
      'changes',jsonb_build_array(jsonb_build_object('codigo','TEST-CATALOG-123','before',before_value,'after',after_value)));
    result := public.finish_installed_catalog_sync(job,token,plan);
    perform pg_temp.assert(result->>'status'='completed','extension_'||candidate);
    perform pg_temp.assert((select before_data->'fields'=before_value and after_data->'fields'=after_value
      from public.product_catalog_metadata_audit where batch_id=(result->>'batch_id')::uuid),'audit_'||candidate);
    perform pg_temp.assert((select count(*)=1 from public.product_catalog_metadata_audit
      where batch_id=(result->>'batch_id')::uuid),'single_audit_'||candidate);
    perform public.finish_installed_catalog_sync(job,token,plan);
    perform pg_temp.assert((select count(*)=1 from public.product_catalog_metadata_audit
      where batch_id=(result->>'batch_id')::uuid),'idempotent_'||candidate);
    perform pg_temp.assert(protected=(select to_jsonb(p)-array['url_imagem','marca','aplicacao',
      'categoria','montadora','oem','similar','detalhes'] from public.products p where codigo='TEST-CATALOG-123'),
      'commercial_fields_preserved_'||candidate);
    update public.products set url_imagem=null,detalhes='Manual' where codigo='TEST-CATALOG-123';
  end loop;
  foreach candidate in array array[
    'https://example.invalid/test.PNG',
    'http://pub-1c42f71f3a974244953a13b83a68b545.r2.dev/test.PNG',
    'https://pub-1c42f71f3a974244953a13b83a68b545.r2.dev.evil.invalid/test.PNG',
    'https://pub-1c42f71f3a974244953a13b83a68b545.r2.dev/test.PNG?x=1',
    'https://pub-1c42f71f3a974244953a13b83a68b545.r2.dev/test.PNG#x',
    'https://pub-1c42f71f3a974244953a13b83a68b545.r2.dev/test.svg',
    'https://pub-1c42f71f3a974244953a13b83a68b545.r2.dev/test.png.exe',
    'https://pub-1c42f71f3a974244953a13b83a68b545.r2.dev/test.png/'
  ] loop
    insert into public.installed_catalog_sync_requests(requested_by,status,claim_token,lease_until)
      values('00000000-0000-0000-0000-000000000123','running',gen_random_uuid(),now()+interval '5 minutes')
      returning id,claim_token into job,token;
    after_value := before_value || jsonb_build_object('url_imagem',candidate,
      'detalhes',E'Manual\n\n[CATALOGO_IPS_INSTALADO]\nTeste\n[/CATALOGO_IPS_INSTALADO]');
    plan := jsonb_set(plan,'{changes}',jsonb_build_array(jsonb_build_object(
      'codigo','TEST-CATALOG-123','before',before_value,'after',after_value)));
    select count(*) into count_before from public.catalog_metadata_sync_batches;
    begin
      perform public.finish_installed_catalog_sync(job,token,plan);
      raise exception 'TEST_FAILED:invalid_image_accepted';
    exception when raise_exception then
      if sqlerrm <> 'ORIGEM_IMAGEM_INVALIDA' then raise; end if;
    end;
    perform pg_temp.assert((select count(*)=count_before from public.catalog_metadata_sync_batches),'no_partial_batch');
    perform pg_temp.assert((select url_imagem is null from public.products where codigo='TEST-CATALOG-123'),'no_partial_product');
    update public.installed_catalog_sync_requests set status='failed' where id=job;
  end loop;
end $$;

select 'PASS: extension case, origin restrictions, audit, idempotence, permissions, protected values and atomic rejection' as result;
rollback;
