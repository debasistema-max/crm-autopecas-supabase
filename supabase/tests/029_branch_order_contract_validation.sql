\set ON_ERROR_STOP on

select
  current_database() as test_029_wrapper_source_db,
  current_user as test_029_wrapper_user
\gset

\if :{?test_029_inner}
\else
  \setenv TEST_029_SOURCE_DB :test_029_wrapper_source_db
  \setenv TEST_029_RUN_USER :test_029_wrapper_user
  \connect postgres
  \! bash -o pipefail -c 'token=$$; cleanup(){ dbs=$(psql -X -U "$TEST_029_RUN_USER" -d postgres -Atc "select datname from pg_database where datname like \$\$test029_%_${token}\$\$") || return 1; for db in $dbs; do psql -X -U "$TEST_029_RUN_USER" -d postgres -v ON_ERROR_STOP=1 -c "drop database \"$db\" with (force)" >/dev/null || return 1; done; }; trap "rc=\$?; trap - EXIT; cleanup || rc=1; exit \$rc" EXIT; trap "exit 130" INT TERM; schema_before=$(pg_dump -U "$TEST_029_RUN_USER" -d "$TEST_029_SOURCE_DB" --schema-only | sed "/^\\\\restrict /d;/^\\\\unrestrict /d" | sha256sum | cut -d" " -f1) || exit 1; data_before=$(pg_dump -U "$TEST_029_RUN_USER" -d "$TEST_029_SOURCE_DB" --data-only --no-owner --no-privileges | sed "/^\\\\restrict /d;/^\\\\unrestrict /d" | sha256sum | cut -d" " -f1) || exit 1; psql -X -U "$TEST_029_RUN_USER" -d "$TEST_029_SOURCE_DB" -v ON_ERROR_STOP=1 -v test_029_inner=1 -v test_029_run_token="$token" -f tests/029_branch_order_contract_validation.sql; rc=$?; schema_after=$(pg_dump -U "$TEST_029_RUN_USER" -d "$TEST_029_SOURCE_DB" --schema-only | sed "/^\\\\restrict /d;/^\\\\unrestrict /d" | sha256sum | cut -d" " -f1) || exit 1; data_after=$(pg_dump -U "$TEST_029_RUN_USER" -d "$TEST_029_SOURCE_DB" --data-only --no-owner --no-privileges | sed "/^\\\\restrict /d;/^\\\\unrestrict /d" | sha256sum | cut -d" " -f1) || exit 1; if [ "$schema_before" != "$schema_after" ] || [ "$data_before" != "$data_after" ]; then echo "TEST_029_SOURCE_FINGERPRINT_CHANGED"; exit 1; fi; exit "$rc"'
  \if :SHELL_ERROR
    select 1 / 0;
  \else
    \quit
  \endif
\endif

do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (
       select 1
       from supabase_migrations.schema_migrations
       where version = '028'
     )
     or exists (
       select 1
       from supabase_migrations.schema_migrations
       where version ~ '^[0-9]+$'
         and version::numeric > 28
     ) then
    raise exception 'TEST_029_REQUIRES_DATABASE_AT_MIGRATION_028';
  end if;
end;
$$;

select
  current_database() as test_029_source_db,
  format('test029_main_%s', :'test_029_run_token') as test_029_main_db,
  format('test029_null_%s', :'test_029_run_token') as test_029_null_db,
  format('test029_invalid_%s', :'test_029_run_token') as test_029_invalid_db,
  format('test029_duplicate_%s', :'test_029_run_token') as test_029_duplicate_db,
  format('test029_v1_%s', :'test_029_run_token') as test_029_v1_db,
  format('test029_downstream_%s', :'test_029_run_token') as test_029_downstream_db,
  format('test029_race_%s', :'test_029_run_token') as test_029_race_db,
  format('test029_column_%s', :'test_029_run_token') as test_029_column_db,
  format('test029_index_%s', :'test_029_run_token') as test_029_index_db,
  format('test029_constraint_%s', :'test_029_run_token') as test_029_constraint_db,
  format('test029_flag_%s', :'test_029_run_token') as test_029_flag_db,
  format('test029_quote_%s', :'test_029_run_token') as test_029_quote_db,
  format('test029_snapshot_%s', :'test_029_run_token') as test_029_snapshot_db,
  format('test029_snapshot_tamper_%s', :'test_029_run_token') as test_029_snapshot_tamper_db,
  format('test029_reapply_forgery_%s', :'test_029_run_token') as test_029_reapply_forgery_db,
  format('test029_policy_%s', :'test_029_run_token') as test_029_policy_db,
  format('test029_security_%s', :'test_029_run_token') as test_029_security_db,
  format('test029_helper_%s', :'test_029_run_token') as test_029_helper_db,
  format('test029_rpc_metadata_%s', :'test_029_run_token') as test_029_rpc_metadata_db,
  format('test029_snapshot_storage_%s', :'test_029_run_token') as test_029_snapshot_storage_db,
  format('test029_rollback_manifest_%s', :'test_029_run_token') as test_029_rollback_manifest_db,
  format('test029_rollback_atomic_%s', :'test_029_run_token') as test_029_rollback_atomic_db,
  format('test029_trigger_%s', :'test_029_run_token') as test_029_trigger_db,
  format('test029_rollback_partial_%s', :'test_029_run_token') as test_029_rollback_partial_db,
  format('test029_rollback_settings_%s', :'test_029_run_token') as test_029_rollback_settings_db,
  format('test029_rollback_constraint_%s', :'test_029_run_token') as test_029_rollback_constraint_db,
  format('test029_rollback_unrelated_%s', :'test_029_run_token') as test_029_rollback_unrelated_db,
  format('test029_version_%s', :'test_029_run_token') as test_029_version_db,
  format('test029_logistics_%s', :'test_029_run_token') as test_029_logistics_db
\gset

\connect postgres
create database :"test_029_main_db" template :"test_029_source_db";
create database :"test_029_null_db" template :"test_029_source_db";
create database :"test_029_invalid_db" template :"test_029_source_db";
create database :"test_029_duplicate_db" template :"test_029_source_db";
create database :"test_029_v1_db" template :"test_029_source_db";
create database :"test_029_downstream_db" template :"test_029_source_db";
create database :"test_029_race_db" template :"test_029_source_db";
create database :"test_029_column_db" template :"test_029_source_db";
create database :"test_029_index_db" template :"test_029_source_db";
create database :"test_029_constraint_db" template :"test_029_source_db";
create database :"test_029_flag_db" template :"test_029_source_db";
create database :"test_029_quote_db" template :"test_029_source_db";
create database :"test_029_snapshot_db" template :"test_029_source_db";
create database :"test_029_snapshot_tamper_db" template :"test_029_source_db";
create database :"test_029_reapply_forgery_db" template :"test_029_source_db";
create database :"test_029_policy_db" template :"test_029_source_db";
create database :"test_029_security_db" template :"test_029_source_db";
create database :"test_029_helper_db" template :"test_029_source_db";
create database :"test_029_rpc_metadata_db" template :"test_029_source_db";
create database :"test_029_snapshot_storage_db" template :"test_029_source_db";
create database :"test_029_rollback_manifest_db" template :"test_029_source_db";
create database :"test_029_rollback_atomic_db" template :"test_029_source_db";
create database :"test_029_trigger_db" template :"test_029_source_db";
create database :"test_029_rollback_partial_db" template :"test_029_source_db";
create database :"test_029_rollback_settings_db" template :"test_029_source_db";
create database :"test_029_rollback_constraint_db" template :"test_029_source_db";
create database :"test_029_rollback_unrelated_db" template :"test_029_source_db";
create database :"test_029_version_db" template :"test_029_source_db";
create database :"test_029_logistics_db" template :"test_029_source_db";
\connect :"test_029_main_db"

create temporary table test_029_compatibility_baseline
on commit preserve rows
as
select
  md5(pg_get_functiondef(
    'public.commit_product_import_batch(uuid)'::regprocedure
  )) as import_commit_definition_md5,
  md5(pg_get_functiondef(
    'public.sync_legacy_product_stock_to_pr()'::regprocedure
  )) as legacy_stock_sync_definition_md5,
  (select count(*) from public.product_branch_stock) as stock_rows,
  (select coalesce(sum(physical_qty), 0) from public.product_branch_stock) as physical_qty,
  (select coalesce(sum(reserved_order_qty), 0) from public.product_branch_stock) as reserved_order_qty,
  (select count(*) from public.product_branch_prices) as price_rows,
  (select count(*) from public.stock_movements) as movement_rows;

create temporary table test_029_branches_baseline
on commit preserve rows
as table public.branches;
create temporary table test_029_profile_branches_baseline
on commit preserve rows
as table public.profile_branches;
create temporary table test_029_stock_baseline
on commit preserve rows
as table public.product_branch_stock;
create temporary table test_029_prices_baseline
on commit preserve rows
as table public.product_branch_prices;
create temporary table test_029_movements_baseline
on commit preserve rows
as table public.stock_movements;
create temporary table test_029_products_baseline
on commit preserve rows
as table public.products;
create temporary table test_029_import_batches_baseline
on commit preserve rows
as table public.products_import_batches;
create temporary table test_029_import_stage_baseline
on commit preserve rows
as table public.products_import_stage;
create temporary table test_029_import_audit_baseline
on commit preserve rows
as table public.products_import_audit;
create temporary table test_029_legacy_function_snapshots_baseline
on commit preserve rows
as table public.branch_import_legacy_function_snapshots;
create temporary table test_029_legacy_acl_snapshots_baseline
on commit preserve rows
as table public.branch_import_legacy_table_acl_snapshots;

create temporary table test_029_commercial_policy_baseline
on commit preserve rows
as
select
  c.relname as table_name,
  p.polname,
  p.polpermissive,
  p.polroles,
  p.polcmd,
  coalesce(pg_get_expr(p.polqual, p.polrelid), '') as using_expression,
  coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as check_expression
from pg_catalog.pg_policy p
join pg_catalog.pg_class c on c.oid = p.polrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and (c.relname, p.polname) in (
    ('orders', 'orders_read'),
    ('order_items', 'order_items_read'),
    ('quotations', 'quotations_read'),
    ('quotation_items', 'quotation_items_read')
  );

select md5(string_agg(
  concat_ws(
    '|',
    table_name,
    polname,
    polpermissive,
    polroles::text,
    polcmd,
    using_expression,
    check_expression
  ),
  E'\n'
  order by table_name, polname
)) as test_029_policy_baseline_md5
from test_029_commercial_policy_baseline
\gset

create or replace function pg_temp.test_029_commercial_policy_fingerprints()
returns table (
  table_name name,
  policy_name name,
  permissive boolean,
  roles oid[],
  command "char",
  using_expression text,
  check_expression text
)
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select
    c.relname,
    p.polname,
    p.polpermissive,
    p.polroles,
    p.polcmd,
    coalesce(pg_get_expr(p.polqual, p.polrelid), ''),
    coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
  from pg_catalog.pg_policy p
  join pg_catalog.pg_class c on c.oid = p.polrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and (c.relname, p.polname) in (
      ('orders', 'orders_read'),
      ('order_items', 'order_items_read'),
      ('quotations', 'quotations_read'),
      ('quotation_items', 'quotation_items_read')
    )
$$;

create or replace function pg_temp.test_029_compatibility_fingerprints()
returns table (
  category text,
  object_identity text,
  fingerprint text
)
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  with target_tables(table_name) as (
    values
      ('branches'),
      ('profile_branches'),
      ('products'),
      ('product_branch_stock'),
      ('product_branch_prices'),
      ('stock_movements'),
      ('products_import_batches'),
      ('products_import_stage'),
      ('products_import_audit'),
      ('branch_import_legacy_function_snapshots'),
      ('branch_import_legacy_table_acl_snapshots')
  ),
  target_functions(function_name) as (
    values
      ('touch_product_branch_stock'),
      ('reject_stock_movement_mutation'),
      ('can_access_branch'),
      ('get_default_branch_id'),
      ('sync_legacy_product_stock_to_pr'),
      ('touch_product_branch_price'),
      ('resolve_branch_import_initial_branches'),
      ('can_access_product_import_batch_row'),
      ('sync_legacy_product_prices_to_branches'),
      ('branch_import_allowed_fields'),
      ('normalize_branch_import_mask'),
      ('canonicalize_branch_import_data'),
      ('compute_product_import_staging_hash'),
      ('create_product_import_batch'),
      ('stage_product_import_rows'),
      ('reset_product_import_batch_to_draft'),
      ('preview_product_import_batch'),
      ('approve_product_import_batch'),
      ('commit_product_import_batch'),
      ('get_allowed_import_branches'),
      ('create_products_import_batch'),
      ('preview_products_import_batch'),
      ('approve_products_import_batch'),
      ('commit_products_import_batch'),
      ('get_products_import_batches_report'),
      ('get_products_import_batch_details')
  ),
  fingerprints as (
    select
      'columns'::text as category,
      c.relname || '.' || a.attname as object_identity,
      md5(concat_ws(
        '|',
        c.relname,
        a.attnum,
        a.attname,
        a.atttypid,
        a.atttypmod,
        a.attnotnull,
        a.attidentity,
        a.attgenerated,
        a.attcollation,
        coalesce(pg_get_expr(d.adbin, d.adrelid), '')
      )) as fingerprint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join target_tables t on t.table_name = c.relname
    join pg_attribute a
      on a.attrelid = c.oid
     and a.attnum > 0
     and not a.attisdropped
    left join pg_attrdef d
      on d.adrelid = a.attrelid
     and d.adnum = a.attnum
    where n.nspname = 'public'

    union all

    select
      'relation_metadata',
      c.relname,
      md5(concat_ws(
        '|',
        c.relname,
        c.relowner,
        c.relrowsecurity,
        c.relforcerowsecurity,
        coalesce(c.relacl::text, '')
      ))
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join target_tables t on t.table_name = c.relname
    where n.nspname = 'public'

    union all

    select
      'column_acls',
      c.relname || '.' || a.attname,
      md5(concat_ws(
        '|',
        c.relname,
        a.attnum,
        a.attname,
        coalesce(a.attacl::text, '')
      ))
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join target_tables t on t.table_name = c.relname
    join pg_attribute a
      on a.attrelid = c.oid
     and a.attnum > 0
     and not a.attisdropped
    where n.nspname = 'public'

    union all

    select
      'constraints',
      c.relname || '.' || con.conname,
      md5(concat_ws(
        '|',
        c.relname,
        con.conname,
        con.contype,
        con.convalidated,
        con.condeferrable,
        con.condeferred,
        pg_get_constraintdef(con.oid, true)
      ))
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join target_tables t on t.table_name = c.relname
    join pg_constraint con on con.conrelid = c.oid
    where n.nspname = 'public'

    union all

    select
      'indexes',
      table_class.relname || '.' || index_class.relname,
      md5(concat_ws(
        '|',
        table_class.relname,
        index_class.relname,
        idx.indisunique,
        idx.indisprimary,
        idx.indisexclusion,
        idx.indisvalid,
        idx.indisready,
        idx.indislive,
        pg_get_indexdef(idx.indexrelid)
      ))
    from pg_class table_class
    join pg_namespace n on n.oid = table_class.relnamespace
    join target_tables t on t.table_name = table_class.relname
    join pg_index idx on idx.indrelid = table_class.oid
    join pg_class index_class on index_class.oid = idx.indexrelid
    where n.nspname = 'public'

    union all

    select
      'triggers',
      c.relname || '.' || trigger.tgname,
      md5(concat_ws(
        '|',
        c.relname,
        trigger.tgname,
        trigger.tgenabled,
        pg_get_triggerdef(trigger.oid, true)
      ))
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join target_tables t on t.table_name = c.relname
    join pg_trigger trigger
      on trigger.tgrelid = c.oid
     and not trigger.tgisinternal
    where n.nspname = 'public'

    union all

    select
      'policies',
      c.relname || '.' || policy.polname,
      md5(concat_ws(
        '|',
        c.relname,
        policy.polname,
        policy.polpermissive,
        policy.polroles::text,
        policy.polcmd,
        coalesce(pg_get_expr(policy.polqual, policy.polrelid), ''),
        coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '')
      ))
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join target_tables t on t.table_name = c.relname
    join pg_policy policy on policy.polrelid = c.oid
    where n.nspname = 'public'

    union all

    select
      'table_acls',
      c.relname,
      md5(concat_ws('|', c.relname, coalesce(c.relacl::text, '')))
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join target_tables t on t.table_name = c.relname
    where n.nspname = 'public'

    union all

    select
      'functions',
      procedure.oid::regprocedure::text,
      md5(concat_ws(
        '|',
        procedure.oid::regprocedure::text,
        procedure.proowner,
        procedure.prosecdef,
        coalesce(procedure.proconfig::text, ''),
        coalesce(procedure.proacl::text, ''),
        pg_get_functiondef(procedure.oid)
      ))
    from pg_proc procedure
    join pg_namespace n on n.oid = procedure.pronamespace
    join target_functions target
      on target.function_name = procedure.proname
    where n.nspname = 'public'

    union all

    select
      'extensions',
      extension.extname,
      md5(concat_ws(
        '|',
        extension.extname,
        extension.extowner,
        extension.extversion,
        extension.extrelocatable,
        extension.extnamespace
      ))
    from pg_extension extension
    where extension.extname = 'pgcrypto'
  )
  select
    fingerprints.category,
    fingerprints.object_identity,
    fingerprints.fingerprint
  from fingerprints
