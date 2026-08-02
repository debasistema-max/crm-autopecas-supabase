begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute
      'lock table supabase_migrations.schema_migrations in share mode';
  end if;
end;
$$;

lock table public.orders, public.order_items,
  public.quotations, public.quotation_items
  in share row exclusive mode;

lock table public.branch_import_legacy_function_snapshots
  in share row exclusive mode;

do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null then
    execute
      'lock table public.order_stock_contract_settings
       in share row exclusive mode';
  end if;
end;
$$;

do $$
declare
  v_used boolean;
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null
     and exists (
       select 1
       from supabase_migrations.schema_migrations
       where version ~ '^[0-9]+$'
         and version::numeric > 29
     ) then
    raise exception using
      errcode = '55000',
      message = 'ROLLBACK_029_BLOCKED_DOWNSTREAM_MIGRATION';
  end if;

  if to_regclass('public.order_stock_contract_settings') is not null then
    execute
      'select exists (
         select 1
         from public.order_stock_contract_settings
         where singleton and order_stock_contract_v1_enabled
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'ROLLBACK_029_BLOCKED_V1_ENABLED';
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name = 'stock_contract_version'
  ) then
    execute
      'select exists (
         select 1
         from public.orders
         where stock_contract_version = 1
            or logistics_status <> ''LEGACY_UNMANAGED''
            or operational_version <> 0
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'ROLLBACK_029_BLOCKED_ORDER_OPERATIONAL_USE';
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quotations'
      and column_name = 'stock_contract_version'
  ) then
    execute
      'select exists (
         select 1
         from public.quotations
         where stock_contract_version = 1
            or operational_version <> 0
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'ROLLBACK_029_BLOCKED_QUOTATION_OPERATIONAL_USE';
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'order_items'
      and column_name = 'branch_price'
  ) then
    execute
      'select exists (
         select 1
         from public.order_items
         where branch_price is not null
            or branch_price_currency is not null
            or branch_price_version is not null
            or branch_price_captured_at is not null
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'ROLLBACK_029_BLOCKED_ORDER_SNAPSHOT_USE';
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quotation_items'
      and column_name = 'branch_price'
  ) then
    execute
      'select exists (
         select 1
         from public.quotation_items
         where branch_price is not null
            or branch_price_currency is not null
            or branch_price_version is not null
            or branch_price_captured_at is not null
       )'
      into v_used;
    if v_used then
      raise exception using
        errcode = '55000',
        message = 'ROLLBACK_029_BLOCKED_QUOTATION_SNAPSHOT_USE';
    end if;
  end if;
end;
$$;

do $validate_029_object_manifest$
declare
  v_fingerprint text;
