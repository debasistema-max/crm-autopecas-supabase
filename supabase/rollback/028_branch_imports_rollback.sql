begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

create temporary table branch_import_rollback_context
on commit drop
as
select pr_branch_id, sp_branch_id
from public.resolve_branch_import_initial_branches();

do $context_guard$
begin
  if (select count(*) from branch_import_rollback_context) <> 1 then
    raise exception using
      errcode = 'P2805',
      message = 'BRANCH_IDENTITIES_INVALID';
  end if;
end
$context_guard$;

create temporary table branch_import_rollback_columns (
  table_oid oid not null,
  column_attnum smallint not null,
  primary key (table_oid, column_attnum)
) on commit drop;

insert into branch_import_rollback_columns (table_oid, column_attnum)
select a.attrelid, a.attnum
from pg_attribute a
where (a.attrelid, a.attname) in (
  values
    ('public.products_import_batches'::regclass, 'branch_id'),
    ('public.products_import_batches'::regclass, 'mode'),
    ('public.products_import_batches'::regclass, 'contract_version'),
    ('public.products_import_batches'::regclass, 'field_mask'),
    ('public.products_import_batches'::regclass, 'client_file_hash'),
    ('public.products_import_batches'::regclass, 'normalized_file_hash'),
    ('public.products_import_batches'::regclass, 'normalization_algorithm'),
    ('public.products_import_batches'::regclass, 'hash_algorithm'),
    ('public.products_import_batches'::regclass, 'idempotency_key'),
    ('public.products_import_batches'::regclass, 'state'),
    ('public.products_import_batches'::regclass, 'created_by_profile_id'),
    ('public.products_import_batches'::regclass, 'approved_by_profile_id'),
    ('public.products_import_batches'::regclass, 'committed_by_profile_id'),
    ('public.products_import_batches'::regclass, 'previewed_at'),
    ('public.products_import_batches'::regclass, 'committed_at'),
    ('public.products_import_batches'::regclass, 'last_attempt_started_at'),
    ('public.products_import_batches'::regclass, 'last_attempt_completed_at'),
    ('public.products_import_batches'::regclass, 'last_failure_code'),
    ('public.products_import_batches'::regclass, 'last_failure_details'),
    ('public.products_import_batches'::regclass, 'last_failure_at'),
    ('public.products_import_batches'::regclass, 'attempt_count'),
    ('public.products_import_batches'::regclass, 'staging_revision'),
    ('public.products_import_batches'::regclass, 'rollback_status'),
    ('public.products_import_batches'::regclass, 'rollback_summary'),
    ('public.products_import_batches'::regclass, 'rollback_started_at'),
    ('public.products_import_batches'::regclass, 'rollback_completed_at'),
    ('public.products_import_batches'::regclass, 'rollback_requested_by'),
    ('public.products_import_stage'::regclass, 'normalized_code'),
    ('public.products_import_stage'::regclass, 'provided_fields'),
    ('public.products_import_stage'::regclass, 'field_mask'),
    ('public.products_import_stage'::regclass, 'row_hash'),
    ('public.products_import_stage'::regclass, 'planned_action'),
    ('public.products_import_stage'::regclass, 'product_before'),
    ('public.products_import_stage'::regclass, 'product_after'),
    ('public.products_import_stage'::regclass, 'stock_before'),
    ('public.products_import_stage'::regclass, 'stock_after'),
    ('public.products_import_stage'::regclass, 'price_before'),
    ('public.products_import_stage'::regclass, 'price_after'),
    ('public.products_import_stage'::regclass, 'product_version'),
    ('public.products_import_stage'::regclass, 'stock_version'),
    ('public.products_import_stage'::regclass, 'price_version'),
    ('public.products_import_stage'::regclass, 'physical_delta'),
    ('public.products_import_stage'::regclass, 'blocking_errors'),
    ('public.products_import_stage'::regclass, 'ignored_fields'),
    ('public.products_import_audit'::regclass, 'stage_id'),
    ('public.products_import_audit'::regclass, 'branch_id'),
    ('public.products_import_audit'::regclass, 'entity_type'),
    ('public.products_import_audit'::regclass, 'version_before'),
    ('public.products_import_audit'::regclass, 'version_after'),
    ('public.products_import_audit'::regclass, 'stock_movement_id'),
    ('public.products_import_audit'::regclass, 'rollback_action'),
    ('public.products_import_audit'::regclass, 'rollback_status'),
    ('public.products_import_audit'::regclass, 'rollback_details')
);

do $guard$
declare
  v_pr uuid;
  v_sp uuid;
begin
  select pr_branch_id, sp_branch_id into strict v_pr, v_sp
  from branch_import_rollback_context;

  if exists (
    select 1 from public.products_import_batches
    where contract_version >= 1 and state = 'COMMITTED'
  ) then
    raise exception 'ROLLBACK_028_BLOQUEADO: existe lote V2 confirmado';
  end if;

  if exists (
    select 1 from public.stock_movements where source = 'BRANCH_IMPORT_V2'
  ) then
    raise exception 'ROLLBACK_028_BLOQUEADO: existem movimentos V2';
  end if;

  if exists (
    select 1 from public.products_import_audit
    where entity_type is not null or rollback_status is not null
  ) then
    raise exception 'ROLLBACK_028_BLOQUEADO: existe auditoria V2';
  end if;

  if exists (
    select 1 from public.products_import_batches
    where rollback_status <> 'NOT_REQUESTED'
  ) then
    raise exception 'ROLLBACK_028_BLOQUEADO: existe rollback operacional';
  end if;

  if exists (
    select 1 from public.product_branch_prices
    where source <> 'LEGACY_BACKFILL'
       or source_batch_id is not null
       or version > 1
  ) then
    raise exception 'ROLLBACK_028_BLOQUEADO: existem precos operacionais';
  end if;

  if exists (
    select 1
    from public.product_branch_prices bp
    join public.products p on p.codigo = bp.product_code
    where (bp.branch_id = v_pr and bp.sale_price is distinct from p.preco_pr)
       or (bp.branch_id = v_sp and bp.sale_price is distinct from p.preco_sp)
       or bp.branch_id not in (v_pr, v_sp)
  ) then
    raise exception 'ROLLBACK_028_BLOQUEADO: backfill diverge do preco legado';
  end if;