$$;

create or replace function public.test_029_commercial_legacy_fingerprints()
returns table (
  category text,
  object_identity text,
  fingerprint text
)
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  with commercial_tables(table_name) as (
    values ('orders'), ('order_items'), ('quotations'), ('quotation_items')
  ),
  commercial_functions(function_name) as (
    values
      ('commercial_update_document_items'),
      ('commercial_update_document_status'),
      ('convert_quotation_to_order')
  )
  select
    'columns',
    c.relname || '.' || a.attname,
    md5(concat_ws(
      '|',
      a.attnum,
      a.atttypid,
      a.atttypmod,
      a.attnotnull,
      a.attidentity,
      a.attgenerated,
      a.attcollation,
      coalesce(pg_get_expr(d.adbin, d.adrelid), ''),
      coalesce(a.attacl::text, '')
    ))
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join commercial_tables target on target.table_name = c.relname
  join pg_attribute a
    on a.attrelid = c.oid
   and a.attnum > 0
   and not a.attisdropped
  left join pg_attrdef d
    on d.adrelid = a.attrelid
   and d.adnum = a.attnum
  where n.nspname = 'public'

  union all

  select
    'relations',
    c.relname,
    md5(concat_ws(
      '|',
      c.relowner,
      c.relrowsecurity,
      c.relforcerowsecurity,
      coalesce(c.relacl::text, '')
    ))
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join commercial_tables target on target.table_name = c.relname
  where n.nspname = 'public'

  union all

  select
    'constraints',
    c.relname || '.' || con.conname,
    md5(concat_ws(
      '|',
      con.contype,
      con.convalidated,
      con.condeferrable,
      con.condeferred,
      pg_get_constraintdef(con.oid, true)
    ))
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  join commercial_tables target on target.table_name = c.relname
  where n.nspname = 'public'

  union all

  select
    'indexes',
    table_class.relname || '.' || index_class.relname,
    md5(concat_ws(
      '|',
      idx.indisunique,
      idx.indisprimary,
      idx.indisexclusion,
      idx.indisvalid,
      idx.indisready,
      idx.indislive,
      pg_get_indexdef(idx.indexrelid)
    ))
  from pg_class table_class
  join pg_namespace n on n.oid = table_class.relnamespace
  join commercial_tables target on target.table_name = table_class.relname
  join pg_index idx on idx.indrelid = table_class.oid
  join pg_class index_class on index_class.oid = idx.indexrelid
  where n.nspname = 'public'

  union all

  select
    'triggers',
    c.relname || '.' || t.tgname,
    md5(concat_ws(
      '|',
      t.tgenabled,
      pg_get_triggerdef(t.oid, true)
    ))
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join commercial_tables target on target.table_name = c.relname
  where n.nspname = 'public'
    and not t.tgisinternal

  union all

  select
    'functions',
    p.oid::regprocedure::text,
    md5(concat_ws(
      '|',
      p.proowner,
      p.prosecdef,
      coalesce(p.proconfig::text, ''),
      coalesce(p.proacl::text, ''),
      pg_get_functiondef(p.oid)
    ))
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join commercial_functions target on target.function_name = p.proname
  where n.nspname = 'public'
$$;

create temporary table test_029_catalog_baseline
on commit preserve rows
as
select *
from pg_temp.test_029_compatibility_fingerprints();

create table public.test_029_commercial_legacy_baseline
as
select *
from public.test_029_commercial_legacy_fingerprints();

\ir ../migrations/029_branch_order_contract.sql
\setenv PGDATABASE :test_029_main_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_ALREADY_APPLIED_OR_PARTIAL" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then
    raise exception 'ASSERTION_FAILED: %', message;
  end if;
end;
$$;

create temporary table test_029_context (
  pr_branch_id uuid not null,
  sp_branch_id uuid not null,
  product_code text not null,
  admin_id uuid not null,
  supervisor_id uuid not null,
  seller_id uuid not null
) on commit drop;

insert into test_029_context
select
  (select id from public.branches where code = 'PR' and active and is_headquarters),
  (select id from public.branches where code = 'SP' and active),
  (select codigo from public.products order by codigo limit 1),
  '29000000-0000-4000-8000-000000000001'::uuid,
  '29000000-0000-4000-8000-000000000002'::uuid,
  '29000000-0000-4000-8000-000000000003'::uuid;

grant select on test_029_context to authenticated;

select pg_temp.assert_true(
  (select count(*) from test_029_context) = 1
  and (select pr_branch_id is not null and sp_branch_id is not null and product_code is not null
       from test_029_context),
  'canonical branches and a product must exist'
);

select pg_temp.assert_true(
  has_table_privilege('authenticated', 'public.orders', 'SELECT')
  and has_table_privilege('authenticated', 'public.order_items', 'SELECT')
  and has_table_privilege('authenticated', 'public.quotations', 'SELECT')
  and has_table_privilege('authenticated', 'public.quotation_items', 'SELECT')
  and has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.can_access_branch(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.is_active_branch_order_profile()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.is_branch_order_supervisor()', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.orders', 'INSERT')
  and not has_table_privilege('authenticated', 'public.orders', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.orders', 'DELETE')
  and not has_table_privilege('authenticated', 'public.order_items', 'INSERT')
  and not has_table_privilege('authenticated', 'public.order_items', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.order_items', 'DELETE')
  and not has_table_privilege('authenticated', 'public.quotations', 'INSERT')
  and not has_table_privilege('authenticated', 'public.quotations', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.quotations', 'DELETE')
  and not has_table_privilege('authenticated', 'public.quotation_items', 'INSERT')
  and not has_table_privilege('authenticated', 'public.quotation_items', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.quotation_items', 'DELETE'),
  'historical and 029 read grants are incomplete'
);

select pg_temp.assert_true(
  not has_function_privilege(
    'anon',
    'public.is_active_branch_order_profile()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.is_branch_order_supervisor()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.enforce_branch_order_contract()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.enforce_branch_price_snapshot_parent()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.serialize_branch_order_contract_statement()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.enforce_branch_order_contract()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.enforce_branch_price_snapshot_parent()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.serialize_branch_order_contract_statement()',
    'EXECUTE'
  )
  and not exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) acl
    where p.oid in (
      'public.enforce_branch_order_contract()'::regprocedure,
      'public.enforce_branch_price_snapshot_parent()'::regprocedure,
      'public.serialize_branch_order_contract_statement()'::regprocedure,
      'public.is_active_branch_order_profile()'::regprocedure,
      'public.is_branch_order_supervisor()'::regprocedure
    )
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ),
  '029 function EXECUTE privileges are broader than intended'
);

select pg_temp.assert_true(
  not exists (
    with expected(
      trigger_name,
      table_name,
      trigger_type,
      enabled,
      function_name
    ) as (
      values
        (
          'orders_serialize_branch_contract_029',
          'orders',
          18,
          'O',
          'serialize_branch_order_contract_statement()'
        ),
        (
          'quotations_serialize_branch_contract_029',
          'quotations',
          18,
          'O',
          'serialize_branch_order_contract_statement()'
        ),
        (
          'order_items_serialize_branch_snapshot_update_029',
          'order_items',
          18,
          'O',
          'serialize_branch_order_contract_statement()'
        ),
        (
          'quotation_items_serialize_branch_snapshot_update_029',
          'quotation_items',
          18,
          'O',
          'serialize_branch_order_contract_statement()'
        ),
        (
          'order_items_serialize_branch_snapshot_insert_029',
          'order_items',
          6,
          'O',
          'serialize_branch_order_contract_statement()'
        ),
        (
          'quotation_items_serialize_branch_snapshot_insert_029',
          'quotation_items',
          6,
          'O',
          'serialize_branch_order_contract_statement()'
        )
    ),
    actual as (
      select
        t.tgname::text,
        c.relname::text,
        t.tgtype::integer,
        t.tgenabled::text,
        t.tgfoid::regprocedure::text
      from pg_catalog.pg_trigger t
      join pg_catalog.pg_class c on c.oid = t.tgrelid
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and not t.tgisinternal
        and t.tgname like '%serialize_branch%029'
    )
    (
      select * from expected
      except
      select * from actual
    )
    union all
    (
      select * from actual
      except
      select * from expected
    )
  ),
  '029 statement-level serialization triggers differ from the contract'
);

select pg_temp.assert_true(
  pg_catalog.pg_get_functiondef(
    'public.serialize_branch_order_contract_statement()'::regprocedure
  ) like '%pg_advisory_xact_lock(29, 0)%',
  '029 domain advisory lock keys differ from the contract'
);

select pg_temp.assert_true(
  position(
    'pg_advisory_xact_lock(29, 0)'
    in lower(pg_catalog.pg_get_functiondef(
      'public.commercial_update_document_items(text,jsonb)'::regprocedure
    ))
  ) > 0
  and position(
    'pg_advisory_xact_lock(29, 0)'
    in lower(pg_catalog.pg_get_functiondef(
      'public.commercial_update_document_items(text,jsonb)'::regprocedure
    ))
  ) < position(
    'for update'
    in lower(pg_catalog.pg_get_functiondef(
      'public.commercial_update_document_items(text,jsonb)'::regprocedure
    ))
  ),
  'legacy item RPC does not acquire the protocol lock before FOR UPDATE'
);

select pg_temp.assert_true(
  position(
    'pg_advisory_xact_lock(29, 0)'
    in lower(pg_catalog.pg_get_functiondef(
      'public.convert_quotation_to_order(uuid)'::regprocedure
    ))
  ) > 0
  and position(
    'pg_advisory_xact_lock(29, 0)'
    in lower(pg_catalog.pg_get_functiondef(
      'public.convert_quotation_to_order(uuid)'::regprocedure
    ))
  ) < position(
    'for update'
    in lower(pg_catalog.pg_get_functiondef(
      'public.convert_quotation_to_order(uuid)'::regprocedure
    ))
  ),
  'quotation conversion RPC does not acquire the protocol lock before FOR UPDATE'
);

create temporary table test_029_inventory_baseline on commit drop as
select
  (select count(*) from public.product_branch_stock) as stock_rows,
  (select coalesce(sum(physical_qty), 0) from public.product_branch_stock) as physical_qty,
  (select coalesce(sum(reserved_order_qty), 0) from public.product_branch_stock) as reserved_order_qty,
  (select count(*) from public.stock_movements) as movement_rows,
  (select count(*) from public.product_branch_prices) as price_rows;

select pg_temp.assert_true(
  (select count(*) from public.order_stock_contract_settings) = 1
  and (
    select not order_stock_contract_v1_enabled
    from public.order_stock_contract_settings
    where singleton
  ),
  'V1 feature flag must be a disabled singleton'
);

select pg_temp.assert_true(
  not has_table_privilege('anon', 'public.orders', 'SELECT')
  and not has_table_privilege('anon', 'public.quotations', 'SELECT')
  and not has_table_privilege('anon', 'public.order_stock_contract_settings', 'SELECT')
  and (
    select count(*) = 9
      and bool_and(
        acl.grantor = relation_row.relowner
        and not acl.is_grantable
        and (
          (
            acl.grantee = relation_row.relowner
            and acl.privilege_type in (
              'SELECT',
              'INSERT',
              'UPDATE',
              'DELETE',
              'TRUNCATE',
              'REFERENCES',
              'TRIGGER',
              'MAINTAIN'
            )
          )
          or (
            acl.grantee = 'authenticated'::regrole
            and acl.privilege_type = 'SELECT'
          )
        )
      )
    from pg_class relation_row
    cross join lateral aclexplode(relation_row.relacl) acl
    where relation_row.oid =
      'public.order_stock_contract_settings'::regclass
  )
  and not exists (
    select 1
    from pg_attribute attribute_row
    where attribute_row.attrelid =
      'public.order_stock_contract_settings'::regclass
      and attribute_row.attnum > 0
      and not attribute_row.attisdropped
      and attribute_row.attacl is not null
  ),
  'anon and authenticated flag privileges must be restricted'
);

select pg_temp.assert_true(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name in (
        'branch_id',
        'stock_contract_version',
        'logistics_status',
        'priority',
        'promised_at',
        'operational_version',
        'branch_locked_at',
        'approval_requested_at',
        'price_revalidation_required_at'
      )
  ) = 9,
  'orders contract columns are incomplete'
);

select pg_temp.assert_true(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quotations'
      and column_name in (
        'branch_id',
        'stock_contract_version',
        'priority',
        'promised_at',
        'operational_version'
      )
  ) = 5,
  'quotation contract columns are incomplete'
);