begin
  if to_regclass('public.order_stock_contract_settings') is null then
    if exists (
      select 1
      from pg_proc function_row
      where function_row.oid in (
        to_regprocedure('public.enforce_branch_order_contract()'),
        to_regprocedure('public.enforce_branch_price_snapshot_parent()'),
        to_regprocedure('public.serialize_branch_order_contract_statement()'),
        to_regprocedure('public.is_active_branch_order_profile()'),
        to_regprocedure('public.is_branch_order_supervisor()')
      )
    )
    or exists (
      select 1
      from pg_attribute attribute_row
      where attribute_row.attrelid in (
        'public.orders'::regclass,
        'public.order_items'::regclass,
        'public.quotations'::regclass,
        'public.quotation_items'::regclass
      )
        and not attribute_row.attisdropped
        and (
          (
            attribute_row.attrelid = 'public.orders'::regclass
            and attribute_row.attname in (
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
          )
          or (
            attribute_row.attrelid = 'public.quotations'::regclass
            and attribute_row.attname in (
              'branch_id',
              'stock_contract_version',
              'priority',
              'promised_at',
              'operational_version'
            )
          )
          or (
            attribute_row.attrelid in (
              'public.order_items'::regclass,
              'public.quotation_items'::regclass
            )
            and attribute_row.attname in (
              'branch_price',
              'branch_price_currency',
              'branch_price_version',
              'branch_price_captured_at'
            )
          )
        )
    )
    or exists (
      select 1
      from pg_class object_row
      join pg_namespace object_schema
        on object_schema.oid = object_row.relnamespace
      where object_schema.nspname = 'public'
        and object_row.relname in (
          'order_items_order_product_unique_029',
          'quotation_items_quotation_product_unique_029',
          'orders_branch_logistics_v1_idx_029',
          'orders_branch_priority_v1_idx_029',
          'orders_owner_branch_v1_idx_029',
          'quotations_branch_v1_idx_029',
          'quotations_owner_branch_v1_idx_029'
        )
    )
    or exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conname in (
        'orders_branch_id_fkey_029',
        'orders_stock_contract_version_check_029',
        'orders_logistics_status_check_029',
        'orders_priority_check_029',
        'orders_operational_version_check_029',
        'orders_contract_coherence_check_029',
        'orders_contract_dates_check_029',
        'quotations_branch_id_fkey_029',
        'quotations_stock_contract_version_check_029',
        'quotations_priority_check_029',
        'quotations_operational_version_check_029',
        'quotations_contract_coherence_check_029',
        'quotations_contract_dates_check_029',
        'order_items_branch_price_snapshot_check_029',
        'quotation_items_branch_price_snapshot_check_029'
      )
        and constraint_row.conrelid in (
          'public.orders'::regclass,
          'public.order_items'::regclass,
          'public.quotations'::regclass,
          'public.quotation_items'::regclass
        )
    )
    or exists (
      select 1
      from pg_trigger trigger_row
      where not trigger_row.tgisinternal
        and trigger_row.tgname in (
          'orders_serialize_branch_contract_029',
          'quotations_serialize_branch_contract_029',
          'order_items_serialize_branch_snapshot_insert_029',
          'order_items_serialize_branch_snapshot_update_029',
          'order_items_serialize_branch_snapshot_write_029',
          'quotation_items_serialize_branch_snapshot_insert_029',
          'quotation_items_serialize_branch_snapshot_update_029',
          'quotation_items_serialize_branch_snapshot_write_029',
          'orders_enforce_branch_contract_029',
          'quotations_enforce_branch_contract_029',
          'order_items_enforce_branch_snapshot_029',
          'quotation_items_enforce_branch_snapshot_029'
        )
        and trigger_row.tgrelid in (
          'public.orders'::regclass,
          'public.order_items'::regclass,
          'public.quotations'::regclass,
          'public.quotation_items'::regclass
        )
    ) then
      raise exception using
        errcode = '55000',
        message = 'ROLLBACK_029_PARTIAL_STATE_WITHOUT_SETTINGS';
    end if;

    if exists (
      with expected(
        function_signature,
        definition_md5,
        owner_name,
        acl_state,
        config_state
      ) as (
        values
          (
            'public.commercial_update_document_items(text,jsonb)',
            '19dd936a5fc11427034c0084ef392adb',
            'postgres',
            '{postgres=X/postgres}',
            '{search_path=public}'
          ),
          (
            'public.commercial_update_document_status(text,uuid,text)',
            'e3cac88842bb5e81a6c33a6e23429c22',
            'postgres',
            '{postgres=X/postgres}',
            '{search_path=public}'
          ),
          (
            'public.convert_quotation_to_order(uuid)',
            '0c40587afdb78135d3ec085384b7ed76',
            'postgres',
            '{postgres=X/postgres,authenticated=X/postgres}',
            '{search_path=public}'
          )
      )
      select 1
      from expected
      left join pg_proc function_row
        on function_row.oid = to_regprocedure(expected.function_signature)
      left join pg_roles owner_role
        on owner_role.oid = function_row.proowner
      where function_row.oid is null
         or md5(pg_get_functiondef(function_row.oid))
            is distinct from expected.definition_md5
         or owner_role.rolname is distinct from expected.owner_name
         or coalesce(function_row.proacl::text, '<NULL>')
            is distinct from expected.acl_state
         or coalesce(function_row.proconfig::text, '<NULL>')
            is distinct from expected.config_state
    )
    or exists (
      with expected(table_oid, policy_name, policy_md5) as (
        values
          (
            'public.orders'::regclass,
            'orders_read',
            '434c374d5e73ee96ff81c7c0db5c7694'
          ),
          (
            'public.order_items'::regclass,
            'order_items_read',
            '7d9c30fae809a14d5bb134e95604a042'
          ),
          (
            'public.quotations'::regclass,
            'quotations_read',
            '434c374d5e73ee96ff81c7c0db5c7694'
          ),
          (
            'public.quotation_items'::regclass,
            'quotation_items_read',
            'ae256495397e374a3761b7298f279864'
          )
      )
      select 1
      from expected
      left join pg_policy policy_row
        on policy_row.polrelid = expected.table_oid
       and policy_row.polname = expected.policy_name
      where policy_row.oid is null
         or md5(concat_ws(
              '|',
              policy_row.polpermissive,
              (
                select string_agg(
                  coalesce(role_row.rolname, 'PUBLIC'),
                  ','
                  order by coalesce(role_row.rolname, 'PUBLIC')
                )
                from unnest(policy_row.polroles) role_oid
                left join pg_roles role_row
                  on role_row.oid = nullif(role_oid, 0)
              ),
              policy_row.polcmd,
              coalesce(
                pg_get_expr(policy_row.polqual, policy_row.polrelid),
                ''
              ),
              coalesce(
                pg_get_expr(policy_row.polwithcheck, policy_row.polrelid),
                ''
              )
            )) is distinct from expected.policy_md5
    ) then
      raise exception using
        errcode = '55000',
        message = 'ROLLBACK_029_LEGACY_BASELINE_DIVERGED';
    end if;

    return;
  end if;

  if (
    select count(*)
    from pg_index index_row
    where index_row.indrelid =
      'public.order_stock_contract_settings'::regclass
  ) <> 1
  or not exists (
    select 1
    from pg_index index_row
    join pg_class index_class on index_class.oid = index_row.indexrelid
    where index_row.indrelid =
      'public.order_stock_contract_settings'::regclass
      and index_class.relname = 'order_stock_contract_settings_pkey'
  )
  or (
    select count(*)
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.order_stock_contract_settings'::regclass
  ) <> 2
  or (
    select count(*)
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.order_stock_contract_settings'::regclass
      and constraint_row.conname in (
        'order_stock_contract_settings_pkey',
        'order_stock_contract_settings_singleton_check'
      )
  ) <> 2
  or (
    select count(*)
    from pg_trigger trigger_row
    where trigger_row.tgrelid =
      'public.order_stock_contract_settings'::regclass
      and not trigger_row.tgisinternal
  ) <> 1
  or not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid =
      'public.order_stock_contract_settings'::regclass
      and not trigger_row.tgisinternal
      and trigger_row.tgname =
        'order_stock_contract_settings_touch_updated_at'
  )
  or exists (
    select 1
    from pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and (
        (
          trigger_row.tgrelid = 'public.order_items'::regclass
          and trigger_row.tgname =
            'order_items_serialize_branch_snapshot_write_029'
        )
        or (
          trigger_row.tgrelid = 'public.quotation_items'::regclass
          and trigger_row.tgname =
            'quotation_items_serialize_branch_snapshot_write_029'
        )
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'ROLLBACK_029_OBJECT_FINGERPRINT_MISMATCH',
      detail = 'unexpected settings object or reserved compatibility trigger';
  end if;

  with objects(category, identity, fingerprint) as (
    select
      'function',
      p.oid::regprocedure::text,
      md5(concat_ws(
        '|',
        owner_role.rolname,
        p.prosecdef,
        coalesce(p.proconfig::text, ''),
        coalesce(p.proacl::text, ''),
        pg_get_functiondef(p.oid)
      ))
    from pg_proc p
    join pg_roles owner_role on owner_role.oid = p.proowner
    where p.oid in (
      to_regprocedure('public.enforce_branch_order_contract()'),
      to_regprocedure('public.enforce_branch_price_snapshot_parent()'),
      to_regprocedure('public.serialize_branch_order_contract_statement()'),
      to_regprocedure('public.is_active_branch_order_profile()'),
      to_regprocedure('public.is_branch_order_supervisor()'),
      to_regprocedure(
        'public.commercial_update_document_items(text,jsonb)'
      ),
      to_regprocedure(
        'public.commercial_update_document_status(text,uuid,text)'
      ),
      to_regprocedure('public.convert_quotation_to_order(uuid)')
    )

    union all

    select
      'index',
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
    from pg_index idx
    join pg_class index_class on index_class.oid = idx.indexrelid
    join pg_class table_class on table_class.oid = idx.indrelid
    join pg_namespace index_schema on index_schema.oid = index_class.relnamespace
    where index_schema.nspname = 'public'
      and index_class.relname in (
        'order_stock_contract_settings_pkey',
        'order_items_order_product_unique_029',
        'quotation_items_quotation_product_unique_029',
        'orders_branch_logistics_v1_idx_029',
        'orders_branch_priority_v1_idx_029',
        'orders_owner_branch_v1_idx_029',
        'quotations_branch_v1_idx_029',
        'quotations_owner_branch_v1_idx_029'
      )

    union all

    select
      'constraint',
      table_class.relname || '.' || con.conname,
      md5(concat_ws(
        '|',
        con.contype,
        con.convalidated,
        con.condeferrable,
        con.condeferred,
        pg_get_constraintdef(con.oid, true)
      ))
    from pg_constraint con
    join pg_class table_class on table_class.oid = con.conrelid
    where (
      table_class.relname,
      con.conname
    ) in (
      (
        'order_stock_contract_settings',
        'order_stock_contract_settings_pkey'
      ),
      (
        'order_stock_contract_settings',
        'order_stock_contract_settings_singleton_check'
      ),
      ('orders', 'orders_branch_id_fkey_029'),
      ('orders', 'orders_stock_contract_version_check_029'),
      ('orders', 'orders_logistics_status_check_029'),
      ('orders', 'orders_priority_check_029'),
      ('orders', 'orders_operational_version_check_029'),
      ('orders', 'orders_contract_coherence_check_029'),
      ('orders', 'orders_contract_dates_check_029'),
      ('quotations', 'quotations_branch_id_fkey_029'),
      ('quotations', 'quotations_stock_contract_version_check_029'),
      ('quotations', 'quotations_priority_check_029'),
      ('quotations', 'quotations_operational_version_check_029'),
      ('quotations', 'quotations_contract_coherence_check_029'),
      ('quotations', 'quotations_contract_dates_check_029'),
      ('order_items', 'order_items_branch_price_snapshot_check_029'),
      (
        'quotation_items',
        'quotation_items_branch_price_snapshot_check_029'
      )
    )

    union all

    select
      'trigger',
      table_class.relname || '.' || trigger_row.tgname,
      md5(concat_ws(
        '|',
        trigger_row.tgtype,
        trigger_row.tgenabled,
        trigger_row.tgfoid::regprocedure::text,
        encode(trigger_row.tgargs, 'escape'),
        coalesce(
          pg_get_expr(trigger_row.tgqual, trigger_row.tgrelid),
          ''
        )
      ))
    from pg_trigger trigger_row
    join pg_class table_class on table_class.oid = trigger_row.tgrelid
    where not trigger_row.tgisinternal
      and (
        table_class.relname,
        trigger_row.tgname
      ) in (
        (
          'order_stock_contract_settings',
          'order_stock_contract_settings_touch_updated_at'
        ),
        ('orders', 'orders_serialize_branch_contract_029'),
        ('quotations', 'quotations_serialize_branch_contract_029'),
        (
          'order_items',
          'order_items_serialize_branch_snapshot_insert_029'
        ),
        (
          'order_items',
          'order_items_serialize_branch_snapshot_update_029'
        ),
        (
          'quotation_items',
          'quotation_items_serialize_branch_snapshot_insert_029'
        ),
        (
          'quotation_items',
          'quotation_items_serialize_branch_snapshot_update_029'
        ),
        ('orders', 'orders_enforce_branch_contract_029'),
        ('quotations', 'quotations_enforce_branch_contract_029'),
        ('order_items', 'order_items_enforce_branch_snapshot_029'),
        (
          'quotation_items',
          'quotation_items_enforce_branch_snapshot_029'
        )
      )

    union all

    select
      'column',
      table_class.relname || '.' || attribute_row.attname,
      md5(concat_ws(
        '|',
        attribute_row.atttypid,
        attribute_row.atttypmod,
        attribute_row.attnotnull,
        attribute_row.attidentity,
        attribute_row.attgenerated,
        attribute_row.attcollation,
        coalesce(
          pg_get_expr(default_row.adbin, default_row.adrelid),
          ''
        ),
        coalesce(attribute_row.attacl::text, '')
      ))
    from pg_attribute attribute_row
    join pg_class table_class
      on table_class.oid = attribute_row.attrelid
    left join pg_attrdef default_row
      on default_row.adrelid = attribute_row.attrelid
     and default_row.adnum = attribute_row.attnum
    where attribute_row.attnum > 0
      and not attribute_row.attisdropped
      and table_class.oid in (
        'public.orders'::regclass,
        'public.order_items'::regclass,
        'public.quotations'::regclass,
        'public.quotation_items'::regclass,
        'public.order_stock_contract_settings'::regclass
      )

    union all

    select
      'policy',
      table_class.relname || '.' || policy_row.polname,
      md5(concat_ws(
        '|',
        policy_row.polpermissive,
        policy_row.polroles::text,
        policy_row.polcmd,
        coalesce(
          pg_get_expr(policy_row.polqual, policy_row.polrelid),
          ''
        ),
        coalesce(
          pg_get_expr(policy_row.polwithcheck, policy_row.polrelid),
          ''
        )
      ))
    from pg_policy policy_row
    join pg_class table_class on table_class.oid = policy_row.polrelid
    where table_class.oid in (
      'public.orders'::regclass,
      'public.order_items'::regclass,
      'public.quotations'::regclass,
      'public.quotation_items'::regclass,
      'public.order_stock_contract_settings'::regclass
    )

    union all

    select
      'relation',
      relation_row.relname,
      md5(concat_ws(
        '|',
        relation_row.relkind,
        relation_row.relowner::regrole::text,
        relation_row.relrowsecurity,
        relation_row.relforcerowsecurity,
        coalesce(relation_row.relacl::text, '')
      ))
    from pg_class relation_row
    where relation_row.oid in (
      'public.orders'::regclass,
      'public.order_items'::regclass,
      'public.quotations'::regclass,
      'public.quotation_items'::regclass,
      'public.order_stock_contract_settings'::regclass
    )
  )
  select md5(string_agg(
    category || '|' || identity || '|' || fingerprint,
    E'\n'
    order by category, identity
  ))
  into v_fingerprint
  from objects;

  if v_fingerprint is distinct from
     'a564e04f997242b3af203cc059b3d44f' then
    raise exception using
      errcode = '55000',
      message = 'ROLLBACK_029_OBJECT_FINGERPRINT_MISMATCH',
      detail = coalesce(v_fingerprint, '<NULL>');
  end if;
end
$validate_029_object_manifest$;

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
for select to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists order_items_read on public.order_items;
create policy order_items_read on public.order_items
for select to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (public.is_admin() or o.user_id = auth.uid())
  )
);