end
$guard$;

do $dependencies$
declare
  v_blockers text[];
begin
  select array_agg(blocker order by blocker)
  into v_blockers
  from (
    select distinct format(
      '%s %I.%I',
      case c.relkind when 'm' then 'materialized view' else 'view' end,
      n.nspname,
      c.relname
    ) as blocker
    from pg_depend d
    join pg_rewrite r
      on d.classid = 'pg_rewrite'::regclass
     and d.objid = r.oid
    join pg_class c on c.oid = r.ev_class
    join pg_namespace n on n.oid = c.relnamespace
    where d.refclassid = 'pg_class'::regclass
      and (
        d.refobjid in (
          'public.product_branch_prices'::regclass,
          'public.branch_import_legacy_function_snapshots'::regclass,
          'public.branch_import_legacy_table_acl_snapshots'::regclass
        )
        or exists (
          select 1
          from branch_import_rollback_columns rollback_column
          where rollback_column.table_oid = d.refobjid
            and rollback_column.column_attnum = d.refobjsubid
        )
      )
      and c.relkind in ('v', 'm')

    union

    select distinct format(
      'function %I.%I(%s)',
      n.nspname,
      p.proname,
      pg_get_function_identity_arguments(p.oid)
    )
    from pg_depend d
    join pg_proc p
      on d.classid = 'pg_proc'::regclass
     and d.objid = p.oid
    join pg_namespace n on n.oid = p.pronamespace
    where (
      (
        d.refclassid = 'pg_class'::regclass
        and (
          d.refobjid in (
            'public.product_branch_prices'::regclass,
            'public.branch_import_legacy_function_snapshots'::regclass,
            'public.branch_import_legacy_table_acl_snapshots'::regclass
          )
          or exists (
            select 1
            from branch_import_rollback_columns rollback_column
            where rollback_column.table_oid = d.refobjid
              and rollback_column.column_attnum = d.refobjsubid
          )
        )
      ) or (
        d.refclassid = 'pg_proc'::regclass
        and d.refobjid in (
          'public.branch_import_allowed_fields(text)'::regprocedure,
          'public.normalize_branch_import_mask(text,text[])'::regprocedure,
          'public.canonicalize_branch_import_data(text[],jsonb)'::regprocedure,
          'public.compute_product_import_staging_hash(uuid)'::regprocedure,
          'public.create_product_import_batch(jsonb)'::regprocedure,
          'public.stage_product_import_rows(uuid,jsonb)'::regprocedure,
          'public.reset_product_import_batch_to_draft(uuid)'::regprocedure,
          'public.preview_product_import_batch(uuid)'::regprocedure,
          'public.approve_product_import_batch(uuid)'::regprocedure,
           'public.commit_product_import_batch(uuid)'::regprocedure,
           'public.get_allowed_import_branches()'::regprocedure,
           'public.can_access_product_import_batch_row(integer,uuid,uuid,text,boolean,boolean,boolean)'::regprocedure,
           'public.create_products_import_batch_v0_impl(jsonb)'::regprocedure,
           'public.preview_products_import_batch_v0_impl(uuid)'::regprocedure,
           'public.approve_products_import_batch_v0_impl(uuid)'::regprocedure,
           'public.commit_products_import_batch_v0_impl(uuid)'::regprocedure,
           'public.get_products_import_batches_report_v0_impl(jsonb)'::regprocedure,
           'public.get_products_import_batch_details_v0_impl(uuid,integer,integer)'::regprocedure
        )
      )
    )
    and p.oid not in (
      'public.touch_product_branch_price()'::regprocedure,
      'public.sync_legacy_product_prices_to_branches()'::regprocedure,
      'public.resolve_branch_import_initial_branches()'::regprocedure,
      'public.branch_import_allowed_fields(text)'::regprocedure,
      'public.normalize_branch_import_mask(text,text[])'::regprocedure,
      'public.canonicalize_branch_import_data(text[],jsonb)'::regprocedure,
      'public.compute_product_import_staging_hash(uuid)'::regprocedure,
      'public.create_product_import_batch(jsonb)'::regprocedure,
      'public.stage_product_import_rows(uuid,jsonb)'::regprocedure,
      'public.reset_product_import_batch_to_draft(uuid)'::regprocedure,
      'public.preview_product_import_batch(uuid)'::regprocedure,
      'public.approve_product_import_batch(uuid)'::regprocedure,
      'public.commit_product_import_batch(uuid)'::regprocedure,
      'public.get_allowed_import_branches()'::regprocedure,
      'public.can_access_product_import_batch_row(integer,uuid,uuid,text,boolean,boolean,boolean)'::regprocedure,
      'public.create_products_import_batch(jsonb)'::regprocedure,
      'public.preview_products_import_batch(uuid)'::regprocedure,
      'public.approve_products_import_batch(uuid)'::regprocedure,
      'public.commit_products_import_batch(uuid)'::regprocedure,
      'public.get_products_import_batches_report(jsonb)'::regprocedure,
      'public.get_products_import_batch_details(uuid,integer,integer)'::regprocedure,
      'public.create_products_import_batch_v0_impl(jsonb)'::regprocedure,
      'public.preview_products_import_batch_v0_impl(uuid)'::regprocedure,
      'public.approve_products_import_batch_v0_impl(uuid)'::regprocedure,
      'public.commit_products_import_batch_v0_impl(uuid)'::regprocedure,
      'public.get_products_import_batches_report_v0_impl(jsonb)'::regprocedure,
      'public.get_products_import_batch_details_v0_impl(uuid,integer,integer)'::regprocedure,
      'public.sync_legacy_product_stock_to_pr()'::regprocedure
    )

    union

    select format(
      'foreign key %I on %I.%I',
      con.conname,
      n.nspname,
      c.relname
    )
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where con.contype = 'f'
      and con.confrelid = 'public.product_branch_prices'::regclass

    union

    select format('trigger %I on %I.%I', t.tgname, n.nspname, c.relname)
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and t.tgfoid in (
        'public.touch_product_branch_price()'::regprocedure,
        'public.sync_legacy_product_prices_to_branches()'::regprocedure
      )
      and not (
        t.tgrelid = 'public.product_branch_prices'::regclass
        and t.tgname = 'product_branch_prices_touch'
      )
      and not (
        t.tgrelid = 'public.products'::regclass
        and t.tgname = 'products_sync_legacy_prices_to_branches'
      )

    union

    select format('policy %I on %I.%I', pol.polname, n.nspname, c.relname)
    from pg_depend d
    join pg_policy pol
      on d.classid = 'pg_policy'::regclass
     and d.objid = pol.oid
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where d.refclassid in ('pg_class'::regclass, 'pg_proc'::regclass)
      and (
        d.refobjid = 'public.product_branch_prices'::regclass
        or d.refobjid in (
          'public.create_product_import_batch(jsonb)'::regprocedure,
          'public.stage_product_import_rows(uuid,jsonb)'::regprocedure,
          'public.reset_product_import_batch_to_draft(uuid)'::regprocedure,
          'public.preview_product_import_batch(uuid)'::regprocedure,
          'public.approve_product_import_batch(uuid)'::regprocedure,
          'public.commit_product_import_batch(uuid)'::regprocedure,
          'public.get_allowed_import_branches()'::regprocedure
        )
      )
      and not (
        (pol.polrelid = 'public.product_branch_prices'::regclass
          and pol.polname = 'product_branch_prices_scoped_read')
        or (pol.polrelid = 'public.products_import_batches'::regclass
          and pol.polname = 'products_import_batches_read')
        or (pol.polrelid = 'public.products_import_stage'::regclass
          and pol.polname = 'products_import_stage_read')
        or (pol.polrelid = 'public.products_import_audit'::regclass
          and pol.polname = 'products_import_audit_read')
      )

    union

    select format('constraint %I on %I.%I', con.conname, n.nspname, c.relname)
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where con.conrelid in (
        'public.products_import_batches'::regclass,
        'public.products_import_stage'::regclass,
        'public.products_import_audit'::regclass
      )
      and con.conname not in (
        'products_import_batches_branch_id_fkey',
        'products_import_batches_created_by_profile_id_fkey',
        'products_import_batches_approved_by_profile_id_fkey',
        'products_import_batches_committed_by_profile_id_fkey',
        'products_import_batches_rollback_requested_by_fkey',
        'products_import_batches_contract_check',
        'products_import_batches_state_check',
        'products_import_batches_rollback_check',
        'products_import_batches_v2_required_check',
        'products_import_batches_attempt_check',
        'products_import_batches_staging_revision_check',
        'products_import_stage_action_check',
        'products_import_audit_stage_id_fkey',
        'products_import_audit_branch_id_fkey',
        'products_import_audit_stock_movement_id_fkey'
      )
      and exists (
        select 1
        from unnest(coalesce(con.conkey, '{}'::smallint[])) key(attnum)
        join pg_attribute a
          on a.attrelid = con.conrelid
         and a.attnum = key.attnum
        where a.attname in (
          'branch_id', 'mode', 'contract_version', 'field_mask',
          'client_file_hash', 'normalized_file_hash', 'normalization_algorithm',
          'hash_algorithm', 'idempotency_key', 'state',
          'created_by_profile_id', 'approved_by_profile_id',
          'committed_by_profile_id', 'previewed_at', 'committed_at',
          'last_attempt_started_at', 'last_attempt_completed_at',
          'last_failure_code', 'last_failure_details', 'last_failure_at',
          'attempt_count', 'staging_revision', 'rollback_status',
          'rollback_summary', 'rollback_started_at', 'rollback_completed_at',
          'rollback_requested_by', 'normalized_code', 'provided_fields',
          'row_hash', 'planned_action', 'product_before', 'product_after',
          'stock_before', 'stock_after', 'price_before', 'price_after',
          'product_version', 'stock_version', 'price_version',
          'physical_delta', 'blocking_errors', 'ignored_fields', 'stage_id',
          'entity_type', 'version_before', 'version_after',
          'stock_movement_id', 'rollback_action', 'rollback_details'
        )
      )

    union

    select format('index %I.%I', n.nspname, idx.relname)
    from pg_index i
    join pg_class idx on idx.oid = i.indexrelid
    join pg_namespace n on n.oid = idx.relnamespace
    where i.indrelid in (
        'public.products_import_batches'::regclass,
        'public.products_import_stage'::regclass,
        'public.products_import_audit'::regclass
      )
      and idx.relname not in (
        'products_import_batches_v2_idempotency_idx',
        'products_import_batches_branch_state_idx',
        'products_import_stage_v2_code_idx',
        'products_import_stage_v2_row_idx',
        'products_import_audit_stage_idx',
        'products_import_audit_movement_idx'
      )
      and exists (
        select 1
        from unnest(i.indkey::smallint[]) key(attnum)
        join pg_attribute a
          on a.attrelid = i.indrelid
         and a.attnum = key.attnum
        where a.attname in (
          'branch_id', 'mode', 'contract_version', 'field_mask',
          'client_file_hash', 'normalized_file_hash', 'normalization_algorithm',
          'hash_algorithm', 'idempotency_key', 'state',
          'created_by_profile_id', 'approved_by_profile_id',
          'committed_by_profile_id', 'previewed_at', 'committed_at',
          'last_attempt_started_at', 'last_attempt_completed_at',
          'last_failure_code', 'last_failure_details', 'last_failure_at',
          'attempt_count', 'staging_revision', 'rollback_status',
          'rollback_summary', 'rollback_started_at', 'rollback_completed_at',
          'rollback_requested_by', 'normalized_code', 'provided_fields',
          'row_hash', 'planned_action', 'product_before', 'product_after',
          'stock_before', 'stock_after', 'price_before', 'price_after',
          'product_version', 'stock_version', 'price_version',
          'physical_delta', 'blocking_errors', 'ignored_fields', 'stage_id',
          'entity_type', 'version_before', 'version_after',
          'stock_movement_id', 'rollback_action', 'rollback_details'
        )
      )

    union

    select format(
      'function body %I.%I(%s)',
      n.nspname,
      p.proname,
      pg_get_function_identity_arguments(p.oid)
    )
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      and p.oid not in (
        'public.touch_product_branch_price()'::regprocedure,
        'public.sync_legacy_product_prices_to_branches()'::regprocedure,
        'public.resolve_branch_import_initial_branches()'::regprocedure,
        'public.branch_import_allowed_fields(text)'::regprocedure,
        'public.normalize_branch_import_mask(text,text[])'::regprocedure,
        'public.canonicalize_branch_import_data(text[],jsonb)'::regprocedure,
        'public.compute_product_import_staging_hash(uuid)'::regprocedure,
        'public.can_access_product_import_batch_row(integer,uuid,uuid,text,boolean,boolean,boolean)'::regprocedure,
        'public.create_product_import_batch(jsonb)'::regprocedure,
        'public.stage_product_import_rows(uuid,jsonb)'::regprocedure,
        'public.reset_product_import_batch_to_draft(uuid)'::regprocedure,
        'public.preview_product_import_batch(uuid)'::regprocedure,
        'public.approve_product_import_batch(uuid)'::regprocedure,
        'public.commit_product_import_batch(uuid)'::regprocedure,
        'public.get_allowed_import_branches()'::regprocedure,
        'public.sync_legacy_product_stock_to_pr()'::regprocedure,
        'public.create_products_import_batch(jsonb)'::regprocedure,
        'public.preview_products_import_batch(uuid)'::regprocedure,
        'public.approve_products_import_batch(uuid)'::regprocedure,
        'public.commit_products_import_batch(uuid)'::regprocedure,
        'public.get_products_import_batches_report(jsonb)'::regprocedure,
        'public.get_products_import_batch_details(uuid,integer,integer)'::regprocedure,
        'public.create_products_import_batch_v0_impl(jsonb)'::regprocedure,
        'public.preview_products_import_batch_v0_impl(uuid)'::regprocedure,
        'public.approve_products_import_batch_v0_impl(uuid)'::regprocedure,
        'public.commit_products_import_batch_v0_impl(uuid)'::regprocedure,
        'public.get_products_import_batches_report_v0_impl(jsonb)'::regprocedure,
        'public.get_products_import_batch_details_v0_impl(uuid,integer,integer)'::regprocedure
      )
      and (
        lower(coalesce(p.prosrc, '')) ~ (
          'product_branch_prices'
          '|branch_import_legacy_function_snapshots'
          '|branch_import_legacy_table_acl_snapshots'
          '|can_access_product_import_batch_row'
          '|create_product_import_batch'
          '|stage_product_import_rows'
          '|reset_product_import_batch_to_draft'
          '|preview_product_import_batch'
          '|approve_product_import_batch'
          '|commit_product_import_batch'
          '|get_allowed_import_branches'
        )
        or (
          lower(coalesce(p.prosrc, '')) ~ 'products_import_batches'
          and lower(coalesce(p.prosrc, '')) ~ (
            'branch_id|mode|contract_version|field_mask|client_file_hash'
            '|normalized_file_hash|normalization_algorithm|hash_algorithm'
            '|idempotency_key|created_by_profile_id|staging_revision'
            '|rollback_status|last_attempt_started_at|last_failure_code'
          )
        )
        or (
          lower(coalesce(p.prosrc, '')) ~ 'products_import_stage'
          and lower(coalesce(p.prosrc, '')) ~ (
            'normalized_code|provided_fields|row_hash|planned_action'
            '|product_before|stock_before|price_before|physical_delta'
            '|blocking_errors|ignored_fields'
          )
        )
        or (
          lower(coalesce(p.prosrc, '')) ~ 'products_import_audit'
          and lower(coalesce(p.prosrc, '')) ~ (
            'stage_id|branch_id|entity_type|version_before'
            '|stock_movement_id|rollback_action|rollback_status'
          )
        )
      )

    union

    select format('policy expression %I on %I.%I', pol.polname, n.nspname, c.relname)
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not (
        (pol.polrelid = 'public.product_branch_prices'::regclass
          and pol.polname = 'product_branch_prices_scoped_read')
        or (pol.polrelid = 'public.products_import_batches'::regclass
          and pol.polname = 'products_import_batches_read')
        or (pol.polrelid = 'public.products_import_stage'::regclass
          and pol.polname = 'products_import_stage_read')
        or (pol.polrelid = 'public.products_import_audit'::regclass
          and pol.polname = 'products_import_audit_read')
      )
      and (
        lower(
          coalesce(pg_get_expr(pol.polqual, pol.polrelid), '')
          || ' '
          || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '')
        ) ~ (
          'product_branch_prices'
          '|branch_import_legacy_function_snapshots'
          '|branch_import_legacy_table_acl_snapshots'
          '|can_access_product_import_batch_row'
          '|create_product_import_batch'
          '|stage_product_import_rows'
          '|reset_product_import_batch_to_draft'
          '|preview_product_import_batch'
          '|approve_product_import_batch'
          '|commit_product_import_batch'
          '|get_allowed_import_branches'
        )
        or (
          pol.polrelid = 'public.products_import_batches'::regclass
          and lower(
            coalesce(pg_get_expr(pol.polqual, pol.polrelid), '')
            || ' '
            || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '')
          ) ~ (
            'branch_id|mode|contract_version|field_mask'
            '|normalized_file_hash|staging_revision|rollback_status'
          )
        )
        or (
          pol.polrelid = 'public.products_import_stage'::regclass
          and lower(
            coalesce(pg_get_expr(pol.polqual, pol.polrelid), '')
            || ' '
            || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '')
          ) ~ (
            'normalized_code|provided_fields|row_hash|planned_action'
            '|blocking_errors|ignored_fields'
          )
        )
        or (
          pol.polrelid = 'public.products_import_audit'::regclass
          and lower(
            coalesce(pg_get_expr(pol.polqual, pol.polrelid), '')
            || ' '
            || coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '')
          ) ~ (
            'stage_id|branch_id|entity_type|stock_movement_id'
            '|rollback_action|rollback_status'
          )
        )
      )

    union

    select format('%s definition %I.%I',
      case c.relkind when 'm' then 'materialized view' else 'view' end,
      n.nspname,
      c.relname
    )
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('v', 'm')
      and (
        lower(pg_get_viewdef(c.oid, true)) ~ (
          'product_branch_prices'
          '|branch_import_legacy_function_snapshots'
          '|branch_import_legacy_table_acl_snapshots'
          '|can_access_product_import_batch_row'
        )
        or (
          lower(pg_get_viewdef(c.oid, true)) ~ 'products_import_batches'
          and lower(pg_get_viewdef(c.oid, true)) ~ (
            'branch_id|mode|contract_version|field_mask'
            '|normalized_file_hash|staging_revision|rollback_status'
          )
        )
        or (
          lower(pg_get_viewdef(c.oid, true)) ~ 'products_import_stage'
          and lower(pg_get_viewdef(c.oid, true)) ~ (
            'normalized_code|provided_fields|row_hash|planned_action'
            '|blocking_errors|ignored_fields'
          )
        )
        or (
          lower(pg_get_viewdef(c.oid, true)) ~ 'products_import_audit'
          and lower(pg_get_viewdef(c.oid, true)) ~ (
            'stage_id|branch_id|entity_type|stock_movement_id'
            '|rollback_action|rollback_status'
          )
        )
      )

    union

    select format('trigger definition %I on %I.%I', t.tgname, n.nspname, c.relname)
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and not (
        (c.oid = 'public.product_branch_prices'::regclass
          and t.tgname = 'product_branch_prices_touch')
        or (c.oid = 'public.products'::regclass
          and t.tgname = 'products_sync_legacy_prices_to_branches')
        or (
          c.oid = 'public.products'::regclass
          and t.tgname in (
            'products_insert_sync_legacy_stock_to_pr',
            'products_update_sync_legacy_stock_to_pr'
          )
        )
      )
      and (
        lower(pg_get_triggerdef(t.oid, true)) ~ (
          'product_branch_prices'
          '|branch_import_legacy_function_snapshots'
          '|branch_import_legacy_table_acl_snapshots'
          '|can_access_product_import_batch_row'
          '|create_product_import_batch'
          '|stage_product_import_rows'
          '|reset_product_import_batch_to_draft'
          '|preview_product_import_batch'
          '|approve_product_import_batch'
          '|commit_product_import_batch'
        )
        or (
          c.oid = 'public.products_import_batches'::regclass
          and lower(pg_get_triggerdef(t.oid, true)) ~ (
            'branch_id|mode|contract_version|field_mask'
            '|normalized_file_hash|staging_revision|rollback_status'
          )
        )
        or (
          c.oid = 'public.products_import_stage'::regclass
          and lower(pg_get_triggerdef(t.oid, true)) ~ (
            'normalized_code|provided_fields|row_hash|planned_action'
            '|blocking_errors|ignored_fields'
          )
        )
        or (
          c.oid = 'public.products_import_audit'::regclass
          and lower(pg_get_triggerdef(t.oid, true)) ~ (
            'stage_id|branch_id|entity_type|stock_movement_id'
            '|rollback_action|rollback_status'
          )
        )
      )

    union

    select format('default %I.%I.%I', n.nspname, c.relname, a.attname)
    from pg_attrdef ad
    join pg_class c on c.oid = ad.adrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a
      on a.attrelid = ad.adrelid
     and a.attnum = ad.adnum
    where not (
        c.oid in (
          'public.products_import_batches'::regclass,
          'public.products_import_stage'::regclass,
          'public.products_import_audit'::regclass,
          'public.product_branch_prices'::regclass,
          'public.branch_import_legacy_function_snapshots'::regclass,
          'public.branch_import_legacy_table_acl_snapshots'::regclass
        )
      )
      and lower(pg_get_expr(ad.adbin, ad.adrelid)) ~ (
        'product_branch_prices'
        '|branch_import_legacy_function_snapshots'
        '|branch_import_legacy_table_acl_snapshots'
        '|can_access_product_import_batch_row'
        '|create_product_import_batch'
        '|stage_product_import_rows'
        '|reset_product_import_batch_to_draft'
        '|preview_product_import_batch'
        '|approve_product_import_batch'
        '|commit_product_import_batch'
        '|get_allowed_import_branches'
      )

    union

    select format('event trigger %I via %I.%I', et.evtname, n.nspname, p.proname)
    from pg_event_trigger et
    join pg_proc p on p.oid = et.evtfoid
    join pg_namespace n on n.oid = p.pronamespace
    where (
      lower(coalesce(p.prosrc, '')) ~ (
        'product_branch_prices'
        '|branch_import_legacy_function_snapshots'
        '|branch_import_legacy_table_acl_snapshots'
        '|can_access_product_import_batch_row'
        '|create_product_import_batch'
        '|stage_product_import_rows'
        '|reset_product_import_batch_to_draft'
        '|preview_product_import_batch'
        '|approve_product_import_batch'
        '|commit_product_import_batch'
        '|get_allowed_import_branches'
      )
      or (
        lower(coalesce(p.prosrc, '')) ~ 'products_import_batches'
        and lower(coalesce(p.prosrc, '')) ~ (
          'branch_id|mode|contract_version|field_mask'
          '|normalized_file_hash|staging_revision|rollback_status'
        )
      )
      or (
        lower(coalesce(p.prosrc, '')) ~ 'products_import_stage'
        and lower(coalesce(p.prosrc, '')) ~ (
          'normalized_code|provided_fields|row_hash|planned_action'
          '|blocking_errors|ignored_fields'
        )
      )
      or (
        lower(coalesce(p.prosrc, '')) ~ 'products_import_audit'
        and lower(coalesce(p.prosrc, '')) ~ (
          'stage_id|branch_id|entity_type|stock_movement_id'
          '|rollback_action|rollback_status'
        )
      )
    )
  ) blockers;

  if coalesce(cardinality(v_blockers), 0) > 0 then
    raise exception using
      errcode = 'P2830',
      message = 'ROLLBACK_028_DEPENDENCIAS_EXTERNAS',
      detail = array_to_string(v_blockers, E'\n');
  end if;