select pg_temp.assert_true(
  position(
    'BRANCH_IMPORT_V2:PRODUCT:'
    in pg_get_functiondef('public.commit_product_import_batch(uuid)'::regprocedure)
  ) > 0
  and position(
    'pg_advisory_xact_lock'
    in pg_get_functiondef('public.commit_product_import_batch(uuid)'::regprocedure)
  ) > 0,
  'migration 028 product lock contract changed or is missing'
);

do $$
declare
  v_pr uuid := (select pr_branch_id from test_029_context);
  v_sqlstate text;
  v_table_name text;
begin
  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority
    )
    values (
      'TEST-029-V1-BLOCKED',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'DRAFT',
      'NORMAL'
    );
    raise exception 'ASSERTION_FAILED: V1 insert was accepted while disabled';
  exception
    when sqlstate '0A000' then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_table_name = table_name;
      if v_sqlstate <> '0A000'
         or sqlerrm <> 'ORDER_STOCK_CONTRACT_V1_DISABLED'
         or v_table_name <> 'orders' then
        raise;
      end if;
  end;
end;
$$;

do $$
declare
  v_constraint_name text;
  v_sqlstate text;
  v_table_name text;
begin
  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      operational_version
    )
    values (
      'TEST-029-V0-BAD-VERSION',
      'PR',
      'TESTE ISOLADO',
      1
    );
    raise exception 'ASSERTION_FAILED: nonzero operational version was accepted in V0';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or v_constraint_name <> 'orders_contract_coherence_check_029'
         or v_table_name <> 'orders' then
        raise;
      end if;
  end;
end;
$$;

insert into auth.users (
  id,
  aud,
  role,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
select admin_id, 'authenticated', 'authenticated', 'test-029-admin@example.invalid',
       '{}'::jsonb, '{}'::jsonb, now(), now()
from test_029_context
union all
select supervisor_id, 'authenticated', 'authenticated', 'test-029-supervisor@example.invalid',
       '{}'::jsonb, '{}'::jsonb, now(), now()
from test_029_context
union all
select seller_id, 'authenticated', 'authenticated', 'test-029-seller@example.invalid',
       '{}'::jsonb, '{}'::jsonb, now(), now()
from test_029_context;

insert into public.profiles (id, usuario, nome, email, perfil, ativo)
select admin_id, 'test_029_admin', 'Test 029 Admin',
       'test-029-admin@example.invalid', 'ADMIN'::public.user_profile, true
from test_029_context
union all
select supervisor_id, 'test_029_supervisor', 'Test 029 Supervisor',
       'test-029-supervisor@example.invalid', 'SUPERVISOR'::public.user_profile, true
from test_029_context
union all
select seller_id, 'test_029_seller', 'Test 029 Seller',
       'test-029-seller@example.invalid', 'VENDEDOR'::public.user_profile, true
from test_029_context;

insert into public.profile_branches (profile_id, branch_id, is_default, active)
select supervisor_id, pr_branch_id, true, true
from test_029_context
union all
select seller_id, pr_branch_id, true, true
from test_029_context;

insert into public.orders (
  numero_pedido,
  regiao,
  user_id,
  cliente
)
select 'TEST-029-V0-ORDER', 'PR', seller_id, 'TESTE ISOLADO'
from test_029_context;

insert into public.quotations (
  numero_cotacao,
  regiao,
  user_id,
  cliente
)
select 'TEST-029-V0-QUOTE', 'SP', seller_id, 'TESTE ISOLADO'
from test_029_context;

select pg_temp.assert_true(
  exists (
    select 1
    from public.orders o
    join public.branches b on b.id = o.branch_id
    where o.numero_pedido = 'TEST-029-V0-ORDER'
      and o.stock_contract_version = 0
      and o.logistics_status = 'LEGACY_UNMANAGED'
      and b.code = 'PR'
  )
  and exists (
    select 1
    from public.quotations q
    join public.branches b on b.id = q.branch_id
    where q.numero_cotacao = 'TEST-029-V0-QUOTE'
      and q.stock_contract_version = 0
      and b.code = 'SP'
  ),
  'V0 defaults or automatic branch mapping failed'
);

insert into public.order_items (
  order_id,
  item,
  codigo,
  quantidade
)
select o.id, 1, c.product_code, 1
from public.orders o
cross join test_029_context c
where o.numero_pedido = 'TEST-029-V0-ORDER';

insert into public.quotation_items (
  quotation_id,
  item,
  codigo,
  quantidade
)
select q.id, 1, c.product_code, 1
from public.quotations q
cross join test_029_context c
where q.numero_cotacao = 'TEST-029-V0-QUOTE';

do $$
declare
  v_order_id uuid := (
    select id from public.orders where numero_pedido = 'TEST-029-V0-ORDER'
  );
  v_quotation_id uuid := (
    select id from public.quotations where numero_cotacao = 'TEST-029-V0-QUOTE'
  );
  v_product text := (select product_code from test_029_context);
  v_constraint_name text;
  v_sqlstate text;
  v_table_name text;
begin
  begin
    insert into public.order_items (order_id, item, codigo, quantidade)
    values (v_order_id, 2, v_product, 1);
    raise exception 'ASSERTION_FAILED: duplicate order product was accepted';
  exception
    when unique_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23505'
         or v_constraint_name <> 'order_items_order_product_unique_029'
         or v_table_name <> 'order_items' then
        raise;
      end if;
  end;

  begin
    insert into public.quotation_items (quotation_id, item, codigo, quantidade)
    values (v_quotation_id, 2, v_product, 1);
    raise exception 'ASSERTION_FAILED: duplicate quotation product was accepted';
  exception
    when unique_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23505'
         or v_constraint_name
            <> 'quotation_items_quotation_product_unique_029'
         or v_table_name <> 'quotation_items' then
        raise;
      end if;
  end;

  begin
    update public.order_items
    set branch_price = 10,
        branch_price_currency = 'BRL',
        branch_price_version = 1,
        branch_price_captured_at = now()
    where order_id = v_order_id;
    raise exception 'ASSERTION_FAILED: a V0 snapshot was accepted';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or sqlerrm <> 'BRANCH_PRICE_SNAPSHOT_REQUIRES_V1'
         or v_table_name <> 'order_items' then
        raise;
      end if;
  end;
end;
$$;

update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = true
where singleton;

do $$
declare
  v_pr uuid := (select pr_branch_id from test_029_context);
  v_constraint_name text;
  v_sqlstate text;
  v_table_name text;
begin
  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      stock_contract_version,
      logistics_status,
      priority
    )
    values (
      'TEST-029-V1-NO-BRANCH',
      'PR',
      'TESTE ISOLADO',
      1,
      'DRAFT',
      'NORMAL'
    );
    raise exception 'ASSERTION_FAILED: V1 order without branch was accepted';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or v_constraint_name <> 'orders_contract_coherence_check_029'
         or v_table_name <> 'orders' then
        raise;
      end if;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority,
      promised_at
    )
    values (
      'TEST-029-V1-BAD-PROMISE',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'DRAFT',
      'NORMAL',
      now() - interval '1 day'
    );
    raise exception 'ASSERTION_FAILED: incoherent promise date was accepted';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or v_constraint_name <> 'orders_contract_dates_check_029'
         or v_table_name <> 'orders' then
        raise;
      end if;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority,
      operational_version
    )
    values (
      'TEST-029-V1-BAD-VERSION',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'DRAFT',
      'NORMAL',
      -1
    );
    raise exception 'ASSERTION_FAILED: negative operational version was accepted';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or v_constraint_name
            <> 'orders_operational_version_check_029'
         or v_table_name <> 'orders' then
        raise;
      end if;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority
    )
    values (
      'TEST-029-V1-BAD-LOGISTICS',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'LEGACY_UNMANAGED',
      'NORMAL'
    );
    raise exception 'ASSERTION_FAILED: V1 legacy logistics was accepted';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or v_constraint_name <> 'orders_contract_coherence_check_029'
         or v_table_name <> 'orders' then
        raise;
      end if;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status,
      priority
    )
    values (
      'TEST-029-V1-BAD-PRIORITY',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      1,
      'DRAFT',
      'INVALID'
    );
    raise exception 'ASSERTION_FAILED: invalid priority was accepted';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or v_constraint_name <> 'orders_priority_check_029'
         or v_table_name <> 'orders' then
        raise;
      end if;
  end;

  begin
    insert into public.orders (
      numero_pedido,
      regiao,
      cliente,
      branch_id,
      stock_contract_version,
      logistics_status
    )
    values (
      'TEST-029-V0-BAD-LOGISTICS',
      'PR',
      'TESTE ISOLADO',
      v_pr,
      0,
      'DRAFT'
    );
    raise exception 'ASSERTION_FAILED: operational logistics was accepted in V0';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_constraint_name = constraint_name,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or v_constraint_name <> 'orders_contract_coherence_check_029'
         or v_table_name <> 'orders' then
        raise;
      end if;
  end;
end;
$$;

insert into public.orders (
  numero_pedido,
  regiao,
  user_id,
  cliente,
  branch_id,
  stock_contract_version,
  logistics_status,
  priority,
  promised_at
)
select 'TEST-029-V1-ADMIN-PR', 'PR'::public.order_region, admin_id, 'TESTE ISOLADO',
       pr_branch_id, 1, 'DRAFT', 'NORMAL', now() + interval '1 day'
from test_029_context
union all
select 'TEST-029-V1-SELLER-PR', 'PR'::public.order_region, seller_id, 'TESTE ISOLADO',
       pr_branch_id, 1, 'DRAFT', 'HIGH', now() + interval '2 days'
from test_029_context
union all
select 'TEST-029-V1-SELLER-SP', 'SP'::public.order_region, seller_id, 'TESTE ISOLADO',
       sp_branch_id, 1, 'DRAFT', 'NORMAL', now() + interval '3 days'
from test_029_context;

insert into public.quotations (
  numero_cotacao,
  regiao,
  user_id,
  cliente,
  branch_id,
  stock_contract_version,
  priority,
  promised_at
)
select 'TEST-029-V1-QUOTE-PR', 'PR', seller_id, 'TESTE ISOLADO',
       pr_branch_id, 1, 'NORMAL', now() + interval '1 day'
from test_029_context;

insert into public.order_items (
  order_id,
  item,
  codigo,
  quantidade,
  branch_price,
  branch_price_currency,
  branch_price_version,
  branch_price_captured_at
)
select o.id, 1, c.product_code, 1, 10, 'BRL', 1, now()
from public.orders o
cross join test_029_context c
where o.numero_pedido like 'TEST-029-V1-%'
  and o.numero_pedido in (
    'TEST-029-V1-ADMIN-PR',
    'TEST-029-V1-SELLER-PR',
    'TEST-029-V1-SELLER-SP'
  );

insert into public.quotation_items (
  quotation_id,
  item,
  codigo,
  quantidade,
  branch_price,
  branch_price_currency,
  branch_price_version,
  branch_price_captured_at
)
select q.id, 1, c.product_code, 1, 10, 'BRL', 1, now()
from public.quotations q
cross join test_029_context c
where q.numero_cotacao = 'TEST-029-V1-QUOTE-PR';

do $$
declare
  v_order_id uuid := (
    select id from public.orders where numero_pedido = 'TEST-029-V1-SELLER-PR'
  );
  v_product text := (select product_code from test_029_context);
  v_sqlstate text;
  v_table_name text;
begin
  begin
    update public.order_items
    set branch_price_currency = null
    where order_id = v_order_id;
    raise exception 'ASSERTION_FAILED: incomplete V1 snapshot was accepted';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or sqlerrm <> 'BRANCH_PRICE_SNAPSHOT_REQUIRED_FOR_V1'
         or v_table_name <> 'order_items' then
        raise;
      end if;
  end;

  begin
    insert into public.order_items (
      order_id,
      item,
      codigo,
      quantidade
    )
    values (v_order_id, 2, v_product, 1);
    raise exception 'ASSERTION_FAILED: missing V1 snapshot was accepted';
  exception
    when check_violation then
      get stacked diagnostics
        v_sqlstate = returned_sqlstate,
        v_table_name = table_name;
      if v_sqlstate <> '23514'
         or sqlerrm <> 'BRANCH_PRICE_SNAPSHOT_REQUIRED_FOR_V1'
         or v_table_name <> 'order_items' then
        raise;
      end if;
  end;
end;
$$;

update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = false
where singleton;