drop policy if exists quotations_read on public.quotations;
create policy quotations_read on public.quotations
for select to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists quotation_items_read on public.quotation_items;
create policy quotation_items_read on public.quotation_items
for select to authenticated
using (
  exists (
    select 1
    from public.quotations q
    where q.id = quotation_id
      and (public.is_admin() or q.user_id = auth.uid())
  )
);

drop trigger if exists order_items_enforce_branch_snapshot_029
  on public.order_items;
drop trigger if exists quotation_items_enforce_branch_snapshot_029
  on public.quotation_items;
drop trigger if exists quotation_items_serialize_branch_snapshot_update_029
  on public.quotation_items;
drop trigger if exists quotation_items_serialize_branch_snapshot_insert_029
  on public.quotation_items;
drop trigger if exists quotation_items_serialize_branch_snapshot_write_029
  on public.quotation_items;
drop trigger if exists order_items_serialize_branch_snapshot_update_029
  on public.order_items;
drop trigger if exists order_items_serialize_branch_snapshot_insert_029
  on public.order_items;
drop trigger if exists order_items_serialize_branch_snapshot_write_029
  on public.order_items;
drop trigger if exists quotations_serialize_branch_contract_029
  on public.quotations;
drop trigger if exists orders_serialize_branch_contract_029
  on public.orders;