end
$dependencies$;

do $restore_legacy_functions$
declare
  v_snapshot record;
  v_owner name;
  v_acl text;
  v_config text;
  v_restored_md5 text;
begin
  if (
    select count(*)
    from public.branch_import_legacy_function_snapshots
  ) <> 6 then
    raise exception using
      errcode = 'P2831',
      message = 'ROLLBACK_028_LEGACY_SNAPSHOT_INCOMPLETE';
  end if;

  for v_snapshot in
    select *
    from public.branch_import_legacy_function_snapshots
    order by function_signature
  loop
    select
      owner_role.rolname,
      coalesce(p.proacl::text, '<NULL>'),
      coalesce(p.proconfig::text, '<NULL>')
    into strict v_owner, v_acl, v_config
    from pg_proc p
    join pg_roles owner_role on owner_role.oid = p.proowner
    where p.oid = to_regprocedure(v_snapshot.function_signature);

    if v_owner is distinct from v_snapshot.owner_name
       or v_acl is distinct from v_snapshot.acl_state
       or v_config is distinct from v_snapshot.config_state then
      raise exception using
        errcode = 'P2831',
        message = 'ROLLBACK_028_LEGACY_FUNCTION_SECURITY_DIVERGED';
    end if;

    execute v_snapshot.function_definition;

    select md5(pg_get_functiondef(to_regprocedure(v_snapshot.function_signature)))
    into v_restored_md5;

    if v_restored_md5 is distinct from v_snapshot.definition_md5 then
      raise exception using
        errcode = 'P2831',
        message = 'ROLLBACK_028_LEGACY_FUNCTION_RESTORE_DIVERGED';
    end if;
  end loop;