create or replace function pg_temp.assert_commercial_writes_denied(
  claim_id uuid
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
declare
  target_table text;
  statement_sql text;
  v_sqlstate text;
begin
  perform set_config('request.jwt.claim.sub', claim_id::text, true);

  foreach target_table in array array[
    'orders',
    'order_items',
    'quotations',
    'quotation_items'
  ]
  loop
    foreach statement_sql in array array[
      format(
        'insert into public.%I (id) values (%L::uuid)',
        target_table,
        '29000000-0000-4000-8000-000000009999'
      ),
      format(
        'update public.%I set id = id where false',
        target_table
      ),
      format('delete from public.%I where false', target_table)
    ]
    loop
      begin
        execute statement_sql;
        raise exception using
          errcode = 'P0001',
          message = 'ASSERTION_FAILED: authenticated commercial write succeeded',
          detail = target_table || ': ' || statement_sql;
      exception
        when insufficient_privilege then
          get stacked diagnostics v_sqlstate = returned_sqlstate;
          if v_sqlstate <> '42501' then
            raise;
          end if;
      end;
    end loop;
  end loop;
end;
$$;

set local role authenticated;

select pg_temp.assert_commercial_writes_denied(
  (select admin_id from test_029_context)
);
select pg_temp.assert_commercial_writes_denied(
  (select supervisor_id from test_029_context)
);
select pg_temp.assert_commercial_writes_denied(
  (select seller_id from test_029_context)
);

select set_config(
  'request.jwt.claim.sub',
  (select admin_id::text from test_029_context),
  true
);
select pg_temp.assert_true(
  (select count(*) from public.orders where numero_pedido like 'TEST-029-%') = 4,
  'ADMIN must read all test orders'
);
select pg_temp.assert_true(
  (
    select count(*)
    from public.order_items i
    join public.orders o on o.id = i.order_id
    where o.numero_pedido like 'TEST-029-%'
  ) = 4
  and (
    select count(*)
    from public.quotation_items i
    join public.quotations q on q.id = i.quotation_id
    where q.numero_cotacao like 'TEST-029-%'
  ) = 2,
  'ADMIN item visibility must follow all visible test documents'
);
select pg_temp.assert_true(
  (select count(*) from public.order_stock_contract_settings) = 1,
  'ADMIN must read the feature flag'
);

do $$
begin
  begin
    update public.order_stock_contract_settings
    set order_stock_contract_v1_enabled = true
    where singleton;
    raise exception 'ASSERTION_FAILED: authenticated ADMIN wrote the flag directly';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  (select supervisor_id::text from test_029_context),
  true
);
select pg_temp.assert_true(
  (select count(*) from public.orders where numero_pedido like 'TEST-029-V1-%') = 2,
  'SUPERVISOR must read V1 orders only in linked PR branch'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V0-ORDER'
  )
  and not exists (
    select 1
    from public.quotations
    where numero_cotacao = 'TEST-029-V0-QUOTE'
  ),
  'SUPERVISOR must not gain access to legacy V0 documents owned by another user'
);
select pg_temp.assert_true(
  (
    select count(*)
    from public.order_items i
    join public.orders o on o.id = i.order_id
    where o.numero_pedido like 'TEST-029-V1-%'
  ) = 2
  and (
    select count(*)
    from public.quotation_items i
    join public.quotations q on q.id = i.quotation_id
    where q.numero_cotacao = 'TEST-029-V1-QUOTE-PR'
  ) = 1,
  'SUPERVISOR item visibility must follow linked V1 documents'
);
select pg_temp.assert_true(
  (select count(*) from public.order_stock_contract_settings) = 0,
  'SUPERVISOR must not read the feature flag'
);

select set_config(
  'request.jwt.claim.sub',
  (select seller_id::text from test_029_context),
  true
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V0-ORDER'
  ),
  'VENDEDOR must retain own V0 read access'
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V1-SELLER-PR'
  )
  and not exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V1-SELLER-SP'
  )
  and not exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V1-ADMIN-PR'
  ),
  'VENDEDOR V1 access must require ownership and linked branch'
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.quotations
    where numero_cotacao = 'TEST-029-V1-QUOTE-PR'
  ),
  'VENDEDOR must read own V1 quotation in linked branch'
);
select pg_temp.assert_true(
  (
    select count(*)
    from public.order_items i
    join public.orders o on o.id = i.order_id
    where o.numero_pedido like 'TEST-029-%'
  ) = 2
  and (
    select count(*)
    from public.quotation_items i
    join public.quotations q on q.id = i.quotation_id
    where q.numero_cotacao like 'TEST-029-%'
  ) = 2,
  'VENDEDOR item visibility must follow owned and linked documents'
);

reset role;

create or replace function pg_temp.assert_orders_update_denied_by_rls()
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_row_count bigint;
begin
  update public.orders
  set cliente = cliente
  where numero_pedido = 'TEST-029-V0-ORDER';

  get diagnostics v_row_count = row_count;
  if v_row_count <> 0 then
    raise exception
      'ASSERTION_FAILED: RLS allowed a non-owner UPDATE with table grant';
  end if;
end;
$$;

grant update on public.orders to authenticated;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '29000000-0000-4000-8000-000000009998',
  true
);
select pg_temp.assert_orders_update_denied_by_rls();
reset role;
revoke update on public.orders from authenticated;

update public.profiles
set ativo = false
where id = (select seller_id from test_029_context);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  (select seller_id::text from test_029_context),
  true
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-V0-ORDER'
  )
  and not exists (
    select 1
    from public.orders
    where numero_pedido in (
      'TEST-029-V1-SELLER-PR',
      'TEST-029-V1-SELLER-SP'
    )
  ),
  'inactive profile must retain legacy V0 behavior but lose all V1 access'
);
select pg_temp.assert_true(
  (
    select count(*)
    from public.order_items i
    join public.orders o on o.id = i.order_id
    where o.numero_pedido like 'TEST-029-%'
  ) = 1
  and (
    select count(*)
    from public.quotation_items i
    join public.quotations q on q.id = i.quotation_id
    where q.numero_cotacao like 'TEST-029-%'
  ) = 1,
  'inactive VENDEDOR item visibility must be limited to legacy owned documents'
);
reset role;

set local role anon;
do $$
begin
  begin
    perform count(*) from public.order_items;
    raise exception 'ASSERTION_FAILED: anon read order items';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform count(*) from public.quotation_items;
    raise exception 'ASSERTION_FAILED: anon read quotation items';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

select pg_temp.assert_true(
  (
    select row(
      count(*),
      coalesce(sum(physical_qty), 0),
      coalesce(sum(reserved_order_qty), 0)
    )
    from public.product_branch_stock
  ) = (
    select row(stock_rows, physical_qty, reserved_order_qty)
    from test_029_inventory_baseline
  )
  and (
    select count(*) from public.stock_movements
  ) = (
    select movement_rows from test_029_inventory_baseline
  )
  and (
    select count(*) from public.product_branch_prices
  ) = (
    select price_rows from test_029_inventory_baseline
  ),
  '029 tests changed stock, movements, reservations, or branch prices'
);

select 'PASS: migration 029 structural validation' as result;

rollback;

\ir ../rollback/029_branch_order_contract_rollback.sql

do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name in (
           'orders',
           'order_items',
           'quotations',
           'quotation_items'
         )
         and column_name in (
           'stock_contract_version',
           'logistics_status',
           'branch_price'
         )
     )
     or to_regclass('public.product_branch_prices') is null
     or to_regprocedure('public.commit_product_import_batch(uuid)') is null then
    raise exception 'ASSERTION_FAILED: rollback did not isolate 029 from 028';
  end if;

  if (select count(*) from test_029_commercial_policy_baseline) <> 4
     or exists (
       (
         select
           c.relname,
           p.polname,
           p.polpermissive,
           p.polroles,
           p.polcmd,
           coalesce(pg_get_expr(p.polqual, p.polrelid), ''),
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
         from pg_catalog.pg_policy p
         join pg_catalog.pg_class c on c.oid = p.polrelid
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and (c.relname, p.polname) in (
             ('orders', 'orders_read'),
             ('order_items', 'order_items_read'),
             ('quotations', 'quotations_read'),
             ('quotation_items', 'quotation_items_read')
           )
         except
         select * from test_029_commercial_policy_baseline
       )
       union all
       (
         select * from test_029_commercial_policy_baseline
         except
         select
           c.relname,
           p.polname,
           p.polpermissive,
           p.polroles,
           p.polcmd,
           coalesce(pg_get_expr(p.polqual, p.polrelid), ''),
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
         from pg_catalog.pg_policy p
         join pg_catalog.pg_class c on c.oid = p.polrelid
         join pg_catalog.pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and (c.relname, p.polname) in (
             ('orders', 'orders_read'),
             ('order_items', 'order_items_read'),
             ('quotations', 'quotations_read'),
             ('quotation_items', 'quotation_items_read')
           )
       )
     ) then
    raise exception 'ASSERTION_FAILED: rollback did not restore migration 025 policies exactly';
  end if;
end;
$$;

\ir ../migrations/029_branch_order_contract.sql

do $$
begin
  if not exists (
    select 1
    from test_029_compatibility_baseline baseline
    where baseline.import_commit_definition_md5 = md5(pg_get_functiondef(
            'public.commit_product_import_batch(uuid)'::regprocedure
          ))
      and baseline.legacy_stock_sync_definition_md5 = md5(pg_get_functiondef(
            'public.sync_legacy_product_stock_to_pr()'::regprocedure
          ))
      and baseline.stock_rows = (select count(*) from public.product_branch_stock)
      and baseline.physical_qty = (
        select coalesce(sum(physical_qty), 0)
        from public.product_branch_stock
      )
      and baseline.reserved_order_qty = (
        select coalesce(sum(reserved_order_qty), 0)
        from public.product_branch_stock
      )
      and baseline.price_rows = (select count(*) from public.product_branch_prices)
      and baseline.movement_rows = (select count(*) from public.stock_movements)
  ) or exists (
    (select * from public.branches
     except all
     select * from test_029_branches_baseline)
    union all
    (select * from test_029_branches_baseline
     except all
     select * from public.branches)
  ) or exists (
    (select * from public.profile_branches
     except all
     select * from test_029_profile_branches_baseline)
    union all
    (select * from test_029_profile_branches_baseline
     except all
     select * from public.profile_branches)
  ) or exists (
    (select * from public.product_branch_stock
     except all
     select * from test_029_stock_baseline)
    union all
    (select * from test_029_stock_baseline
     except all
     select * from public.product_branch_stock)
  ) or exists (
    (select * from public.product_branch_prices
     except all
     select * from test_029_prices_baseline)
    union all
    (select * from test_029_prices_baseline
     except all
     select * from public.product_branch_prices)
  ) or exists (
    (select * from public.stock_movements
     except all
     select * from test_029_movements_baseline)
    union all
    (select * from test_029_movements_baseline
     except all
     select * from public.stock_movements)
  ) or exists (
    (select * from public.products
     except all
     select * from test_029_products_baseline)
    union all
    (select * from test_029_products_baseline
     except all
     select * from public.products)
  ) or exists (
    (select * from public.products_import_batches
     except all
     select * from test_029_import_batches_baseline)
    union all
    (select * from test_029_import_batches_baseline
     except all
     select * from public.products_import_batches)
  ) or exists (
    (select * from public.products_import_stage
     except all
     select * from test_029_import_stage_baseline)
    union all
    (select * from test_029_import_stage_baseline
     except all
     select * from public.products_import_stage)
  ) or exists (
    (select * from public.products_import_audit
     except all
     select * from test_029_import_audit_baseline)
    union all
    (select * from test_029_import_audit_baseline
     except all
     select * from public.products_import_audit)
  ) or exists (
    (select *
     from public.branch_import_legacy_function_snapshots
     where function_signature <> all(array[
       'public.commercial_update_document_items(text,jsonb)',
       'public.commercial_update_document_status(text,uuid,text)',
       'public.convert_quotation_to_order(uuid)'
     ])
     except all
     select * from test_029_legacy_function_snapshots_baseline)
    union all
    (select * from test_029_legacy_function_snapshots_baseline
     except all
     select *
     from public.branch_import_legacy_function_snapshots
     where function_signature <> all(array[
       'public.commercial_update_document_items(text,jsonb)',
       'public.commercial_update_document_status(text,uuid,text)',
       'public.convert_quotation_to_order(uuid)'
     ]))
  ) or exists (
    (select * from public.branch_import_legacy_table_acl_snapshots
     except all
     select * from test_029_legacy_acl_snapshots_baseline)
    union all
    (select * from test_029_legacy_acl_snapshots_baseline
     except all
     select * from public.branch_import_legacy_table_acl_snapshots)
  ) or exists (
    (select * from test_029_catalog_baseline
     except
     select * from pg_temp.test_029_compatibility_fingerprints())
    union all
    (select * from pg_temp.test_029_compatibility_fingerprints()
     except
     select * from test_029_catalog_baseline)
  ) then
    raise exception 'ASSERTION_FAILED: migration 027 or 028 compatibility changed';
  end if;
end;
$$;

drop table
  test_029_compatibility_baseline,
  test_029_branches_baseline,
  test_029_profile_branches_baseline,
  test_029_stock_baseline,
  test_029_prices_baseline,
  test_029_movements_baseline,
  test_029_products_baseline,
  test_029_import_batches_baseline,
  test_029_import_stage_baseline,
  test_029_import_audit_baseline,
  test_029_legacy_function_snapshots_baseline,
  test_029_legacy_acl_snapshots_baseline,
  test_029_catalog_baseline;

\connect :"test_029_null_db"
alter table public.orders alter column regiao drop not null;
alter table public.quotations alter column regiao drop not null;
insert into public.orders (numero_pedido, regiao, cliente, updated_at)
values
  ('TEST-029-BACKFILL-PR', 'PR', 'TESTE ISOLADO', '2020-01-02 03:04:05+00'),
  ('TEST-029-BACKFILL-SP', 'SP', 'TESTE ISOLADO', '2020-01-02 03:04:05+00'),
  ('TEST-029-BACKFILL-NULL', null, 'TESTE ISOLADO', '2020-01-02 03:04:05+00');
insert into public.quotations (numero_cotacao, regiao, cliente, updated_at)
values
  ('TEST-029-BACKFILL-Q-PR', 'PR', 'TESTE ISOLADO', '2020-01-02 03:04:05+00'),
  ('TEST-029-BACKFILL-Q-SP', 'SP', 'TESTE ISOLADO', '2020-01-02 03:04:05+00'),
  ('TEST-029-BACKFILL-Q-NULL', null, 'TESTE ISOLADO', '2020-01-02 03:04:05+00');
\ir ../migrations/029_branch_order_contract.sql
do $$
begin
  if exists (
    select 1
    from public.orders o
    left join public.branches b on b.id = o.branch_id
    where o.numero_pedido like 'TEST-029-BACKFILL-%'
      and (
        o.stock_contract_version <> 0
        or o.logistics_status <> 'LEGACY_UNMANAGED'
        or o.updated_at <> '2020-01-02 03:04:05+00'::timestamptz
        or (o.regiao = 'PR' and b.code is distinct from 'PR')
        or (o.regiao = 'SP' and b.code is distinct from 'SP')
        or (o.regiao is null and o.branch_id is not null)
      )
  ) or exists (
    select 1
    from public.quotations q
    left join public.branches b on b.id = q.branch_id
    where q.numero_cotacao like 'TEST-029-BACKFILL-Q-%'
      and (
        q.stock_contract_version <> 0
        or q.updated_at <> '2020-01-02 03:04:05+00'::timestamptz
        or (q.regiao = 'PR' and b.code is distinct from 'PR')
        or (q.regiao = 'SP' and b.code is distinct from 'SP')
        or (q.regiao is null and q.branch_id is not null)
      )
  ) then
    raise exception 'ASSERTION_FAILED: PR/SP/NULL backfill or updated_at preservation';
  end if;