drop trigger if exists orders_enforce_branch_contract_029
  on public.orders;
drop trigger if exists quotations_enforce_branch_contract_029
  on public.quotations;

do $restore_legacy_commercial_functions$
declare
  v_snapshot record;
  v_owner name;
  v_acl text;
  v_config text;
  v_restored_md5 text;
  v_snapshot_count integer;
  v_rpc_has_029_lock boolean;
begin
  select count(*)
  into v_snapshot_count
  from public.branch_import_legacy_function_snapshots
  where function_signature = any(array[
    'public.commercial_update_document_items(text,jsonb)',
    'public.commercial_update_document_status(text,uuid,text)',
    'public.convert_quotation_to_order(uuid)'
  ]);

  select position(
    'pg_advisory_xact_lock(29, 0)'
    in lower(pg_get_functiondef(
      'public.commercial_update_document_items(text,jsonb)'::regprocedure
    ))
  ) > 0
  into v_rpc_has_029_lock;

  if v_snapshot_count = 0 then
    if to_regprocedure(
         'public.serialize_branch_order_contract_statement()'
       ) is not null
       or v_rpc_has_029_lock then
      raise exception using
        errcode = '55000',
        message = 'ROLLBACK_029_LEGACY_COMMERCIAL_SNAPSHOT_MISSING';
    end if;
    return;
  elsif v_snapshot_count <> 3 then
    raise exception using
      errcode = '55000',
      message = 'ROLLBACK_029_LEGACY_COMMERCIAL_SNAPSHOT_INCOMPLETE';
  end if;

  if exists (
    with expected(
      function_signature,
      definition_md5,
      owner_name,
      acl_state,
      config_state
    ) as (
      values
        (
          'public.commercial_update_document_items(text,jsonb)',
          '19dd936a5fc11427034c0084ef392adb',
          'postgres'::name,
          '{postgres=X/postgres}',
          '{search_path=public}'
        ),
        (
          'public.commercial_update_document_status(text,uuid,text)',
          'e3cac88842bb5e81a6c33a6e23429c22',
          'postgres'::name,
          '{postgres=X/postgres}',
          '{search_path=public}'
        ),
        (
          'public.convert_quotation_to_order(uuid)',
          '0c40587afdb78135d3ec085384b7ed76',
          'postgres'::name,
          '{postgres=X/postgres,authenticated=X/postgres}',
          '{search_path=public}'
        )
    )
    select 1
    from expected
    left join public.branch_import_legacy_function_snapshots snapshot
      using (function_signature)
    where snapshot.function_signature is null
       or snapshot.definition_md5 is distinct from expected.definition_md5
       or snapshot.owner_name is distinct from expected.owner_name
       or snapshot.acl_state is distinct from expected.acl_state
       or snapshot.config_state is distinct from expected.config_state
       or snapshot.definition_md5 is distinct from
          md5(snapshot.function_definition)
  ) then
    raise exception using
      errcode = '55000',
      message = 'ROLLBACK_029_LEGACY_COMMERCIAL_BASELINE_MISMATCH';
  end if;

  for v_snapshot in
    select *
    from public.branch_import_legacy_function_snapshots
    where function_signature = any(array[
      'public.commercial_update_document_items(text,jsonb)',
      'public.commercial_update_document_status(text,uuid,text)',
      'public.convert_quotation_to_order(uuid)'
    ])
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
          errcode = '55000',
          message = 'ROLLBACK_029_LEGACY_COMMERCIAL_SECURITY_DIVERGED',
          detail = v_snapshot.function_signature;
      end if;

      execute v_snapshot.function_definition;

      select md5(pg_get_functiondef(
        to_regprocedure(v_snapshot.function_signature)
      ))
      into v_restored_md5;

      if v_restored_md5 is distinct from v_snapshot.definition_md5 then
        raise exception using
          errcode = '55000',
          message = 'ROLLBACK_029_LEGACY_COMMERCIAL_RESTORE_DIVERGED',
          detail = v_snapshot.function_signature;
      end if;
  end loop;

  delete from public.branch_import_legacy_function_snapshots
  where function_signature = any(array[
    'public.commercial_update_document_items(text,jsonb)',
    'public.commercial_update_document_status(text,uuid,text)',
    'public.convert_quotation_to_order(uuid)'
  ]);