end
$restore_legacy_functions$;

revoke all on function
  public.create_products_import_batch_v0_impl(jsonb),
  public.preview_products_import_batch_v0_impl(uuid),
  public.approve_products_import_batch_v0_impl(uuid),
  public.commit_products_import_batch_v0_impl(uuid),
  public.get_products_import_batches_report_v0_impl(jsonb),
  public.get_products_import_batch_details_v0_impl(uuid, integer, integer)
from public, anon, authenticated;

drop function public.create_products_import_batch_v0_impl(jsonb);
drop function public.preview_products_import_batch_v0_impl(uuid);
drop function public.approve_products_import_batch_v0_impl(uuid);
drop function public.commit_products_import_batch_v0_impl(uuid);
drop function public.get_products_import_batches_report_v0_impl(jsonb);
drop function public.get_products_import_batch_details_v0_impl(uuid, integer, integer);

drop policy if exists products_import_audit_read on public.products_import_audit;
create policy products_import_audit_read
on public.products_import_audit
for select
using (public.can_view_products_import_batches());

drop policy if exists products_import_stage_read on public.products_import_stage;
create policy products_import_stage_read
on public.products_import_stage
for select
using (public.can_view_products_import_batches());

drop policy if exists products_import_batches_read on public.products_import_batches;
create policy products_import_batches_read
on public.products_import_batches
for select
using (public.can_view_products_import_batches());