end;
$$;

\connect :"test_029_invalid_db"
alter type public.order_region add value 'XX';
insert into public.orders (id, numero_pedido, regiao, cliente)
values (
  '29000000-0000-4000-8000-000000000201'::uuid,
  'TEST-029-INVALID-REGION',
  'XX',
  'TESTE ISOLADO'
);
\setenv PGDATABASE :test_029_invalid_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "23514:" "$log" || ! grep -Fq "MIGRATION_029_UNMAPPABLE_REGION" "$log" || ! grep -Fq "29000000-0000-4000-8000-000000000201:XX" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null then
    raise exception 'ASSERTION_FAILED: invalid region did not abort migration 029';
  end if;
end;
$$;

\connect :"test_029_duplicate_db"
with new_order as (
  insert into public.orders (id, numero_pedido, regiao, cliente)
  values (
    '29000000-0000-4000-8000-000000000202'::uuid,
    'TEST-029-DUPLICATE',
    'PR',
    'TESTE ISOLADO'
  )
  returning id
), product as (
  select codigo
  from public.products
  order by codigo
  limit 1
)
insert into public.order_items (order_id, item, codigo, quantidade)
select new_order.id, 1, product.codigo, 1 from new_order, product
union all
select new_order.id, 2, product.codigo, 1 from new_order, product;
\setenv PGDATABASE :test_029_duplicate_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "23505:" "$log" || ! grep -Fq "MIGRATION_029_DUPLICATE_ORDER_PRODUCTS" "$log" || ! grep -Fq "29000000-0000-4000-8000-000000000202:" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null then
    raise exception 'ASSERTION_FAILED: duplicate product did not abort migration 029';
  end if;
end;
$$;

\connect :"test_029_column_db"
alter table public.orders
  add column stock_contract_version text;
\setenv PGDATABASE :test_029_column_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_COLUMN_FINGERPRINT_MISMATCH" "$log" || ! grep -Fq "public.orders.stock_contract_version" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or not exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
          and table_name = 'orders'
          and column_name = 'stock_contract_version'
          and data_type = 'text'
          and is_nullable = 'YES'
         and column_default is null
     ) then
    raise exception 'ASSERTION_FAILED: incompatible column was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_index_db"
create index order_items_order_product_unique_029
  on public.order_items (id);
\setenv PGDATABASE :test_029_index_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_INDEX_FINGERPRINT_MISMATCH" "$log" || ! grep -Fq "public.order_items_order_product_unique_029" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or pg_get_indexdef(
          'public.order_items_order_product_unique_029'::regclass
        ) not like '% USING btree (id)' then
    raise exception 'ASSERTION_FAILED: incompatible index was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_constraint_db"
alter table public.orders
  add constraint orders_stock_contract_version_check_029
  check (true);
\setenv PGDATABASE :test_029_constraint_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_CONSTRAINT_FINGERPRINT_MISMATCH" "$log" || ! grep -Fq "public.orders.orders_stock_contract_version_check_029" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
declare
  v_definition text;
begin
  select pg_get_constraintdef(c.oid, true)
  into v_definition
  from pg_constraint c
  where c.conrelid = 'public.orders'::regclass
    and c.conname = 'orders_stock_contract_version_check_029';

  if to_regclass('public.order_stock_contract_settings') is not null
     or v_definition <> 'CHECK (true)' then
    raise exception 'ASSERTION_FAILED: incompatible constraint was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_snapshot_tamper_db"
insert into public.branch_import_legacy_function_snapshots (
  function_signature,
  function_name,
  function_definition,
  owner_name,
  acl_state,
  config_state,
  definition_md5
)
values (
  'public.commercial_update_document_items(text,jsonb)',
  'commercial_update_document_items',
  'select 1',
  current_user,
  '<NULL>',
  '<NULL>',
  md5('select 1')
);
\setenv PGDATABASE :test_029_snapshot_tamper_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_LEGACY_COMMERCIAL_SNAPSHOT_COLLISION" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or (
       select count(*)
       from public.branch_import_legacy_function_snapshots
       where function_signature =
         'public.commercial_update_document_items(text,jsonb)'
         and function_definition = 'select 1'
     ) <> 1 then
    raise exception
      'ASSERTION_FAILED: tampered legacy snapshot was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_reapply_forgery_db"
create function public.enforce_branch_order_contract()
returns trigger
language plpgsql
as $$
begin
  return new;
end;
$$;
\setenv PGDATABASE :test_029_reapply_forgery_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_ALREADY_APPLIED_OR_PARTIAL" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regprocedure(
       'public.enforce_branch_order_contract()'
     ) is null
     or to_regclass('public.order_stock_contract_settings') is not null
     or exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'orders'
         and column_name = 'stock_contract_version'
     ) then
    raise exception
      'ASSERTION_FAILED: forged reapplication marker was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_policy_db"
drop policy orders_read on public.orders;
create policy orders_read on public.orders
for select to authenticated
using (true);
drop policy orders_create on public.orders;
create policy orders_create on public.orders
for insert
with check (true);
\setenv PGDATABASE :test_029_policy_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_LEGACY_POLICY_FINGERPRINT_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or (
        select pg_get_expr(p.polqual, p.polrelid)
       from pg_policy p
       where p.polrelid = 'public.orders'::regclass
         and p.polname = 'orders_read'
      ) <> 'true'
     or (
       select pg_get_expr(p.polwithcheck, p.polrelid)
       from pg_policy p
       where p.polrelid = 'public.orders'::regclass
         and p.polname = 'orders_create'
     ) <> 'true' then
    raise exception
      'ASSERTION_FAILED: incompatible legacy policy was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_security_db"
alter table public.orders disable row level security;
grant update (status) on public.orders to authenticated;
grant insert on public.orders to service_role;
create policy test029_extra_orders_read on public.orders
for select to authenticated
using (true);
\setenv PGDATABASE :test_029_security_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_LEGACY_COMMERCIAL_SECURITY_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or (
       select c.relrowsecurity
       from pg_class c
       where c.oid = 'public.orders'::regclass
     )
     or not has_any_column_privilege(
       'authenticated',
       'public.orders',
       'UPDATE'
      )
     or not has_table_privilege(
       'service_role',
       'public.orders',
       'INSERT'
     )
     or not exists (
       select 1
       from pg_policy p
       where p.polrelid = 'public.orders'::regclass
         and p.polname = 'test029_extra_orders_read'
     ) then
    raise exception
      'ASSERTION_FAILED: insecure commercial baseline was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_snapshot_storage_db"
grant truncate on public.branch_import_legacy_function_snapshots
to authenticated;
grant update (captured_at)
on public.branch_import_legacy_function_snapshots
to authenticated;
alter table public.branch_import_legacy_function_snapshots
  add constraint test029_snapshot_extra_check
  check (captured_at is not null);
\setenv PGDATABASE :test_029_snapshot_storage_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_LEGACY_SNAPSHOT_STORAGE_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or not has_table_privilege(
       'authenticated',
       'public.branch_import_legacy_function_snapshots',
       'TRUNCATE'
     )
     or not has_any_column_privilege(
       'authenticated',
       'public.branch_import_legacy_function_snapshots',
       'UPDATE'
     )
     or not exists (
       select 1
       from pg_constraint con
       where con.conrelid =
         'public.branch_import_legacy_function_snapshots'::regclass
         and con.conname = 'test029_snapshot_extra_check'
     ) then
    raise exception
      'ASSERTION_FAILED: insecure snapshot storage was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_helper_db"
create function public.is_active_branch_order_profile()
returns boolean
language sql
stable
as $$
  select true
$$;
\setenv PGDATABASE :test_029_helper_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_ALREADY_APPLIED_OR_PARTIAL" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regprocedure(
       'public.is_active_branch_order_profile()'
     ) is null
     or to_regclass('public.order_stock_contract_settings') is not null then
    raise exception
      'ASSERTION_FAILED: homonymous helper was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_rpc_metadata_db"
grant execute on function
  public.commercial_update_document_items(text, jsonb)
to authenticated;
\setenv PGDATABASE :test_029_rpc_metadata_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_LEGACY_COMMERCIAL_BASELINE_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or not has_function_privilege(
       'authenticated',
       'public.commercial_update_document_items(text,jsonb)',
       'EXECUTE'
     ) then
    raise exception
      'ASSERTION_FAILED: altered RPC ACL was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_trigger_db"
create trigger orders_enforce_branch_contract_029
before update on public.orders
for each row execute function public.touch_updated_at();
\setenv PGDATABASE :test_029_trigger_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_ALREADY_APPLIED_OR_PARTIAL" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or not exists (
       select 1
       from pg_trigger
       where tgrelid = 'public.orders'::regclass
         and tgname = 'orders_enforce_branch_contract_029'
         and not tgisinternal
     ) then
    raise exception
      'ASSERTION_FAILED: reserved homonymous trigger was not rejected atomically';
  end if;
end;
$$;

\connect :"test_029_rollback_manifest_db"
\ir ../migrations/029_branch_order_contract.sql
drop index public.orders_branch_priority_v1_idx_029;
create index orders_branch_priority_v1_idx_029
on public.products (codigo);
\setenv PGDATABASE :test_029_rollback_manifest_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_OBJECT_FINGERPRINT_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null
     or not exists (
       select 1
       from pg_index idx
       join pg_class index_class on index_class.oid = idx.indexrelid
       where index_class.relname = 'orders_branch_priority_v1_idx_029'
         and idx.indrelid = 'public.products'::regclass
     ) then
    raise exception
      'ASSERTION_FAILED: rollback removed a substituted 029 object';
  end if;
end;
$$;

\connect :"test_029_rollback_partial_db"
\ir ../migrations/029_branch_order_contract.sql
alter table public.order_stock_contract_settings
  rename to test029_removed_order_stock_contract_settings;
\setenv PGDATABASE :test_029_rollback_partial_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_PARTIAL_STATE_WITHOUT_SETTINGS" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass(
       'public.test029_removed_order_stock_contract_settings'
     ) is null
     or to_regprocedure(
       'public.serialize_branch_order_contract_statement()'
     ) is null then
    raise exception
      'ASSERTION_FAILED: partial rollback state was not preserved atomically';
  end if;
end;
$$;

\connect :"test_029_rollback_settings_db"
\ir ../migrations/029_branch_order_contract.sql
drop trigger order_stock_contract_settings_touch_updated_at
  on public.order_stock_contract_settings;
create trigger order_stock_contract_settings_touch_updated_at
before update on public.order_stock_contract_settings
for each row execute function public.enforce_branch_order_contract();
\setenv PGDATABASE :test_029_rollback_settings_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_OBJECT_FINGERPRINT_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null
     or not exists (
       select 1
       from pg_trigger
       where tgrelid = 'public.order_stock_contract_settings'::regclass
         and tgname = 'order_stock_contract_settings_touch_updated_at'
         and tgfoid =
           'public.enforce_branch_order_contract()'::regprocedure
     ) then
    raise exception
      'ASSERTION_FAILED: substituted settings trigger was removed';
  end if;
end;
$$;

drop trigger order_stock_contract_settings_touch_updated_at
  on public.order_stock_contract_settings;
create trigger order_stock_contract_settings_touch_updated_at
before update on public.order_stock_contract_settings
for each row execute function public.touch_updated_at();
create trigger order_items_serialize_branch_snapshot_write_029
before update on public.order_items
for each statement
execute function public.serialize_branch_order_contract_statement();
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_OBJECT_FINGERPRINT_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.order_items'::regclass
      and tgname = 'order_items_serialize_branch_snapshot_write_029'
      and not tgisinternal
  ) then
    raise exception
      'ASSERTION_FAILED: reserved compatibility trigger was removed';
  end if;
end;
$$;

drop trigger order_items_serialize_branch_snapshot_write_029
  on public.order_items;
create trigger test029_extra_settings_trigger
before update on public.order_stock_contract_settings
for each row execute function public.touch_updated_at();
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_OBJECT_FINGERPRINT_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgrelid =
      'public.order_stock_contract_settings'::regclass
      and tgname = 'test029_extra_settings_trigger'
      and not tgisinternal
  ) then
    raise exception
      'ASSERTION_FAILED: extra settings trigger was removed';
  end if;
end;
$$;

\connect :"test_029_rollback_constraint_db"
\ir ../migrations/029_branch_order_contract.sql
alter table public.order_stock_contract_settings
  drop constraint order_stock_contract_settings_singleton_check;
alter table public.order_stock_contract_settings
  add constraint order_stock_contract_settings_singleton_check
  check (singleton is not null);
\setenv PGDATABASE :test_029_rollback_constraint_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_OBJECT_FINGERPRINT_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null
     or (
       select pg_get_constraintdef(oid, true)
       from pg_constraint
       where conrelid =
         'public.order_stock_contract_settings'::regclass
         and conname =
           'order_stock_contract_settings_singleton_check'
     ) <> 'CHECK (singleton IS NOT NULL)' then
    raise exception
      'ASSERTION_FAILED: substituted settings constraint was removed';
  end if;
end;
$$;

\connect :"test_029_rollback_unrelated_db"
create schema integration;
create table integration.audit (id bigint);
create index unrelated_029 on integration.audit (id);
\ir ../migrations/029_branch_order_contract.sql
\ir ../rollback/029_branch_order_contract_rollback.sql
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or to_regclass('integration.unrelated_029') is null then
    raise exception
      'ASSERTION_FAILED: unrelated suffixed object affected rollback';
  end if;
end;
$$;

\connect :"test_029_rollback_atomic_db"
\ir ../migrations/029_branch_order_contract.sql
update public.branch_import_legacy_function_snapshots
set function_definition = replace(
      function_definition,
      'SEM_PERMISSAO',
      'SEM_PERMISSAO_ADULTERADA'
    ),
    definition_md5 = md5(replace(
      function_definition,
      'SEM_PERMISSAO',
      'SEM_PERMISSAO_ADULTERADA'
    ))
where function_signature =
  'public.commercial_update_document_status(text,uuid,text)';
\setenv PGDATABASE :test_029_rollback_atomic_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_LEGACY_COMMERCIAL_BASELINE_MISMATCH" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null
     or to_regprocedure(
       'public.serialize_branch_order_contract_statement()'
     ) is null
     or position(
       'pg_advisory_xact_lock(29, 0)'
       in pg_get_functiondef(
         'public.commercial_update_document_items(text,jsonb)'::regprocedure
       )
     ) = 0
     or (
       select count(*)
       from public.branch_import_legacy_function_snapshots
       where function_signature = any(array[
         'public.commercial_update_document_items(text,jsonb)',
         'public.commercial_update_document_status(text,uuid,text)',
         'public.convert_quotation_to_order(uuid)'
       ])
     ) <> 3 then
    raise exception
      'ASSERTION_FAILED: self-consistent tampered rollback snapshot was accepted';
  end if;
