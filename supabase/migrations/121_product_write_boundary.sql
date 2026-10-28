begin;

-- Browser roles cannot update canonical or legacy-mirror business values.
-- Keep SELECT/RLS and trusted backend/SECURITY DEFINER writers unchanged.
do $$ declare table_name text; columns_sql text; begin
  foreach table_name in array array['products','product_sap_data','product_branch_prices',
    'product_branch_stock','product_route_prices'] loop
    execute format('revoke insert,update,delete,truncate on public.%I from public,anon,authenticated',table_name);
    select string_agg(format('%I',a.attname),',' order by a.attnum) into columns_sql
      from pg_attribute a where a.attrelid=format('public.%I',table_name)::regclass
        and a.attnum>0 and not a.attisdropped;
    execute format('revoke insert (%s),update (%s) on public.%I from public,anon,authenticated',
      columns_sql,columns_sql,table_name);
  end loop;
end $$;

-- Obsolete immediate-write endpoint: no supported frontend/integration calls it.
revoke all on function public.import_products_transactional(jsonb) from public,anon,authenticated;

-- Wrappers retain execution and call delegates as their trusted owner. Direct
-- delegate calls must not bypass contract/branch checks in the wrappers.
do $$ declare signature regprocedure; begin
  for signature in select p.oid::regprocedure from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f'
      and p.proname=any(array['create_products_import_batch_v0_impl',
        'preview_products_import_batch_v0_impl','approve_products_import_batch_v0_impl',
        'commit_products_import_batch_v0_impl','get_products_import_batch_details_v0_impl',
        'get_products_import_batches_report_v0_impl'])
  loop
    execute format('revoke all on function %s from public,anon,authenticated',signature);
  end loop;
end $$;

comment on function public.import_products_transactional(jsonb) is
  'Deprecated immediate-write path; browser roles must use approved import batches.';
commit;