do $restore_legacy_table_acls$
declare
  v_snapshot record;
  v_current_owner name;
  v_acl record;
  v_grantee_sql text;
  v_grantor_sql text;
  v_current_raw_md5 text;
begin
  if (
    select count(*)
    from public.branch_import_legacy_table_acl_snapshots
    where table_name in (
      'public.products_import_batches',
      'public.products_import_stage',
      'public.products_import_audit'
    )
  ) <> 3 then
    raise exception using
      errcode = 'P2832',
      message = 'ROLLBACK_028_LEGACY_TABLE_ACL_SNAPSHOT_INCOMPLETE';
  end if;

  for v_snapshot in
    select *
    from public.branch_import_legacy_table_acl_snapshots
    order by table_name
  loop
    select owner_role.rolname
    into strict v_current_owner
    from pg_class c
    join pg_roles owner_role on owner_role.oid = c.relowner
    where c.oid = v_snapshot.table_name::regclass;

    if v_current_owner is distinct from v_snapshot.owner_name then
      raise exception using
        errcode = 'P2832',
        message = 'ROLLBACK_028_LEGACY_TABLE_OWNER_DIVERGED',
        detail = v_snapshot.table_name;
    end if;

    for v_acl in
      select distinct exploded.grantee
      from pg_class c
      cross join lateral aclexplode(
        coalesce(c.relacl, '{}'::aclitem[])
      ) exploded
      where c.oid = v_snapshot.table_name::regclass
    loop
      v_grantee_sql := case
        when v_acl.grantee = 0 then 'public'
        else format('%I', pg_get_userbyid(v_acl.grantee))
      end;

      execute format(
        'revoke all privileges on table %s from %s cascade',
        v_snapshot.table_name,
        v_grantee_sql
      );
    end loop;

    for v_acl in
      select
        exploded.grantor,
        exploded.grantee,
        exploded.privilege_type,
        exploded.is_grantable
      from aclexplode(v_snapshot.effective_acl_state) exploded
      order by
        exploded.grantee,
        exploded.grantor,
        exploded.privilege_type,
        exploded.is_grantable
    loop
      if v_acl.privilege_type not in (
        'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
        'REFERENCES', 'TRIGGER', 'MAINTAIN'
      ) then
        raise exception using
          errcode = 'P2832',
          message = 'ROLLBACK_028_LEGACY_TABLE_ACL_PRIVILEGE_UNKNOWN',
          detail = v_acl.privilege_type;
      end if;

      v_grantee_sql := case
        when v_acl.grantee = 0 then 'public'
        else format('%I', pg_get_userbyid(v_acl.grantee))
      end;
      v_grantor_sql := format('%I', pg_get_userbyid(v_acl.grantor));

      execute format(
        'grant %s on table %s to %s%s granted by %s',
        v_acl.privilege_type,
        v_snapshot.table_name,
        v_grantee_sql,
        case when v_acl.is_grantable then ' with grant option' else '' end,
        v_grantor_sql
      );
    end loop;

    if exists (
      (
        select
          expected.grantor,
          expected.grantee,
          expected.privilege_type,
          expected.is_grantable
        from aclexplode(v_snapshot.effective_acl_state) expected
        except
        select
          actual.grantor,
          actual.grantee,
          actual.privilege_type,
          actual.is_grantable
        from pg_class c
        cross join lateral aclexplode(
          coalesce(c.relacl, acldefault('r', c.relowner))
        ) actual
        where c.oid = v_snapshot.table_name::regclass
      )
      union all
      (
        select
          actual.grantor,
          actual.grantee,
          actual.privilege_type,
          actual.is_grantable
        from pg_class c
        cross join lateral aclexplode(
          coalesce(c.relacl, acldefault('r', c.relowner))
        ) actual
        where c.oid = v_snapshot.table_name::regclass
        except
        select
          expected.grantor,
          expected.grantee,
          expected.privilege_type,
          expected.is_grantable
        from aclexplode(v_snapshot.effective_acl_state) expected
      )
    ) then
      raise exception using
        errcode = 'P2832',
        message = 'ROLLBACK_028_LEGACY_TABLE_ACL_RESTORE_DIVERGED',
        detail = v_snapshot.table_name;
    end if;

    select md5(coalesce(c.relacl::text, '<NULL>'))
    into strict v_current_raw_md5
    from pg_class c
    where c.oid = v_snapshot.table_name::regclass;

    if v_snapshot.raw_acl_state is not null
       and v_current_raw_md5 is distinct from v_snapshot.raw_acl_md5 then
      raise exception using
        errcode = 'P2832',
        message = 'ROLLBACK_028_LEGACY_TABLE_RELACL_RESTORE_DIVERGED',
        detail = v_snapshot.table_name;
    end if;
  end loop;