end;
$$;

\connect :"test_029_race_db"
\ir ../migrations/029_branch_order_contract.sql
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = true
where singleton;

insert into auth.users (
  id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values (
  '29000000-0000-4000-8000-000000000109'::uuid,
  'authenticated',
  'authenticated',
  'test029-rpc-admin@example.invalid',
  '{}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

insert into public.profiles (
  id, usuario, nome, email, perfil, ativo
)
values (
  '29000000-0000-4000-8000-000000000109'::uuid,
  'test029_rpc_admin',
  'TESTE RPC 029',
  'test029-rpc-admin@example.invalid',
  'ADMIN',
  true
);

grant execute on function
  public.commercial_update_document_items(text, jsonb),
  public.convert_quotation_to_order(uuid)
to authenticated;

insert into public.orders (
  id,
  numero_pedido,
  regiao,
  cliente,
  branch_id,
  stock_contract_version,
  logistics_status,
  priority
)
select
  '29000000-0000-4000-8000-000000000101'::uuid,
  'TEST-029-RACE-ORDER-ITEM-FIRST',
  'PR',
  'TESTE ISOLADO',
  id,
  1,
  'DRAFT',
  'NORMAL'
from public.branches
where code = 'PR';

\setenv PGDATABASE :test_029_race_db
\! sh -c 'item_log=$(mktemp); parent_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$item_log" 2>&1 & item_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; insert into public.order_items (order_id, item, codigo, quantidade, branch_price, branch_price_currency, branch_price_version, branch_price_captured_at) select \$\$29000000-0000-4000-8000-000000000101\$\$::uuid, 1, codigo, 1, 10, \$\$BRL\$\$, 1, now() from public.products order by codigo limit 1; select pg_advisory_xact_lock(29000101);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000101) then not pg_advisory_unlock(29000101) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$item_pid" 2>/dev/null; wait "$item_pid" 2>/dev/null; cat "$item_log"; rm -f "$fifo" "$item_log" "$parent_log"; exit 1; fi; PGAPPNAME=test029_competing_101 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "update public.orders set stock_contract_version = 0, logistics_status = \$\$LEGACY_UNMANAGED\$\$, priority = null where id = \$\$29000000-0000-4000-8000-000000000101\$\$::uuid;" >"$parent_log" 2>&1 & parent_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_competing_101\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$item_pid"; item_rc=$?; wait "$parent_pid"; parent_rc=$?; if [ "$waiting" -ne 1 ] || [ "$item_rc" -ne 0 ] || [ "$parent_rc" -eq 0 ] || ! grep -Fq "23514:" "$parent_log" || ! grep -Fq "SCHEMA NAME:  public" "$parent_log" || ! grep -Fq "TABLE NAME:  orders" "$parent_log" || ! grep -Fq "ORDER_STOCK_CONTRACT_ITEM_SNAPSHOT_MISMATCH" "$parent_log"; then cat "$item_log"; cat "$parent_log"; rm -f "$fifo" "$item_log" "$parent_log"; exit 1; fi; rm -f "$fifo" "$item_log" "$parent_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

do $$
begin
  if not exists (
    select 1
    from public.orders o
    join public.order_items i on i.order_id = o.id
    where o.id = '29000000-0000-4000-8000-000000000101'::uuid
      and o.stock_contract_version = 1
      and o.logistics_status = 'DRAFT'
      and i.branch_price = 10
  ) then
    raise exception 'ASSERTION_FAILED: item-first order race ended incoherently';
  end if;
end;
$$;

insert into public.orders (
  id,
  numero_pedido,
  regiao,
  cliente,
  branch_id,
  stock_contract_version,
  logistics_status,
  priority
)
select
  '29000000-0000-4000-8000-000000000102'::uuid,
  'TEST-029-RACE-ORDER-PARENT-FIRST',
  'PR',
  'TESTE ISOLADO',
  id,
  1,
  'DRAFT',
  'NORMAL'
from public.branches
where code = 'PR';

\! sh -c 'parent_log=$(mktemp); item_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$parent_log" 2>&1 & parent_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; update public.orders set stock_contract_version = 0, logistics_status = \$\$LEGACY_UNMANAGED\$\$, priority = null where id = \$\$29000000-0000-4000-8000-000000000102\$\$::uuid; select pg_advisory_xact_lock(29000102);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000102) then not pg_advisory_unlock(29000102) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$parent_pid" 2>/dev/null; wait "$parent_pid" 2>/dev/null; cat "$parent_log"; rm -f "$fifo" "$parent_log" "$item_log"; exit 1; fi; PGAPPNAME=test029_competing_102 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "insert into public.order_items (order_id, item, codigo, quantidade, branch_price, branch_price_currency, branch_price_version, branch_price_captured_at) select \$\$29000000-0000-4000-8000-000000000102\$\$::uuid, 1, codigo, 1, 10, \$\$BRL\$\$, 1, now() from public.products order by codigo limit 1;" >"$item_log" 2>&1 & item_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_competing_102\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$parent_pid"; parent_rc=$?; wait "$item_pid"; item_rc=$?; if [ "$waiting" -ne 1 ] || [ "$parent_rc" -ne 0 ] || [ "$item_rc" -eq 0 ] || ! grep -Fq "23514:" "$item_log" || ! grep -Fq "SCHEMA NAME:  public" "$item_log" || ! grep -Fq "TABLE NAME:  order_items" "$item_log" || ! grep -Fq "BRANCH_PRICE_SNAPSHOT_REQUIRES_V1" "$item_log"; then cat "$parent_log"; cat "$item_log"; rm -f "$fifo" "$parent_log" "$item_log"; exit 1; fi; rm -f "$fifo" "$parent_log" "$item_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

do $$
begin
  if not exists (
    select 1
    from public.orders
    where id = '29000000-0000-4000-8000-000000000102'::uuid
      and stock_contract_version = 0
      and logistics_status = 'LEGACY_UNMANAGED'
  ) or exists (
    select 1
    from public.order_items
    where order_id = '29000000-0000-4000-8000-000000000102'::uuid
  ) then
    raise exception 'ASSERTION_FAILED: parent-first order race ended incoherently';
  end if;
end;
$$;

insert into public.quotations (
  id, numero_cotacao, regiao, cliente, branch_id,
  stock_contract_version, priority
)
select
  '29000000-0000-4000-8000-000000000103'::uuid,
  'TEST-029-RACE-QUOTE-ITEM-FIRST',
  'PR', 'TESTE ISOLADO', id, 1, 'NORMAL'
from public.branches
where code = 'PR';

insert into public.quotation_items (
  quotation_id, item, codigo, quantidade, branch_price,
  branch_price_currency, branch_price_version, branch_price_captured_at
)
select
  '29000000-0000-4000-8000-000000000103'::uuid,
  1, codigo, 1, 10, 'BRL', 1, now()
from public.products
order by codigo
limit 1;

\! sh -c 'item_log=$(mktemp); parent_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$item_log" 2>&1 & item_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; update public.quotation_items set branch_price = 11 where quotation_id = \$\$29000000-0000-4000-8000-000000000103\$\$::uuid; select pg_advisory_xact_lock(29000103);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000103) then not pg_advisory_unlock(29000103) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$item_pid" 2>/dev/null; wait "$item_pid" 2>/dev/null; cat "$item_log"; rm -f "$fifo" "$item_log" "$parent_log"; exit 1; fi; PGAPPNAME=test029_competing_103 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "update public.quotations set stock_contract_version = 0, priority = null where id = \$\$29000000-0000-4000-8000-000000000103\$\$::uuid;" >"$parent_log" 2>&1 & parent_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_competing_103\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$item_pid"; item_rc=$?; wait "$parent_pid"; parent_rc=$?; if [ "$waiting" -ne 1 ] || [ "$item_rc" -ne 0 ] || [ "$parent_rc" -eq 0 ] || ! grep -Fq "23514:" "$parent_log" || ! grep -Fq "SCHEMA NAME:  public" "$parent_log" || ! grep -Fq "TABLE NAME:  quotations" "$parent_log" || ! grep -Fq "ORDER_STOCK_CONTRACT_ITEM_SNAPSHOT_MISMATCH" "$parent_log"; then cat "$item_log"; cat "$parent_log"; rm -f "$fifo" "$item_log" "$parent_log"; exit 1; fi; rm -f "$fifo" "$item_log" "$parent_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

do $$
begin
  if not exists (
    select 1
    from public.quotations q
    join public.quotation_items i on i.quotation_id = q.id
    where q.id = '29000000-0000-4000-8000-000000000103'::uuid
      and q.stock_contract_version = 1
      and i.branch_price = 11
  ) then
    raise exception 'ASSERTION_FAILED: quotation race ended incoherently';
  end if;
end;
$$;

insert into public.quotations (
  id, numero_cotacao, regiao, cliente, branch_id,
  stock_contract_version, priority
)
select
  '29000000-0000-4000-8000-000000000104'::uuid,
  'TEST-029-RACE-QUOTE-PARENT-FIRST',
  'PR', 'TESTE ISOLADO', id, 1, 'NORMAL'
from public.branches
where code = 'PR';

\! sh -c 'parent_log=$(mktemp); item_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$parent_log" 2>&1 & parent_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; update public.quotations set stock_contract_version = 0, priority = null where id = \$\$29000000-0000-4000-8000-000000000104\$\$::uuid; select pg_advisory_xact_lock(29000104);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000104) then not pg_advisory_unlock(29000104) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$parent_pid" 2>/dev/null; wait "$parent_pid" 2>/dev/null; cat "$parent_log"; rm -f "$fifo" "$parent_log" "$item_log"; exit 1; fi; PGAPPNAME=test029_competing_104 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "insert into public.quotation_items (quotation_id, item, codigo, quantidade, branch_price, branch_price_currency, branch_price_version, branch_price_captured_at) select \$\$29000000-0000-4000-8000-000000000104\$\$::uuid, 1, codigo, 1, 10, \$\$BRL\$\$, 1, now() from public.products order by codigo limit 1;" >"$item_log" 2>&1 & item_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_competing_104\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$parent_pid"; parent_rc=$?; wait "$item_pid"; item_rc=$?; if [ "$waiting" -ne 1 ] || [ "$parent_rc" -ne 0 ] || [ "$item_rc" -eq 0 ] || ! grep -Fq "23514:" "$item_log" || ! grep -Fq "SCHEMA NAME:  public" "$item_log" || ! grep -Fq "TABLE NAME:  quotation_items" "$item_log" || ! grep -Fq "BRANCH_PRICE_SNAPSHOT_REQUIRES_V1" "$item_log"; then cat "$parent_log"; cat "$item_log"; rm -f "$fifo" "$parent_log" "$item_log"; exit 1; fi; rm -f "$fifo" "$parent_log" "$item_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

do $$
begin
  if not exists (
    select 1 from public.quotations
    where id = '29000000-0000-4000-8000-000000000104'::uuid
      and stock_contract_version = 0
  ) or exists (
    select 1 from public.quotation_items
    where quotation_id = '29000000-0000-4000-8000-000000000104'::uuid
  ) then
    raise exception 'ASSERTION_FAILED: parent-first quotation race ended incoherently';
  end if;
end;
$$;

insert into public.orders (
  id, numero_pedido, regiao, cliente, branch_id,
  stock_contract_version, logistics_status, priority
)
select
  fixture.id, fixture.numero_pedido, 'PR', 'TESTE ISOLADO',
  branch.id, 1, 'DRAFT', 'NORMAL'
from public.branches branch
cross join (
  values
    ('29000000-0000-4000-8000-000000000105'::uuid, 'TEST-029-RACE-MOVE-A'),
    ('29000000-0000-4000-8000-000000000106'::uuid, 'TEST-029-RACE-MOVE-B')
) fixture(id, numero_pedido)
where branch.code = 'PR';

with products as (
  select codigo, row_number() over (order by codigo) as position
  from public.products
)
insert into public.order_items (
  order_id, item, codigo, quantidade, branch_price,
  branch_price_currency, branch_price_version, branch_price_captured_at
)
select
  case when products.position = 1
    then '29000000-0000-4000-8000-000000000105'::uuid
    else '29000000-0000-4000-8000-000000000106'::uuid
  end,
  products.position, products.codigo, 1, 10, 'BRL', 1, now()
from products
where products.position <= 2;

\! sh -c 'first_log=$(mktemp); second_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$first_log" 2>&1 & first_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; update public.order_items set order_id = \$\$29000000-0000-4000-8000-000000000106\$\$::uuid where order_id = \$\$29000000-0000-4000-8000-000000000105\$\$::uuid; select pg_advisory_xact_lock(29000105);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000105) then not pg_advisory_unlock(29000105) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$first_pid" 2>/dev/null; wait "$first_pid" 2>/dev/null; cat "$first_log"; rm -f "$fifo" "$first_log" "$second_log"; exit 1; fi; PGAPPNAME=test029_competing_105 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "update public.order_items set order_id = \$\$29000000-0000-4000-8000-000000000105\$\$::uuid where order_id = \$\$29000000-0000-4000-8000-000000000106\$\$::uuid and codigo = (select codigo from public.products order by codigo offset 1 limit 1);" >"$second_log" 2>&1 & second_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_competing_105\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$first_pid"; first_rc=$?; wait "$second_pid"; second_rc=$?; if [ "$waiting" -ne 1 ] || [ "$first_rc" -ne 0 ] || [ "$second_rc" -ne 0 ] || grep -Fq "40P01:" "$first_log" || grep -Fq "40P01:" "$second_log"; then cat "$first_log"; cat "$second_log"; rm -f "$fifo" "$first_log" "$second_log"; exit 1; fi; rm -f "$fifo" "$first_log" "$second_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

do $$
begin
  if (
    select count(*) from public.order_items
    where order_id in (
      '29000000-0000-4000-8000-000000000105'::uuid,
      '29000000-0000-4000-8000-000000000106'::uuid
    )
  ) <> 2 then
    raise exception 'ASSERTION_FAILED: ordered parent swap race ended incoherently';
  end if;
end;
$$;

\! sh -c 'first_log=$(mktemp); second_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$first_log" 2>&1 & first_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; update public.orders set stock_contract_version = stock_contract_version where id = \$\$29000000-0000-4000-8000-000000000105\$\$::uuid; select pg_advisory_xact_lock(29000106);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000106) then not pg_advisory_unlock(29000106) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$first_pid" 2>/dev/null; wait "$first_pid" 2>/dev/null; cat "$first_log"; rm -f "$fifo" "$first_log" "$second_log"; exit 1; fi; PGAPPNAME=test029_mixed_domain_106 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; update public.quotations set stock_contract_version = stock_contract_version where id = \$\$29000000-0000-4000-8000-000000000104\$\$::uuid; update public.orders set stock_contract_version = stock_contract_version where id = \$\$29000000-0000-4000-8000-000000000106\$\$::uuid; commit;" >"$second_log" 2>&1 & second_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_mixed_domain_106\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "update public.quotations set stock_contract_version = stock_contract_version where id = \$\$29000000-0000-4000-8000-000000000103\$\$::uuid;" "commit;" "\\q" >&3; exec 3>&-; wait "$first_pid"; first_rc=$?; wait "$second_pid"; second_rc=$?; if [ "$waiting" -ne 1 ] || [ "$first_rc" -ne 0 ] || [ "$second_rc" -ne 0 ] || grep -Fq "40P01:" "$first_log" || grep -Fq "40P01:" "$second_log"; then cat "$first_log"; cat "$second_log"; rm -f "$fifo" "$first_log" "$second_log"; exit 1; fi; rm -f "$fifo" "$first_log" "$second_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

insert into public.orders (
  id, numero_pedido, regiao, cliente, branch_id,
  stock_contract_version, logistics_status, priority
)
select
  fixture.id, fixture.numero_pedido,
  'PR', 'TESTE ISOLADO', branch.id,
  fixture.contract_version, fixture.logistics_status, fixture.priority
from public.branches branch
cross join (
  values
    (
      '29000000-0000-4000-8000-000000000107'::uuid,
      'TEST-029-RACE-MIXED-INSERT-V0',
      0::smallint, 'LEGACY_UNMANAGED', null::text
    ),
    (
      '29000000-0000-4000-8000-000000000108'::uuid,
      'TEST-029-RACE-MIXED-INSERT-V1',
      1::smallint, 'DRAFT', 'NORMAL'
    )
) fixture(
  id, numero_pedido, contract_version, logistics_status, priority
)
where branch.code = 'PR';

\! sh -c 'transition_log=$(mktemp); insert_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$transition_log" 2>&1 & transition_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; update public.orders set stock_contract_version = 1, logistics_status = \$\$DRAFT\$\$, priority = \$\$NORMAL\$\$ where id = \$\$29000000-0000-4000-8000-000000000107\$\$::uuid; select pg_advisory_xact_lock(29000108);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000108) then not pg_advisory_unlock(29000108) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$transition_pid" 2>/dev/null; wait "$transition_pid" 2>/dev/null; cat "$transition_log"; rm -f "$fifo" "$transition_log" "$insert_log"; exit 1; fi; PGAPPNAME=test029_mixed_insert_108 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "with products as (select codigo, row_number() over (order by codigo) as position from public.products) insert into public.order_items (order_id, item, codigo, quantidade, branch_price, branch_price_currency, branch_price_version, branch_price_captured_at) select case when position = 1 then \$\$29000000-0000-4000-8000-000000000107\$\$::uuid else \$\$29000000-0000-4000-8000-000000000108\$\$::uuid end, position, codigo, 1, case when position = 1 then null else 10 end, case when position = 1 then null else \$\$BRL\$\$ end, case when position = 1 then null else 1 end, case when position = 1 then null else now() end from products where position in (1, 2) order by position;" >"$insert_log" 2>&1 & insert_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_mixed_insert_108\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$transition_pid"; transition_rc=$?; wait "$insert_pid"; insert_rc=$?; if [ "$waiting" -ne 1 ] || [ "$transition_rc" -ne 0 ] || [ "$insert_rc" -eq 0 ] || ! grep -Fq "23514:" "$insert_log" || ! grep -Fq "SCHEMA NAME:  public" "$insert_log" || ! grep -Fq "TABLE NAME:  order_items" "$insert_log" || ! grep -Fq "BRANCH_PRICE_SNAPSHOT_REQUIRED_FOR_V1" "$insert_log" || grep -Fq "40P01:" "$transition_log" || grep -Fq "40P01:" "$insert_log"; then cat "$transition_log"; cat "$insert_log"; rm -f "$fifo" "$transition_log" "$insert_log"; exit 1; fi; rm -f "$fifo" "$transition_log" "$insert_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

do $$
begin
  if (
    select count(*)
    from public.orders o
    where o.id in (
      '29000000-0000-4000-8000-000000000107'::uuid,
      '29000000-0000-4000-8000-000000000108'::uuid
    )
      and o.stock_contract_version = 1
  ) <> 2
  or exists (
    select 1
    from public.order_items i
    where i.order_id in (
      '29000000-0000-4000-8000-000000000107'::uuid,
      '29000000-0000-4000-8000-000000000108'::uuid
    )
  ) then
    raise exception
      'ASSERTION_FAILED: mixed multi-row insert race ended incoherently';
  end if;
end;
$$;

insert into public.orders (
  id, numero_pedido, regiao, user_id, vendedor, cliente, branch_id,
  stock_contract_version, logistics_status
)
select
  '29000000-0000-4000-8000-000000000109'::uuid,
  'TEST-029-RPC-ORDER-V0',
  'PR',
  '29000000-0000-4000-8000-000000000109'::uuid,
  'TESTE RPC 029',
  'TESTE ISOLADO',
  id,
  0,
  'LEGACY_UNMANAGED'
from public.branches
where code = 'PR';

\! sh -c 'transition_log=$(mktemp); rpc_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$transition_log" 2>&1 & transition_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; update public.orders set stock_contract_version = 1, logistics_status = \$\$DRAFT\$\$, priority = \$\$NORMAL\$\$ where id = \$\$29000000-0000-4000-8000-000000000109\$\$::uuid; select pg_advisory_xact_lock(29000109);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000109) then not pg_advisory_unlock(29000109) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$transition_pid" 2>/dev/null; wait "$transition_pid" 2>/dev/null; cat "$transition_log"; rm -f "$fifo" "$transition_log" "$rpc_log"; exit 1; fi; PGAPPNAME=test029_rpc_items_109 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role authenticated; select set_config(\$\$request.jwt.claim.sub\$\$,\$\$29000000-0000-4000-8000-000000000109\$\$,true); select public.commercial_update_document_items(\$\$pedido\$\$,jsonb_build_object(\$\$id\$\$,\$\$29000000-0000-4000-8000-000000000109\$\$,\$\$items\$\$,jsonb_build_array(jsonb_build_object(\$\$codigo\$\$,\$\$TEST-028-CONCURRENT\$\$,\$\$quantidade\$\$,1,\$\$desconto_percentual\$\$,0)))); commit;" >"$rpc_log" 2>&1 & rpc_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_rpc_items_109\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$transition_pid"; transition_rc=$?; wait "$rpc_pid"; rpc_rc=$?; if [ "$waiting" -ne 1 ] || [ "$transition_rc" -ne 0 ] || [ "$rpc_rc" -eq 0 ] || ! grep -Fq "23514:" "$rpc_log" || ! grep -Fq "BRANCH_PRICE_SNAPSHOT_REQUIRED_FOR_V1" "$rpc_log" || grep -Fq "40P01:" "$transition_log" || grep -Fq "40P01:" "$rpc_log"; then cat "$transition_log"; cat "$rpc_log"; rm -f "$fifo" "$transition_log" "$rpc_log"; exit 1; fi; rm -f "$fifo" "$transition_log" "$rpc_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

do $$
begin
  if not exists (
    select 1
    from public.orders
    where id = '29000000-0000-4000-8000-000000000109'::uuid
      and stock_contract_version = 1
  ) or exists (
    select 1
    from public.order_items
    where order_id = '29000000-0000-4000-8000-000000000109'::uuid
  ) then
    raise exception
      'ASSERTION_FAILED: real item RPC race ended incoherently';
  end if;
end;
$$;

insert into public.quotations (
  id, numero_cotacao, regiao, user_id, vendedor, cliente, status
)
values (
  '29000000-0000-4000-8000-000000000110'::uuid,
  'TEST-029-RPC-CONVERT-V0',
  'PR',
  '29000000-0000-4000-8000-000000000109'::uuid,
  'TESTE RPC 029',
  'TESTE ISOLADO',
  'APROVADA'
);

insert into public.quotation_items (
  quotation_id, item, codigo, quantidade, preco_unitario,
  desconto_percentual, preco_final_unitario, total_item
)
select
  '29000000-0000-4000-8000-000000000110'::uuid,
  1, codigo, 1, preco_pr, 0, preco_pr, preco_pr
from public.products
where preco_pr is not null
  and preco_pr >= 0
order by codigo
limit 1;

\! sh -c 'holder_log=$(mktemp); rpc_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$holder_log" 2>&1 & holder_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; select pg_advisory_xact_lock(29,0); update public.quotations set cliente = cliente where id = \$\$29000000-0000-4000-8000-000000000110\$\$::uuid; select pg_advisory_xact_lock(29000110);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000110) then not pg_advisory_unlock(29000110) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$holder_pid" 2>/dev/null; wait "$holder_pid" 2>/dev/null; cat "$holder_log"; rm -f "$fifo" "$holder_log" "$rpc_log"; exit 1; fi; PGAPPNAME=test029_rpc_convert_110 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "begin; set local role authenticated; select set_config(\$\$request.jwt.claim.sub\$\$,\$\$29000000-0000-4000-8000-000000000109\$\$,true); select public.convert_quotation_to_order(\$\$29000000-0000-4000-8000-000000000110\$\$::uuid); commit;" >"$rpc_log" 2>&1 & rpc_pid=$!; waiting=0; for n in $(seq 1 200); do blocked=$(psql -X -U supabase_admin -Atc "select exists (select 1 from pg_stat_activity where application_name = \$\$test029_rpc_convert_110\$\$ and wait_event_type = \$\$Lock\$\$)"); if [ "$blocked" = "t" ]; then waiting=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$holder_pid"; holder_rc=$?; wait "$rpc_pid"; rpc_rc=$?; if [ "$waiting" -ne 1 ] || [ "$holder_rc" -ne 0 ] || [ "$rpc_rc" -ne 0 ] || grep -Fq "40P01:" "$holder_log" || grep -Fq "40P01:" "$rpc_log"; then cat "$holder_log"; cat "$rpc_log"; rm -f "$fifo" "$holder_log" "$rpc_log"; exit 1; fi; rm -f "$fifo" "$holder_log" "$rpc_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif

do $$
begin
  if not exists (
    select 1
    from public.quotation_order_conversions conversion
    where conversion.quotation_id =
      '29000000-0000-4000-8000-000000000110'::uuid
  ) then
    raise exception
      'ASSERTION_FAILED: real quotation conversion RPC did not complete';
  end if;
end;
$$;

\! sh -c 'first_log=$(mktemp); second_log=$(mktemp); fifo=$(mktemp -u); mkfifo "$fifo"; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose <"$fifo" >"$first_log" 2>&1 & first_pid=$!; exec 3>"$fifo"; printf "%s\n" "begin; update public.orders set cliente = cliente where id = \$\$29000000-0000-4000-8000-000000000105\$\$::uuid; select pg_advisory_xact_lock(29000107);" >&3; ready=0; for n in $(seq 1 200); do held=$(psql -X -U supabase_admin -Atc "select case when pg_try_advisory_lock(29000107) then not pg_advisory_unlock(29000107) else true end"); if [ "$held" = "t" ]; then ready=1; break; fi; sleep 0.05; done; if [ "$ready" -ne 1 ]; then exec 3>&-; kill "$first_pid" 2>/dev/null; wait "$first_pid" 2>/dev/null; cat "$first_log"; rm -f "$fifo" "$first_log" "$second_log"; exit 1; fi; PGAPPNAME=test029_parallel_v0_107 psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "update public.quotations set cliente = cliente where id = \$\$29000000-0000-4000-8000-000000000104\$\$::uuid;" >"$second_log" 2>&1 & second_pid=$!; completed=0; for n in $(seq 1 200); do if ! kill -0 "$second_pid" 2>/dev/null; then completed=1; break; fi; sleep 0.05; done; printf "%s\n" "commit;" "\\q" >&3; exec 3>&-; wait "$first_pid"; first_rc=$?; wait "$second_pid"; second_rc=$?; if [ "$completed" -ne 1 ] || [ "$first_rc" -ne 0 ] || [ "$second_rc" -ne 0 ] || grep -Fq "40P01:" "$first_log" || grep -Fq "40P01:" "$second_log"; then cat "$first_log"; cat "$second_log"; rm -f "$fifo" "$first_log" "$second_log"; exit 1; fi; rm -f "$fifo" "$first_log" "$second_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = false
where singleton;

\connect :"test_029_v1_db"
\ir ../migrations/029_branch_order_contract.sql
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = true
where singleton;
insert into public.orders (
  numero_pedido,
  regiao,
  cliente,
  branch_id,
  stock_contract_version,
  logistics_status,
  priority
)
select
  'TEST-029-OPERATIONAL-V1',
  'PR',
  'TESTE ISOLADO',
  id,
  1,
  'DRAFT',
  'NORMAL'
from public.branches
where code = 'PR';
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = false
where singleton;
\setenv PGDATABASE :test_029_v1_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "MIGRATION_029_REAPPLICATION_BLOCKED_ORDER_USE" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null
     or not exists (
       select 1 from public.orders where stock_contract_version = 1
     ) then
    raise exception 'ASSERTION_FAILED: operational use did not block reapplication';
  end if;
end;
$$;
\setenv PGDATABASE :test_029_v1_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_BLOCKED_ORDER_OPERATIONAL_USE" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null
     or not exists (
       select 1 from public.orders where stock_contract_version = 1
     ) then
    raise exception 'ASSERTION_FAILED: V1 did not block rollback';
  end if;
end;
$$;
delete from public.orders where numero_pedido = 'TEST-029-OPERATIONAL-V1';
\ir ../rollback/029_branch_order_contract_rollback.sql

\connect :"test_029_flag_db"
\ir ../migrations/029_branch_order_contract.sql
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = true
where singleton;
\setenv PGDATABASE :test_029_flag_db
\! sh -c 'migration_log=$(mktemp); rollback_log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$migration_log" 2>&1; migration_rc=$?; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$rollback_log" 2>&1; rollback_rc=$?; if [ "$migration_rc" -eq 0 ] || ! grep -Fq "55000:" "$migration_log" || ! grep -Fq "MIGRATION_029_REAPPLICATION_BLOCKED_V1_ENABLED" "$migration_log" || [ "$rollback_rc" -eq 0 ] || ! grep -Fq "55000:" "$rollback_log" || ! grep -Fq "ROLLBACK_029_BLOCKED_V1_ENABLED" "$rollback_log"; then cat "$migration_log"; cat "$rollback_log"; rm -f "$migration_log" "$rollback_log"; exit 1; fi; rm -f "$migration_log" "$rollback_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if not exists (
    select 1
    from public.order_stock_contract_settings
    where singleton
      and order_stock_contract_v1_enabled
  ) then
    raise exception 'ASSERTION_FAILED: feature flag guard did not preserve the blocked database';
  end if;
end;
$$;

\connect :"test_029_quote_db"
\ir ../migrations/029_branch_order_contract.sql
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = true
where singleton;
insert into public.quotations (
  numero_cotacao,
  regiao,
  cliente,
  branch_id,
  stock_contract_version,
  priority
)
select
  'TEST-029-QUOTE-V1-GUARD',
  'PR',
  'TESTE ISOLADO',
  id,
  1,
  'NORMAL'
from public.branches
where code = 'PR';
update public.order_stock_contract_settings
set order_stock_contract_v1_enabled = false
where singleton;
\setenv PGDATABASE :test_029_quote_db
\! sh -c 'migration_log=$(mktemp); rollback_log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$migration_log" 2>&1; migration_rc=$?; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$rollback_log" 2>&1; rollback_rc=$?; if [ "$migration_rc" -eq 0 ] || ! grep -Fq "55000:" "$migration_log" || ! grep -Fq "MIGRATION_029_REAPPLICATION_BLOCKED_QUOTATION_USE" "$migration_log" || [ "$rollback_rc" -eq 0 ] || ! grep -Fq "55000:" "$rollback_log" || ! grep -Fq "ROLLBACK_029_BLOCKED_QUOTATION_OPERATIONAL_USE" "$rollback_log"; then cat "$migration_log"; cat "$rollback_log"; rm -f "$migration_log" "$rollback_log"; exit 1; fi; rm -f "$migration_log" "$rollback_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if not exists (
    select 1
    from public.quotations
    where numero_cotacao = 'TEST-029-QUOTE-V1-GUARD'
      and stock_contract_version = 1
  ) then
    raise exception 'ASSERTION_FAILED: quotation V1 guard lost its fixture';
  end if;