end
$restore_legacy_commercial_functions$;

drop index if exists public.order_items_order_product_unique_029;
drop index if exists public.quotation_items_quotation_product_unique_029;
drop index if exists public.orders_branch_logistics_v1_idx_029;
drop index if exists public.orders_branch_priority_v1_idx_029;
drop index if exists public.orders_owner_branch_v1_idx_029;
drop index if exists public.quotations_branch_v1_idx_029;
drop index if exists public.quotations_owner_branch_v1_idx_029;

alter table public.order_items
  drop constraint if exists order_items_branch_price_snapshot_check_029;
alter table public.quotation_items
  drop constraint if exists quotation_items_branch_price_snapshot_check_029;

alter table public.orders
  drop constraint if exists orders_contract_dates_check_029,
  drop constraint if exists orders_contract_coherence_check_029,
  drop constraint if exists orders_operational_version_check_029,
  drop constraint if exists orders_priority_check_029,
  drop constraint if exists orders_logistics_status_check_029,
  drop constraint if exists orders_stock_contract_version_check_029,
  drop constraint if exists orders_branch_id_fkey_029;

alter table public.quotations
  drop constraint if exists quotations_contract_dates_check_029,
  drop constraint if exists quotations_contract_coherence_check_029,
  drop constraint if exists quotations_operational_version_check_029,
  drop constraint if exists quotations_priority_check_029,
  drop constraint if exists quotations_stock_contract_version_check_029,
  drop constraint if exists quotations_branch_id_fkey_029;