end
$restore_legacy_table_acls$;

revoke all on function
  public.create_product_import_batch(jsonb),
  public.stage_product_import_rows(uuid, jsonb),
  public.reset_product_import_batch_to_draft(uuid),
  public.preview_product_import_batch(uuid),
  public.approve_product_import_batch(uuid),
  public.commit_product_import_batch(uuid),
  public.get_allowed_import_branches()
from public, anon, authenticated;

drop function if exists public.create_product_import_batch(jsonb);
drop function if exists public.stage_product_import_rows(uuid, jsonb);
drop function if exists public.reset_product_import_batch_to_draft(uuid);
drop function if exists public.preview_product_import_batch(uuid);
drop function if exists public.approve_product_import_batch(uuid);
drop function if exists public.commit_product_import_batch(uuid);
drop function if exists public.get_allowed_import_branches();

revoke all on function public.can_access_product_import_batch_row(
  integer, uuid, uuid, text, boolean, boolean, boolean
) from public, anon, authenticated;
drop function public.can_access_product_import_batch_row(
  integer, uuid, uuid, text, boolean, boolean, boolean
);

revoke all on function
  public.branch_import_allowed_fields(text),
  public.normalize_branch_import_mask(text, text[]),
  public.canonicalize_branch_import_data(text[], jsonb),
  public.compute_product_import_staging_hash(uuid)