end;
$$;

\connect :"test_029_snapshot_db"
\ir ../migrations/029_branch_order_contract.sql
insert into public.orders (numero_pedido, regiao, cliente)
values ('TEST-029-SNAPSHOT-GUARD', 'PR', 'TESTE ISOLADO');
alter table public.order_items
  disable trigger order_items_enforce_branch_snapshot_029;
insert into public.order_items (
  order_id,
  item,
  codigo,
  quantidade,
  branch_price,
  branch_price_currency,
  branch_price_version,
  branch_price_captured_at
)
select
  o.id,
  1,
  p.codigo,
  1,
  10,
  'BRL',
  1,
  now()
from public.orders o
cross join lateral (
  select codigo from public.products order by codigo limit 1
) p
where o.numero_pedido = 'TEST-029-SNAPSHOT-GUARD';
alter table public.order_items
  enable trigger order_items_enforce_branch_snapshot_029;
\setenv PGDATABASE :test_029_snapshot_db
\! sh -c 'migration_log=$(mktemp); rollback_log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$migration_log" 2>&1; migration_rc=$?; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$rollback_log" 2>&1; rollback_rc=$?; if [ "$migration_rc" -eq 0 ] || ! grep -Fq "55000:" "$migration_log" || ! grep -Fq "MIGRATION_029_REAPPLICATION_BLOCKED_ORDER_SNAPSHOT_USE" "$migration_log" || [ "$rollback_rc" -eq 0 ] || ! grep -Fq "55000:" "$rollback_log" || ! grep -Fq "ROLLBACK_029_BLOCKED_ORDER_SNAPSHOT_USE" "$rollback_log"; then cat "$migration_log"; cat "$rollback_log"; rm -f "$migration_log" "$rollback_log"; exit 1; fi; rm -f "$migration_log" "$rollback_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if not exists (
    select 1
    from public.order_items
    where branch_price is not null
  ) then
    raise exception 'ASSERTION_FAILED: snapshot guard lost its fixture';
  end if;