alter table public.order_items
  drop column if exists branch_price_captured_at,
  drop column if exists branch_price_version,
  drop column if exists branch_price_currency,
  drop column if exists branch_price;

alter table public.quotation_items
  drop column if exists branch_price_captured_at,
  drop column if exists branch_price_version,
  drop column if exists branch_price_currency,
  drop column if exists branch_price;

alter table public.orders
  drop column if exists price_revalidation_required_at,
  drop column if exists approval_requested_at,
  drop column if exists branch_locked_at,
  drop column if exists operational_version,
  drop column if exists promised_at,
  drop column if exists priority,
  drop column if exists logistics_status,
  drop column if exists stock_contract_version,
  drop column if exists branch_id;

alter table public.quotations
  drop column if exists operational_version,
  drop column if exists promised_at,
  drop column if exists priority,
  drop column if exists stock_contract_version,
  drop column if exists branch_id;

do $$
begin
  if to_regclass('public.order_stock_contract_settings') is not null then
    drop policy if exists order_stock_contract_settings_admin_read_029
      on public.order_stock_contract_settings;
    drop trigger if exists order_stock_contract_settings_touch_updated_at
      on public.order_stock_contract_settings;
  end if;
end;
$$;

drop table if exists public.order_stock_contract_settings;

drop function if exists public.enforce_branch_price_snapshot_parent();
drop function if exists public.enforce_branch_order_contract();
drop function if exists public.serialize_branch_order_contract_statement();
drop function if exists public.is_branch_order_supervisor();
drop function if exists public.is_active_branch_order_profile();

commit;