from public, anon, authenticated;

drop function if exists public.compute_product_import_staging_hash(uuid);
drop function if exists public.canonicalize_branch_import_data(text[], jsonb);
drop function if exists public.normalize_branch_import_mask(text, text[]);
drop function if exists public.branch_import_allowed_fields(text);

drop trigger if exists products_sync_legacy_prices_to_branches on public.products;
revoke all on function public.sync_legacy_product_prices_to_branches()
from public, anon, authenticated;
drop function if exists public.sync_legacy_product_prices_to_branches();

drop policy if exists product_branch_prices_scoped_read on public.product_branch_prices;
revoke all on public.product_branch_prices from public, anon, authenticated;
drop trigger if exists product_branch_prices_touch on public.product_branch_prices;
revoke all on function public.touch_product_branch_price() from public, anon, authenticated;
drop function if exists public.touch_product_branch_price();
drop table if exists public.product_branch_prices;

revoke all on public.branch_import_legacy_function_snapshots
from public, anon, authenticated;
drop table public.branch_import_legacy_function_snapshots;

revoke all on public.branch_import_legacy_table_acl_snapshots
from public, anon, authenticated;
drop table public.branch_import_legacy_table_acl_snapshots;

drop index if exists public.products_import_audit_movement_idx;
drop index if exists public.products_import_audit_stage_idx;
drop index if exists public.products_import_stage_v2_row_idx;
drop index if exists public.products_import_stage_v2_code_idx;
drop index if exists public.products_import_batches_branch_state_idx;
drop index if exists public.products_import_batches_v2_idempotency_idx;

alter table public.products_import_audit
  drop column if exists rollback_details,
  drop column if exists rollback_status,
  drop column if exists rollback_action,
  drop column if exists stock_movement_id,
  drop column if exists version_after,
  drop column if exists version_before,
  drop column if exists entity_type,
  drop column if exists branch_id,
  drop column if exists stage_id;