end;
$$;

\connect :"test_029_version_db"
\ir ../migrations/029_branch_order_contract.sql
alter table public.orders
  drop constraint orders_contract_coherence_check_029;
insert into public.orders (
  numero_pedido,
  regiao,
  cliente,
  operational_version
)
values ('TEST-029-VERSION-GUARD', 'PR', 'TESTE ISOLADO', 1);
\setenv PGDATABASE :test_029_version_db
\! sh -c 'migration_log=$(mktemp); rollback_log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$migration_log" 2>&1; migration_rc=$?; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$rollback_log" 2>&1; rollback_rc=$?; if [ "$migration_rc" -eq 0 ] || ! grep -Fq "55000:" "$migration_log" || ! grep -Fq "MIGRATION_029_REAPPLICATION_BLOCKED_ORDER_USE" "$migration_log" || [ "$rollback_rc" -eq 0 ] || ! grep -Fq "55000:" "$rollback_log" || ! grep -Fq "ROLLBACK_029_BLOCKED_ORDER_OPERATIONAL_USE" "$rollback_log"; then cat "$migration_log"; cat "$rollback_log"; rm -f "$migration_log" "$rollback_log"; exit 1; fi; rm -f "$migration_log" "$rollback_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if not exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-VERSION-GUARD'
      and operational_version = 1
      and stock_contract_version = 0
  ) then
    raise exception 'ASSERTION_FAILED: operational version guard lost its fixture';
  end if;
end;
$$;

\connect :"test_029_logistics_db"
\ir ../migrations/029_branch_order_contract.sql
alter table public.orders
  drop constraint orders_contract_coherence_check_029;
insert into public.orders (
  numero_pedido,
  regiao,
  cliente,
  logistics_status
)
values ('TEST-029-LOGISTICS-GUARD', 'PR', 'TESTE ISOLADO', 'DRAFT');
\setenv PGDATABASE :test_029_logistics_db
\! sh -c 'migration_log=$(mktemp); rollback_log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f migrations/029_branch_order_contract.sql >"$migration_log" 2>&1; migration_rc=$?; psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$rollback_log" 2>&1; rollback_rc=$?; if [ "$migration_rc" -eq 0 ] || ! grep -Fq "55000:" "$migration_log" || ! grep -Fq "MIGRATION_029_REAPPLICATION_BLOCKED_ORDER_USE" "$migration_log" || [ "$rollback_rc" -eq 0 ] || ! grep -Fq "55000:" "$rollback_log" || ! grep -Fq "ROLLBACK_029_BLOCKED_ORDER_OPERATIONAL_USE" "$rollback_log"; then cat "$migration_log"; cat "$rollback_log"; rm -f "$migration_log" "$rollback_log"; exit 1; fi; rm -f "$migration_log" "$rollback_log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if not exists (
    select 1
    from public.orders
    where numero_pedido = 'TEST-029-LOGISTICS-GUARD'
      and logistics_status = 'DRAFT'
      and stock_contract_version = 0
  ) then
    raise exception 'ASSERTION_FAILED: logistics guard lost its fixture';
  end if;
end;
$$;

\connect :"test_029_downstream_db"
\ir ../migrations/029_branch_order_contract.sql
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('030', 'test_029_simulated_downstream', array[]::text[]);
\setenv PGDATABASE :test_029_downstream_db
\! sh -c 'log=$(mktemp); psql -X -U supabase_admin -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f rollback/029_branch_order_contract_rollback.sql >"$log" 2>&1; rc=$?; if [ "$rc" -eq 0 ] || ! grep -Fq "55000:" "$log" || ! grep -Fq "ROLLBACK_029_BLOCKED_DOWNSTREAM_MIGRATION" "$log"; then cat "$log"; rm -f "$log"; exit 1; fi; rm -f "$log"'
\if :SHELL_ERROR
  select 1 / 0;
\endif
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is null then
    raise exception 'ASSERTION_FAILED: downstream migration did not block rollback';
  end if;
end;
$$;
delete from supabase_migrations.schema_migrations
where version = '030'
  and name = 'test_029_simulated_downstream';
\ir ../rollback/029_branch_order_contract_rollback.sql

\connect :"test_029_main_db"
\ir ../rollback/029_branch_order_contract_rollback.sql
\ir ../rollback/029_branch_order_contract_rollback.sql
do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and (table_name, column_name) in (
           values
             ('orders', 'branch_id'),
             ('orders', 'stock_contract_version'),
             ('orders', 'logistics_status'),
             ('orders', 'priority'),
             ('orders', 'promised_at'),
             ('orders', 'operational_version'),
             ('orders', 'branch_locked_at'),
             ('orders', 'approval_requested_at'),
             ('orders', 'price_revalidation_required_at'),
             ('quotations', 'branch_id'),
             ('quotations', 'stock_contract_version'),
             ('quotations', 'priority'),
             ('quotations', 'promised_at'),
             ('quotations', 'operational_version'),
             ('order_items', 'branch_price'),
             ('order_items', 'branch_price_currency'),
             ('order_items', 'branch_price_version'),
             ('order_items', 'branch_price_captured_at'),
             ('quotation_items', 'branch_price'),
             ('quotation_items', 'branch_price_currency'),
             ('quotation_items', 'branch_price_version'),
             ('quotation_items', 'branch_price_captured_at')
         )
     )
     or exists (
       select 1
       from pg_catalog.pg_constraint con
       join pg_catalog.pg_class c on c.oid = con.conrelid
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname in (
           'orders',
           'order_items',
           'quotations',
           'quotation_items'
         )
         and con.conname like '%\_029' escape '\'
     )
     or exists (
       select 1
       from pg_catalog.pg_class c
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relkind = 'i'
         and c.relname like '%\_029' escape '\'
     )
     or exists (
       select 1
       from pg_catalog.pg_trigger t
       join pg_catalog.pg_class c on c.oid = t.tgrelid
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and not t.tgisinternal
         and t.tgname like '%\_029' escape '\'
     )
     or to_regprocedure(
       'public.serialize_branch_order_contract_statement()'
     ) is not null
     or to_regprocedure('public.enforce_branch_order_contract()') is not null
     or to_regprocedure(
       'public.enforce_branch_price_snapshot_parent()'
     ) is not null
     or to_regprocedure(
       'public.is_active_branch_order_profile()'
     ) is not null
     or to_regprocedure(
       'public.is_branch_order_supervisor()'
     ) is not null
  then
    raise exception 'ASSERTION_FAILED: repeated rollback did not restore 028';
  end if;

end;
$$;

do $$
declare
  v_differences jsonb;
begin
  with differences as (
    (
      select
        'missing_or_changed'::text as difference,
        baseline.*
      from public.test_029_commercial_legacy_baseline baseline
      except
      select
        'missing_or_changed',
        current.*
      from public.test_029_commercial_legacy_fingerprints() current
    )
    union all
    (
      select
        'unexpected_or_changed',
        current.*
      from public.test_029_commercial_legacy_fingerprints() current
      except
      select
        'unexpected_or_changed',
        baseline.*
      from public.test_029_commercial_legacy_baseline baseline
    )
  )
  select jsonb_agg(to_jsonb(differences) order by difference, category, object_identity)
  into v_differences
  from differences;

  if v_differences is not null then
    raise exception using
      errcode = '55000',
      message = 'ASSERTION_FAILED: rollback did not restore individual legacy commercial objects',
      detail = v_differences::text;
  end if;
end;
$$;

select (
  md5(string_agg(
    concat_ws(
      '|',
      c.relname,
      p.polname,
      p.polpermissive,
      p.polroles::text,
      p.polcmd,
      coalesce(pg_get_expr(p.polqual, p.polrelid), ''),
      coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
    ),
    E'\n'
    order by c.relname, p.polname
  )) = :'test_029_policy_baseline_md5'
  and count(*) = 4
) as test_029_repeated_policies_match
from pg_catalog.pg_policy p
join pg_catalog.pg_class c on c.oid = p.polrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and (c.relname, p.polname) in (
    ('orders', 'orders_read'),
    ('order_items', 'order_items_read'),
    ('quotations', 'quotations_read'),
    ('quotation_items', 'quotation_items_read')
  )
\gset

\if :test_029_repeated_policies_match
\else
  select 1 / 0;
\endif

\connect postgres
drop database :"test_029_main_db" with (force);
drop database :"test_029_null_db" with (force);
drop database :"test_029_invalid_db" with (force);
drop database :"test_029_duplicate_db" with (force);
drop database :"test_029_v1_db" with (force);
drop database :"test_029_downstream_db" with (force);
drop database :"test_029_race_db" with (force);
drop database :"test_029_column_db" with (force);
drop database :"test_029_index_db" with (force);
drop database :"test_029_constraint_db" with (force);
drop database :"test_029_flag_db" with (force);
drop database :"test_029_quote_db" with (force);
drop database :"test_029_snapshot_db" with (force);
drop database :"test_029_snapshot_tamper_db" with (force);
drop database :"test_029_reapply_forgery_db" with (force);
drop database :"test_029_policy_db" with (force);
drop database :"test_029_security_db" with (force);
drop database :"test_029_helper_db" with (force);
drop database :"test_029_rpc_metadata_db" with (force);
drop database :"test_029_snapshot_storage_db" with (force);
drop database :"test_029_rollback_manifest_db" with (force);
drop database :"test_029_rollback_atomic_db" with (force);
drop database :"test_029_trigger_db" with (force);
drop database :"test_029_rollback_partial_db" with (force);
drop database :"test_029_rollback_settings_db" with (force);
drop database :"test_029_rollback_constraint_db" with (force);
drop database :"test_029_rollback_unrelated_db" with (force);
drop database :"test_029_version_db" with (force);
drop database :"test_029_logistics_db" with (force);
\connect :"test_029_source_db"
\setenv PGDATABASE :test_029_source_db

do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null
     or not exists (
       select 1
       from supabase_migrations.schema_migrations
       where version = '028'
     )
     or exists (
       select 1
       from supabase_migrations.schema_migrations
       where version ~ '^[0-9]+$'
         and version::numeric > 28
     ) then
    raise exception 'ASSERTION_FAILED: source database was modified by suite 029';
  end if;
end;
$$;

select 'PASS: all migration 029 lifecycle scenarios; disposable databases removed' as result;