alter table public.products_import_stage
  drop constraint if exists products_import_stage_action_check,
  drop column if exists ignored_fields,
  drop column if exists blocking_errors,
  drop column if exists physical_delta,
  drop column if exists price_version,
  drop column if exists stock_version,
  drop column if exists product_version,
  drop column if exists price_after,
  drop column if exists price_before,
  drop column if exists stock_after,
  drop column if exists stock_before,
  drop column if exists product_after,
  drop column if exists product_before,
  drop column if exists planned_action,
  drop column if exists row_hash,
  drop column if exists field_mask,
  drop column if exists provided_fields,
  drop column if exists normalized_code;

alter table public.products_import_batches
  drop constraint if exists products_import_batches_staging_revision_check,
  drop constraint if exists products_import_batches_attempt_check,
  drop constraint if exists products_import_batches_v2_required_check,
  drop constraint if exists products_import_batches_rollback_check,
  drop constraint if exists products_import_batches_state_check,
  drop constraint if exists products_import_batches_contract_check,
  drop column if exists rollback_requested_by,
  drop column if exists rollback_completed_at,
  drop column if exists rollback_started_at,
  drop column if exists rollback_summary,
  drop column if exists rollback_status,
  drop column if exists attempt_count,
  drop column if exists staging_revision,
  drop column if exists last_failure_at,
  drop column if exists last_failure_details,
  drop column if exists last_failure_code,
  drop column if exists last_attempt_completed_at,
  drop column if exists last_attempt_started_at,
  drop column if exists committed_at,
  drop column if exists previewed_at,
  drop column if exists committed_by_profile_id,
  drop column if exists approved_by_profile_id,
  drop column if exists created_by_profile_id,
  drop column if exists state,
  drop column if exists idempotency_key,
  drop column if exists hash_algorithm,
  drop column if exists normalization_algorithm,
  drop column if exists normalized_file_hash,
  drop column if exists client_file_hash,
  drop column if exists field_mask,
  drop column if exists contract_version,
  drop column if exists mode,
  drop column if exists branch_id;

create or replace function public.sync_legacy_product_stock_to_pr()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pr_branch_id uuid;
  v_sp_branch_id uuid;
  v_old_qty numeric(14,3) := case when tg_op = 'INSERT' then 0 else old.estoque_quantidade end;
  v_new_qty numeric(14,3) := coalesce(new.estoque_quantidade, 0);
  v_before jsonb;
  v_after jsonb;
begin
  if v_new_qty < 0 then
    raise exception 'ESTOQUE_LEGADO_NEGATIVO';
  end if;

  select id into v_pr_branch_id from public.branches where code = 'PR';
  select id into v_sp_branch_id from public.branches where code = 'SP';

  if v_pr_branch_id is null or v_sp_branch_id is null then
    raise exception 'FILIAIS_INICIAIS_NAO_CRIADAS';
  end if;

  insert into public.product_branch_stock (product_code, branch_id, physical_qty, updated_by)
  values (new.codigo, v_sp_branch_id, 0, auth.uid())
  on conflict (product_code, branch_id) do nothing;

  select jsonb_build_object(
    'physical_qty', s.physical_qty,
    'reserved_order_qty', s.reserved_order_qty,
    'reserved_transfer_qty', s.reserved_transfer_qty,
    'in_transit_qty', s.in_transit_qty,
    'quarantined_qty', s.quarantined_qty
  )
  into v_before
  from public.product_branch_stock s
  where s.product_code = new.codigo
    and s.branch_id = v_pr_branch_id
  for update;

  if v_before is null then
    v_before := jsonb_build_object(
      'physical_qty', 0,
      'reserved_order_qty', 0,
      'reserved_transfer_qty', 0,
      'in_transit_qty', 0,
      'quarantined_qty', 0
    );

    insert into public.product_branch_stock (
      product_code, branch_id, physical_qty, updated_by
    )
    values (
      new.codigo, v_pr_branch_id, v_new_qty, auth.uid()
    );
  elsif v_old_qty is distinct from v_new_qty then
    update public.product_branch_stock s
    set physical_qty = v_new_qty,
        updated_by = auth.uid()
    where s.product_code = new.codigo
      and s.branch_id = v_pr_branch_id;
  end if;

  if v_old_qty is not distinct from v_new_qty then
    return new;
  end if;

  select jsonb_build_object(
    'physical_qty', s.physical_qty,
    'reserved_order_qty', s.reserved_order_qty,
    'reserved_transfer_qty', s.reserved_transfer_qty,
    'in_transit_qty', s.in_transit_qty,
    'quarantined_qty', s.quarantined_qty
  )
  into v_after
  from public.product_branch_stock s
  where s.product_code = new.codigo
    and s.branch_id = v_pr_branch_id;

  insert into public.stock_movements (
    branch_id,
    product_code,
    movement_type,
    physical_delta,
    balance_before,
    balance_after,
    source,
    reference_type,
    idempotency_key,
    created_by,
    metadata
  )
  values (
    v_pr_branch_id,
    new.codigo,
    'IMPORTACAO_ESTOQUE',
    v_new_qty - v_old_qty,
    v_before,
    v_after,
    'LEGACY_PRODUCTS_SYNC',
    'products',
    'legacy-products-sync:' || gen_random_uuid()::text,
    auth.uid(),
    jsonb_build_object('legacy_column', 'products.estoque_quantidade', 'operation', tg_op)
  );

  return new;
end;
$$;

revoke all on function public.sync_legacy_product_stock_to_pr() from public, anon, authenticated;

drop policy if exists product_branch_stock_commercial_read
on public.product_branch_stock;
create policy product_branch_stock_commercial_read
on public.product_branch_stock
for select to authenticated
using (
  public.is_admin()
  or public.has_module('produtos')
  or public.has_module('novo_pedido')
  or public.has_module('nova_cotacao')
  or public.has_module('alimentacao')
  or public.has_module('dashboard')
);

revoke all on function public.resolve_branch_import_initial_branches()
from public, anon, authenticated;
drop function if exists public.resolve_branch_import_initial_branches();

commit;
