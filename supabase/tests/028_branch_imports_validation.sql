\set ON_ERROR_STOP on

begin;

insert into public.products (
  codigo,
  descricao,
  preco_pr,
  preco_sp,
  estoque_quantidade
)
values
  ('TEST-028-NULL', 'Fixture sem preco', null, null, 0),
  ('TEST-028-ZERO', 'Fixture preco zero', 0, 0, 0),
  ('TEST-028-POSITIVE', 'Fixture preco positivo', 10.25, 11.50, 3)
on conflict (codigo) do nothing;

do $$
declare
  v_pr uuid;
  v_sp uuid;
begin
  select id into v_pr from public.branches where code = 'PR';
  select id into v_sp from public.branches where code = 'SP';

  if v_pr is null or v_sp is null then
    raise exception 'TEST_FAIL: filiais PR/SP ausentes';
  end if;

  if (select count(*) from public.product_branch_prices
      where product_code = 'TEST-028-NULL') <> 0 then
    raise exception 'TEST_FAIL: preco nulo gerou linha';
  end if;

  if (select count(*) from public.product_branch_prices
      where product_code = 'TEST-028-ZERO' and sale_price = 0) <> 2 then
    raise exception 'TEST_FAIL: preco zero nao foi preservado em PR/SP';
  end if;

  if (select count(*) from public.product_branch_prices
      where product_code = 'TEST-028-POSITIVE' and sale_price > 0) <> 2 then
    raise exception 'TEST_FAIL: preco positivo nao foi migrado em PR/SP';
  end if;

  if has_table_privilege('anon', 'public.product_branch_prices', 'select')
     or has_table_privilege('anon', 'public.product_branch_prices', 'insert')
     or has_table_privilege('anon', 'public.product_branch_prices', 'update')
     or has_table_privilege('anon', 'public.product_branch_prices', 'delete') then
    raise exception 'TEST_FAIL: anon possui privilegio em precos por filial';
  end if;

  if has_table_privilege('authenticated', 'public.product_branch_prices', 'insert')
     or has_table_privilege('authenticated', 'public.product_branch_prices', 'update')
     or has_table_privilege('authenticated', 'public.product_branch_prices', 'delete') then
    raise exception 'TEST_FAIL: authenticated possui escrita direta em precos';
  end if;

  if not has_table_privilege(
    'authenticated', 'public.product_branch_prices', 'select'
  ) then
    raise exception 'TEST_FAIL: authenticated sem grant de leitura';
  end if;

  if not (select relrowsecurity from pg_class
          where oid = 'public.product_branch_prices'::regclass) then
    raise exception 'TEST_FAIL: RLS de precos desativada';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.can_access_product_import_batch_row(integer,uuid,uuid,text,boolean,boolean,boolean)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.can_access_product_import_batch_row(integer,uuid,uuid,text,boolean,boolean,boolean)',
       'execute'
     ) then
    raise exception 'TEST_FAIL: grant do helper de policy divergente';
  end if;

  if exists (
    select 1
    from (values
      ('public.products_import_batches'),
      ('public.products_import_stage'),
      ('public.products_import_audit')
    ) target(table_name)
    where not has_table_privilege(
        'authenticated', target.table_name, 'select'
      )
      or has_table_privilege(
        'authenticated', target.table_name, 'insert'
      )
      or has_table_privilege(
        'authenticated', target.table_name, 'update'
      )
      or has_table_privilege(
        'authenticated', target.table_name, 'delete'
      )
      or has_table_privilege('anon', target.table_name, 'select')
      or has_table_privilege('anon', target.table_name, 'insert')
      or has_table_privilege('anon', target.table_name, 'update')
      or has_table_privilege('anon', target.table_name, 'delete')
  ) then
    raise exception 'TEST_FAIL: grants de batches/stage/audit divergentes';
  end if;

  if (
    select count(*)
    from public.branch_import_legacy_table_acl_snapshots
    where table_name in (
      'public.products_import_batches',
      'public.products_import_stage',
      'public.products_import_audit'
    )
  ) <> 3 then
    raise exception 'TEST_FAIL: snapshots de ACL das tabelas incompletos';
  end if;

  if exists (
    select 1
    from public.branch_import_legacy_table_acl_snapshots snapshot
    where snapshot.raw_acl_md5 <> md5(
      coalesce(snapshot.raw_acl_state::text, '<NULL>')
    )
      or snapshot.effective_acl_state is null
      or cardinality(snapshot.effective_acl_state) = 0
  ) then
    raise exception 'TEST_FAIL: snapshot relacl invalido';
  end if;

  if exists (
    select 1
    from (values
      ('public.products_import_batches'),
      ('public.products_import_stage'),
      ('public.products_import_audit')
    ) target(table_name)
    join pg_class c on c.oid = target.table_name::regclass
    where c.relacl is null
  ) then
    raise exception 'TEST_FAIL: ACL fechada da 028 nao foi materializada';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.product_branch_prices'::regclass
      and conname = 'product_branch_prices_source_batch_id_fkey'
      and confdeltype = 'r'
  ) then
    raise exception 'TEST_FAIL: source_batch_id nao usa ON DELETE RESTRICT';
  end if;

  if (select count(*) from pg_trigger
      where tgrelid = 'public.products'::regclass
        and not tgisinternal
        and tgname in (
          'products_insert_sync_legacy_stock_to_pr',
          'products_update_sync_legacy_stock_to_pr'
        )) <> 2 then
    raise exception 'TEST_FAIL: vinculos do trigger legado divergentes';
  end if;

  if position(
    'current_setting(''app.stock_sync_source'', true)'
    in pg_get_functiondef(
      'public.sync_legacy_product_stock_to_pr()'::regprocedure
    )
  ) = 0 then
    raise exception 'TEST_FAIL: trigger legado nao reconhece marcador V2';
  end if;

  if (select count(*) from pg_trigger
      where tgrelid = 'public.products'::regclass
        and not tgisinternal
        and tgname = 'products_sync_legacy_prices_to_branches') <> 1 then
    raise exception 'TEST_FAIL: trigger temporario de precos ausente';
  end if;

  if (select count(*) from public.resolve_branch_import_initial_branches())
     <> 1 then
    raise exception 'TEST_FAIL: resolvedor canonico de filiais invalido';
  end if;
end
$$;

do $$
begin
  begin
    update public.branches set active = false where code = 'SP';
    perform * from public.resolve_branch_import_initial_branches();
    raise exception 'TEST_FAIL: filial SP inativa foi aceita';
  exception
    when sqlstate 'P2804' then
      null;
  end;
end
$$;

do $$
declare
  v_expected text[];
  v_hash_a text;
  v_hash_b text;
begin
  v_expected := array['physical_qty', 'product_code'];
  if public.normalize_branch_import_mask(
    'UPDATE_STOCK', array['product_code', 'physical_qty', 'product_code']
  ) is distinct from v_expected then
    raise exception 'TEST_FAIL: mascara nao foi normalizada';
  end if;

  select encode(
    digest(convert_to('zero', 'UTF8'), 'sha256'), 'hex'
  ) into v_hash_a;
  select encode(
    digest(convert_to('empty', 'UTF8'), 'sha256'), 'hex'
  ) into v_hash_b;
  if v_hash_a = v_hash_b then
    raise exception 'TEST_FAIL: controle basico de hash invalido';
  end if;
end
$$;

insert into auth.users (
  id, aud, role, email, encrypted_password, confirmed_at,
  created_at, updated_at
)
values (
  '02800000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'phase2-admin@example.invalid',
  '',
  now(),
  now(),
  now()
);

insert into public.profiles (
  id, usuario, nome, email, perfil, ativo
)
values (
  '02800000-0000-4000-8000-000000000001',
  'phase2-admin',
  'Phase 2 Admin',
  'phase2-admin@example.invalid',
  'ADMIN',
  true
);

select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  true
);

create temporary table phase2_test_batches (
  name text primary key,
  id uuid not null
) on commit drop;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
  v_expected_error constant text := 'IMPORTACAO_NAO_DISPONIVEL_NESTE_FLUXO';
  v_function text;
  v_error text;
  v_state text;
begin
  select id into v_pr from public.branches where code = 'PR';

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  insert into phase2_test_batches values ('legacy_bypass_v2', v_batch);

  foreach v_function in array array[
    'preview_products_import_batch',
    'approve_products_import_batch',
    'commit_products_import_batch'
  ]
  loop
    v_error := null;
    v_state := null;
    begin
      execute format('select public.%I($1)', v_function) using v_batch;
      raise exception 'TEST_FAIL: RPC legada % aceitou lote V2', v_function;
    exception
      when others then
        if sqlerrm like 'TEST_FAIL:%' then
          raise;
        end if;
        v_error := sqlerrm;
        v_state := sqlstate;
    end;

    if v_state <> 'P2812' or v_error <> v_expected_error then
      raise exception
        'TEST_FAIL: RPC legada % retornou resposta divergente: % / %',
        v_function,
        v_state,
        v_error;
    end if;
  end loop;

  if (select state from public.products_import_batches where id = v_batch)
     <> 'DRAFT' then
      raise exception 'TEST_FAIL: bypass legado alterou lote V2';
  end if;

  begin
    perform public.rollback_products_import_batch(v_batch);
    raise exception 'TEST_FAIL: rollback legado retornou para lote V2';
  exception
    when others then
      if sqlerrm like 'TEST_FAIL:%' then
        raise;
      end if;
      if sqlerrm <> 'ROLLBACK_IMPORTACAO_NAO_HABILITADO' then
        raise exception 'TEST_FAIL: rollback legado revelou lote V2: %', sqlerrm;
      end if;
  end;
end
$$;

do $$
declare
  v_snapshot record;
  v_current_md5 text;
begin
  if (
    select count(*)
    from public.branch_import_legacy_function_snapshots
  ) <> 6 then
    raise exception 'TEST_FAIL: snapshots legados incompletos';
  end if;

  for v_snapshot in
    select *
    from public.branch_import_legacy_function_snapshots
  loop
    select md5(pg_get_functiondef(to_regprocedure(v_snapshot.function_signature)))
    into v_current_md5;
    if v_current_md5 = v_snapshot.definition_md5 then
      raise exception
        'TEST_FAIL: funcao legada % nao recebeu protecao da 028',
        v_snapshot.function_signature;
    end if;
  end loop;
end
$$;

do $$
declare
  v_pr uuid;
  v_payload jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';

  foreach v_payload in array array[
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'contract_version', 2
    ),
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'contract_version', '1'
    ),
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'contract_version', ' 1 '
    ),
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'contract_version', 1.0::numeric
    ),
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'contract_version', null
    ),
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'normalization_algorithm', 'client-defined'
    ),
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'normalization_algorithm', 'Branch-Import-V1'
    ),
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'hash_algorithm', 'MD5'
    ),
    jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty'),
      'hash_algorithm', 'sha-256'
    )
  ]
  loop
    begin
      perform public.create_product_import_batch(v_payload);
      raise exception 'TEST_FAIL: contrato arbitrario foi aceito';
    exception
      when sqlstate 'P2810' then
        null;
    end;
  end loop;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch_a uuid;
  v_batch_b uuid;
  v_batch_c uuid;
  v_hash_a text;
  v_hash_b text;
  v_hash_c text;
  v_result jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch_a := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch_a, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
      'data', jsonb_build_object('physical_qty', 1)
    )
  ));

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('physical_qty', 'product_code')
  ));
  v_batch_b := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch_b, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('physical_qty', 'product_code'),
      'data', jsonb_build_object('physical_qty', 1.0000)
    )
  ));

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch_c := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch_c, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
      'data', jsonb_build_object('physical_qty', '1.0000')
    )
  ));

  select public.compute_product_import_staging_hash(v_batch_a) into v_hash_a;
  select public.compute_product_import_staging_hash(v_batch_b) into v_hash_b;
  select public.compute_product_import_staging_hash(v_batch_c) into v_hash_c;

  if v_hash_a <> v_hash_b or v_hash_b <> v_hash_c then
    raise exception 'TEST_FAIL: numeros semanticamente iguais geraram hashes diferentes';
  end if;

  begin
    perform public.stage_product_import_rows(v_batch_a, jsonb_build_array(
      jsonb_build_object(
        'row_number', 2,
        'product_code', 'TEST-028-ZERO',
        'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
        'data', jsonb_build_object('physical_qty', 0, 'campo_extra', 10)
      )
    ));
    raise exception 'TEST_FAIL: chave extra fora da mascara foi aceita';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: chave extra fora da mascara foi aceita' then
        raise;
      end if;
      if sqlerrm <> 'STAGING_DATA_FORA_DOS_CAMPOS' then
        raise exception 'TEST_FAIL: erro inesperado para chave extra: %', sqlerrm;
      end if;
  end;

  if public.canonicalize_branch_import_data(
       array['physical_qty'], '{}'::jsonb
     ) = public.canonicalize_branch_import_data(
       array['physical_qty'], '{"physical_qty":null}'::jsonb
     )
     or public.canonicalize_branch_import_data(
       array['physical_qty'], '{"physical_qty":null}'::jsonb
     ) = public.canonicalize_branch_import_data(
       array['physical_qty'], '{"physical_qty":0}'::jsonb
     ) then
    raise exception 'TEST_FAIL: ausente, nulo e zero nao foram diferenciados';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_sp uuid;
  v_pr_version bigint;
  v_sp_version bigint;
begin
  select pr_branch_id, sp_branch_id into v_pr, v_sp
  from public.resolve_branch_import_initial_branches();

  select version into v_pr_version
  from public.product_branch_prices
  where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr;
  select version into v_sp_version
  from public.product_branch_prices
  where product_code = 'TEST-028-POSITIVE' and branch_id = v_sp;

  update public.products
  set preco_pr = preco_pr + 1
  where codigo = 'TEST-028-POSITIVE';

  if (select version from public.product_branch_prices
      where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr)
       <> v_pr_version + 1
     or (select source from public.product_branch_prices
         where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr)
       <> 'LEGACY_SYNC'
     or (select version from public.product_branch_prices
         where product_code = 'TEST-028-POSITIVE' and branch_id = v_sp)
       <> v_sp_version then
    raise exception 'TEST_FAIL: sincronizacao legada PR alterou filial incorreta';
  end if;

  select version into v_pr_version
  from public.product_branch_prices
  where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr;
  update public.products
  set preco_pr = preco_pr
  where codigo = 'TEST-028-POSITIVE';
  if (select version from public.product_branch_prices
      where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr)
       <> v_pr_version then
    raise exception 'TEST_FAIL: no-op legado incrementou versao';
  end if;

  update public.products set preco_pr = null
  where codigo = 'TEST-028-POSITIVE';
  if exists (
    select 1 from public.product_branch_prices
    where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr
  ) then
    raise exception 'TEST_FAIL: preco legado nulo nao removeu ausencia';
  end if;

  update public.products set preco_pr = 0
  where codigo = 'TEST-028-POSITIVE';
  if not exists (
    select 1 from public.product_branch_prices
    where product_code = 'TEST-028-POSITIVE'
      and branch_id = v_pr
      and sale_price = 0
      and source = 'LEGACY_SYNC'
  ) then
    raise exception 'TEST_FAIL: preco legado zero nao foi preservado';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';
  update public.product_branch_stock
  set physical_qty = 2,
      reserved_order_qty = 2
  where product_code = 'TEST-028-ZERO' and branch_id = v_pr;

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-ZERO',
      'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
      'data', jsonb_build_object('physical_qty', 1)
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  v_result := public.commit_product_import_batch(v_batch);

  if v_result->>'state' <> 'FAILED' then
    raise exception 'TEST_FAIL: regra de negocio nao terminou em FAILED: %',
      v_result;
  end if;
  if (select state from public.products_import_batches where id = v_batch)
     <> 'FAILED' then
    raise exception 'TEST_FAIL: COMMITTING ficou persistido apos falha';
  end if;
  if (select last_failure_code from public.products_import_batches
      where id = v_batch) <> 'BUSINESS_RULE_VIOLATION' then
    raise exception 'TEST_FAIL: regra de negocio sem classificacao';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
  v_movements integer;
begin
  select id into v_pr from public.branches where code = 'PR';

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_STOCK',
    'contract_version', 1,
    'field_mask', jsonb_build_array('product_code', 'physical_qty'),
    'source_name', 'phase2-pr-stock.csv'
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  insert into phase2_test_batches values ('pr_stock', v_batch);

  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
      'data', jsonb_build_object('physical_qty', 7)
    )
  ));
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
      'data', jsonb_build_object('physical_qty', 7)
    )
  ));
  if (select count(*) from public.products_import_stage
      where batch_id = v_batch) <> 1 then
    raise exception 'TEST_FAIL: staging repetido duplicou linha';
  end if;
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  v_result := public.commit_product_import_batch(v_batch);

  if v_result->>'state' <> 'COMMITTED' then
    raise exception 'TEST_FAIL: commit PR nao concluiu: %', v_result;
  end if;
  if (select physical_qty from public.product_branch_stock
      where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr) <> 7 then
    raise exception 'TEST_FAIL: estoque PR nao foi atualizado';
  end if;
  if (select estoque_quantidade from public.products
      where codigo = 'TEST-028-POSITIVE') <> 7 then
    raise exception 'TEST_FAIL: espelho legado PR nao foi atualizado';
  end if;

  select count(*) into v_movements
  from public.stock_movements
  where source = 'BRANCH_IMPORT_V2'
    and reference_id = (
      select id from public.products_import_stage
      where batch_id = v_batch and normalized_code = 'TEST-028-POSITIVE'
    );
  if v_movements <> 1 then
    raise exception 'TEST_FAIL: commit PR gerou % movimentos', v_movements;
  end if;

  v_result := public.commit_product_import_batch(v_batch);
  if coalesce((v_result->>'idempotent')::boolean, false) is not true then
    raise exception 'TEST_FAIL: repeticao do commit nao foi idempotente';
  end if;
  if (select count(*) from public.stock_movements
      where source = 'BRANCH_IMPORT_V2'
        and reference_id = (
          select id from public.products_import_stage
          where batch_id = v_batch and normalized_code = 'TEST-028-POSITIVE'
        )) <> 1 then
    raise exception 'TEST_FAIL: repeticao duplicou movimento';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
begin
  select id into v_pr from public.branches where code = 'PR';
  begin
    perform public.create_product_import_batch(jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'campo_invalido')
    ));
    raise exception 'TEST_FAIL: mascara invalida foi aceita';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: mascara invalida foi aceita' then
        raise;
      end if;
      if sqlerrm <> 'MASCARA_CONTEM_CAMPO_INVALIDO' then
        raise exception 'TEST_FAIL: erro inesperado de mascara: %', sqlerrm;
      end if;
  end;
end
$$;

do $$
declare
  v_pr uuid;
  v_sp uuid;
  v_batch uuid;
  v_result jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';
  select id into v_sp from public.branches where code = 'SP';

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_sp,
    'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  insert into phase2_test_batches values ('sp_stock', v_batch);

  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
      'data', jsonb_build_object('physical_qty', 5)
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  v_result := public.commit_product_import_batch(v_batch);

  if v_result->>'state' <> 'COMMITTED' then
    raise exception 'TEST_FAIL: commit SP nao concluiu: %', v_result;
  end if;
  if (select physical_qty from public.product_branch_stock
      where product_code = 'TEST-028-POSITIVE' and branch_id = v_sp) <> 5 then
    raise exception 'TEST_FAIL: estoque SP nao foi atualizado';
  end if;
  if (select physical_qty from public.product_branch_stock
      where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr) <> 7 then
    raise exception 'TEST_FAIL: importacao SP alterou PR';
  end if;
  if (select estoque_quantidade from public.products
      where codigo = 'TEST-028-POSITIVE') <> 7 then
    raise exception 'TEST_FAIL: importacao SP alterou espelho legado PR';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
  v_version_before bigint;
  v_version_after bigint;
begin
  select id into v_pr from public.branches where code = 'PR';
  select version into v_version_before
  from public.product_branch_prices
  where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr;

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_PRICES',
    'field_mask', jsonb_build_array('product_code', 'sale_price')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'sale_price'),
      'data', jsonb_build_object('sale_price', 13)
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  perform public.commit_product_import_batch(v_batch);

  select version into v_version_after
  from public.product_branch_prices
  where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr;
  if v_version_after <> v_version_before + 1 then
    raise exception 'TEST_FAIL: mudanca real de preco nao incrementou versao';
  end if;
  if (select source from public.product_branch_prices
      where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr)
       <> 'BRANCH_IMPORT_V2'
     or (select source_batch_id from public.product_branch_prices
         where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr)
       <> v_batch then
    raise exception 'TEST_FAIL: trigger legado sobrescreveu origem V2';
  end if;
  if (select preco_pr from public.products
      where codigo = 'TEST-028-POSITIVE') <> 13 then
    raise exception 'TEST_FAIL: espelho legado de preco PR nao foi atualizado';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
  v_before text;
begin
  select id into v_pr from public.branches where code = 'PR';
  select descricao into v_before from public.products
  where codigo = 'TEST-028-POSITIVE';

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'CUSTOM_UPDATE',
    'field_mask', jsonb_build_array('product_code', 'description')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  insert into phase2_test_batches values ('empty_description', v_batch);
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'description'),
      'data', jsonb_build_object('description', '')
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  perform public.commit_product_import_batch(v_batch);

  if (select descricao from public.products
      where codigo = 'TEST-028-POSITIVE') is distinct from v_before then
    raise exception 'TEST_FAIL: vazio sobrescreveu descricao';
  end if;
  if (select count(*) from public.products_import_audit
      where batch_id = v_batch and entity_type = 'PRODUCT') <> 0 then
    raise exception 'TEST_FAIL: vazio gerou auditoria de produto';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';
  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'CREATE_PRODUCTS',
    'field_mask', jsonb_build_array(
      'product_code', 'description', 'physical_qty', 'sale_price'
    )
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-NEW',
      'provided_fields', jsonb_build_array(
        'product_code', 'description', 'physical_qty', 'sale_price'
      ),
      'data', jsonb_build_object(
        'description', 'Produto novo da fase 2',
        'physical_qty', 0,
        'sale_price', 0
      )
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  v_result := public.commit_product_import_batch(v_batch);

  if v_result->>'state' <> 'COMMITTED'
     or not exists (select 1 from public.products where codigo = 'TEST-028-NEW')
     or not exists (
       select 1 from public.product_branch_prices
       where product_code = 'TEST-028-NEW'
         and branch_id = v_pr
         and sale_price = 0
     )
     or (select count(*) from public.products_import_audit
         where batch_id = v_batch and entity_type = 'PRODUCT') <> 1 then
    raise exception 'TEST_FAIL: cadastro de produto novo incompleto';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
  v_version_before bigint;
  v_version_after bigint;
begin
  select id into v_pr from public.branches where code = 'PR';
  select version into v_version_before
  from public.product_branch_prices
  where product_code = 'TEST-028-ZERO' and branch_id = v_pr;

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_PRICES',
    'field_mask', jsonb_build_array('product_code', 'sale_price', 'currency')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  insert into phase2_test_batches values ('zero_price', v_batch);
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-ZERO',
      'provided_fields', jsonb_build_array(
        'product_code', 'sale_price', 'currency'
      ),
      'data', jsonb_build_object('sale_price', 0, 'currency', 'BRL')
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  perform public.commit_product_import_batch(v_batch);

  select version into v_version_after
  from public.product_branch_prices
  where product_code = 'TEST-028-ZERO' and branch_id = v_pr;
  if v_version_after <> v_version_before then
    raise exception 'TEST_FAIL: preco zero sem mudanca incrementou versao';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_sp uuid;
  v_pr_batch uuid;
  v_sp_batch uuid;
  v_pr_hash text;
  v_sp_hash text;
  v_result jsonb;
  v_rows jsonb := jsonb_build_array(jsonb_build_object(
    'row_number', 1,
    'product_code', 'TEST-028-POSITIVE',
    'provided_fields', jsonb_build_array('product_code', 'sale_price'),
    'data', jsonb_build_object('sale_price', 99)
  ));
begin
  select id into v_pr from public.branches where code = 'PR';
  select id into v_sp from public.branches where code = 'SP';

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr, 'mode', 'UPDATE_PRICES',
    'field_mask', jsonb_build_array('product_code', 'sale_price')
  ));
  v_pr_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_pr_batch, v_rows);
  perform public.preview_product_import_batch(v_pr_batch);

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_sp, 'mode', 'UPDATE_PRICES',
    'field_mask', jsonb_build_array('product_code', 'sale_price')
  ));
  v_sp_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_sp_batch, v_rows);
  perform public.preview_product_import_batch(v_sp_batch);

  select normalized_file_hash into v_pr_hash
  from public.products_import_batches where id = v_pr_batch;
  select normalized_file_hash into v_sp_hash
  from public.products_import_batches where id = v_sp_batch;
  if v_pr_hash = v_sp_hash then
    raise exception 'TEST_FAIL: hash nao distingue filial';
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';
  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  insert into phase2_test_batches values ('invalid_numeric', v_batch);
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
      'data', jsonb_build_object('physical_qty', 'nao-numerico')
    )
  ));
  v_result := public.preview_product_import_batch(v_batch);
  if v_result->>'state' <> 'FAILED' then
    raise exception 'TEST_FAIL: lote invalido nao terminou em FAILED';
  end if;
  begin
    perform public.preview_product_import_batch(v_batch);
    raise exception 'TEST_FAIL: FAILED retornou ao fluxo';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: FAILED retornou ao fluxo' then
        raise;
      end if;
  end;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch_a uuid;
  v_batch_b uuid;
  v_result jsonb;
  v_rows_a jsonb := jsonb_build_array(jsonb_build_object(
    'row_number', 1,
    'product_code', 'TEST-028-POSITIVE',
    'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
    'data', jsonb_build_object('physical_qty', 30)
  ));
  v_rows_b jsonb := jsonb_build_array(jsonb_build_object(
    'row_number', 1,
    'product_code', 'TEST-028-POSITIVE',
    'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
    'data', jsonb_build_object('physical_qty', 31)
  ));
begin
  select id into v_pr from public.branches where code = 'PR';

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr, 'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch_a := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch_a, v_rows_a);
  perform public.preview_product_import_batch(v_batch_a);
  perform public.approve_product_import_batch(v_batch_a);

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr, 'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch_b := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch_b, v_rows_b);
  perform public.preview_product_import_batch(v_batch_b);
  perform public.approve_product_import_batch(v_batch_b);

  perform public.commit_product_import_batch(v_batch_a);
  v_result := public.commit_product_import_batch(v_batch_b);
  if v_result->>'state' <> 'REVALIDATION_REQUIRED' then
    raise exception 'TEST_FAIL: conflito nao exigiu revalidacao: %', v_result;
  end if;
  if (select physical_qty from public.product_branch_stock
      where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr) <> 30 then
    raise exception 'TEST_FAIL: lote conflitante alterou saldo';
  end if;

  v_result := public.reset_product_import_batch_to_draft(v_batch_b);
  if v_result->>'state' <> 'DRAFT'
     or (v_result->>'staging_revision')::bigint <> 1
     or exists (
       select 1
       from public.products_import_stage
       where batch_id = v_batch_b
         and (
           product_version is not null
           or stock_version is not null
           or price_version is not null
           or planned_action is not null
         )
     ) then
    raise exception 'TEST_FAIL: REVALIDATION_REQUIRED nao voltou limpo para DRAFT';
  end if;

  begin
    perform public.reset_product_import_batch_to_draft(v_batch_a);
    raise exception 'TEST_FAIL: COMMITTED voltou para DRAFT';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: COMMITTED voltou para DRAFT' then
        raise;
      end if;
      if sqlerrm <> 'ESTADO_NAO_PERMITE_RETORNO_DRAFT' then
        raise exception 'TEST_FAIL: erro inesperado no reset COMMITTED: %', sqlerrm;
      end if;
  end;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_failed uuid;
  v_result jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';
  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_PRICES',
    'field_mask', jsonb_build_array('product_code', 'sale_price')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-ZERO',
      'provided_fields', jsonb_build_array('product_code', 'sale_price'),
      'data', jsonb_build_object('sale_price', 0)
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  v_result := public.reset_product_import_batch_to_draft(v_batch);
  if v_result->>'state' <> 'DRAFT' then
    raise exception 'TEST_FAIL: PREVIEWED nao voltou para DRAFT';
  end if;

  select id into v_failed
  from phase2_test_batches where name = 'invalid_numeric';
  begin
    perform public.reset_product_import_batch_to_draft(v_failed);
    raise exception 'TEST_FAIL: FAILED voltou para DRAFT';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: FAILED voltou para DRAFT' then
        raise;
      end if;
      if sqlerrm <> 'ESTADO_NAO_PERMITE_RETORNO_DRAFT' then
        raise exception 'TEST_FAIL: erro inesperado no reset FAILED: %', sqlerrm;
      end if;
  end;
end
$$;

do $$
declare
  v_pr uuid;
  v_current_price numeric;
  v_batch_a uuid;
  v_batch_b uuid;
  v_result jsonb;
  v_rows jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';
  select sale_price into v_current_price
  from public.product_branch_prices
  where product_code = 'TEST-028-ZERO'
    and branch_id = v_pr;

  v_rows := jsonb_build_array(jsonb_build_object(
    'row_number', 1,
    'product_code', 'TEST-028-ZERO',
    'provided_fields', jsonb_build_array('product_code', 'sale_price'),
    'data', jsonb_build_object('sale_price', v_current_price)
  ));

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_PRICES',
    'field_mask', jsonb_build_array('product_code', 'sale_price')
  ));
  v_batch_a := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch_a, v_rows);
  perform public.preview_product_import_batch(v_batch_a);
  perform public.approve_product_import_batch(v_batch_a);

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_PRICES',
    'field_mask', jsonb_build_array('product_code', 'sale_price')
  ));
  v_batch_b := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch_b, v_rows);
  perform public.preview_product_import_batch(v_batch_b);
  perform public.approve_product_import_batch(v_batch_b);

  v_result := public.commit_product_import_batch(v_batch_a);
  if v_result->>'state' <> 'COMMITTED' then
    raise exception 'TEST_FAIL: primeiro lote no-op nao confirmou: %', v_result;
  end if;

  v_result := public.commit_product_import_batch(v_batch_b);
  if coalesce((v_result->>'idempotent')::boolean, false) is not true
     or v_result->>'state' <> 'REVALIDATION_REQUIRED'
     or v_result->>'error' <> 'CONTEUDO_JA_CONFIRMADO'
     or v_result->>'committed_batch_id' <> v_batch_a::text then
    raise exception 'TEST_FAIL: corrida idempotente no-op nao foi controlada: %',
      v_result;
  end if;

  if (select count(*) from public.products_import_batches
      where id in (v_batch_a, v_batch_b)
        and state = 'COMMITTED') <> 1 then
    raise exception 'TEST_FAIL: chave idempotente confirmou dois lotes';
  end if;
end
$$;

insert into auth.users (
  id, aud, role, email, encrypted_password, confirmed_at, created_at, updated_at
)
values
  (
    '02800000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'phase2-seller@example.invalid', '',
    now(), now(), now()
  ),
  (
    '02800000-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'phase2-supervisor@example.invalid', '',
    now(), now(), now()
  ),
  (
    '02800000-0000-4000-8000-000000000004',
    'authenticated', 'authenticated', 'phase2-no-branch@example.invalid', '',
    now(), now(), now()
  );

insert into public.profiles (id, usuario, nome, email, perfil, ativo)
values
  (
    '02800000-0000-4000-8000-000000000002',
    'phase2-seller', 'Phase 2 Seller',
    'phase2-seller@example.invalid', 'VENDEDOR', true
  ),
  (
    '02800000-0000-4000-8000-000000000003',
    'phase2-supervisor', 'Phase 2 Supervisor',
    'phase2-supervisor@example.invalid', 'SUPERVISOR', true
  ),
  (
    '02800000-0000-4000-8000-000000000004',
    'phase2-no-branch', 'Phase 2 No Branch',
    'phase2-no-branch@example.invalid', 'SUPERVISOR', true
  );

insert into public.role_permissions (perfil, modulo, permitido)
values
  ('VENDEDOR', 'alimentacao', true),
  ('VENDEDOR', 'visualizar_lotes_importacao', true),
  ('SUPERVISOR', 'aprovar_importacao', true),
  ('SUPERVISOR', 'alimentacao', true),
  ('SUPERVISOR', 'visualizar_lotes_importacao', true)
on conflict (perfil, modulo) do update set permitido = excluded.permitido;

insert into public.profile_branches (profile_id, branch_id, is_default, active)
select '02800000-0000-4000-8000-000000000002'::uuid, id, true, true
from public.branches where code = 'PR'
union all
select '02800000-0000-4000-8000-000000000003'::uuid, id, true, true
from public.branches where code = 'PR';

do $$
declare
  v_pr uuid;
  v_legacy_pr uuid;
  v_legacy_unscoped uuid;
begin
  select id into v_pr from public.branches where code = 'PR';

  insert into public.products_import_batches (
    created_by,
    import_type,
    region,
    source_name,
    status,
    contract_version,
    branch_id,
    state,
    created_by_profile_id
  )
  values (
    'phase2-admin',
    'legacy-report',
    'PR',
    'legacy-pr.csv',
    'draft',
    0,
    v_pr,
    'DRAFT',
    '02800000-0000-4000-8000-000000000001'
  )
  returning id into v_legacy_pr;

  insert into public.products_import_batches (
    created_by,
    import_type,
    region,
    source_name,
    status,
    contract_version,
    branch_id,
    state,
    created_by_profile_id
  )
  values (
    'phase2-admin',
    'legacy-report',
    null,
    'legacy-unscoped.csv',
    'draft',
    0,
    null,
    'DRAFT',
    '02800000-0000-4000-8000-000000000001'
  )
  returning id into v_legacy_unscoped;

  insert into phase2_test_batches values
    ('legacy_pr', v_legacy_pr),
    ('legacy_unscoped', v_legacy_unscoped);
end
$$;

do $$
declare
  v_sp_batch uuid;
  v_legacy_pr uuid;
  v_legacy_unscoped uuid;
  v_report jsonb;
  v_details jsonb;
  v_preview jsonb;
begin
  select id into v_sp_batch from phase2_test_batches where name = 'sp_stock';
  select id into v_legacy_pr from phase2_test_batches where name = 'legacy_pr';
  select id into v_legacy_unscoped
  from phase2_test_batches where name = 'legacy_unscoped';

  perform set_config(
    'request.jwt.claim.sub',
    '02800000-0000-4000-8000-000000000002',
    true
  );

  v_report := public.get_products_import_batches_report(
    jsonb_build_object('page_size', 100)
  );
  if exists (
       select 1
       from jsonb_array_elements(v_report->'rows') item
       where item->>'id' = v_sp_batch::text
     )
     or exists (
       select 1
       from jsonb_array_elements(v_report->'rows') item
       where item->>'id' = v_legacy_unscoped::text
     )
     or not exists (
       select 1
       from jsonb_array_elements(v_report->'rows') item
       where item->>'id' = v_legacy_pr::text
     ) then
    raise exception 'TEST_FAIL: relatorio legado ignorou escopo de filial/criador';
  end if;

  v_details := public.get_products_import_batch_details(v_sp_batch, 1, 25);
  if v_details->'batch' <> '{}'::jsonb
     or v_details->'items' <> '[]'::jsonb
     or v_details->'audit' <> '[]'::jsonb then
    raise exception 'TEST_FAIL: detalhe legado revelou lote V2 de outra filial';
  end if;

  v_preview := public.preview_products_import_batch(v_legacy_pr);
  if v_preview->>'batch_id' <> v_legacy_pr::text then
    raise exception 'TEST_FAIL: preview legado autorizado foi alterado';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    '02800000-0000-4000-8000-000000000004',
    true
  );
  v_report := public.get_products_import_batches_report(
    jsonb_build_object('page_size', 100)
  );
  if jsonb_array_length(v_report->'rows') <> 0 then
    raise exception 'TEST_FAIL: usuario sem filial recebeu lote em relatorio';
  end if;
  if exists (select 1 from public.get_allowed_import_branches()) then
    raise exception 'TEST_FAIL: usuario sem filial recebeu filial permitida';
  end if;

  v_details := public.get_products_import_batch_details(v_legacy_unscoped, 1, 25);
  if v_details->'batch' <> '{}'::jsonb then
    raise exception 'TEST_FAIL: detalhe legado sem filial vazou para terceiro';
  end if;
end
$$;

create or replace function pg_temp.capture_v2_batch_rpc(
  operation text,
  target_batch_id uuid
)
returns text
language plpgsql
as $$
begin
  case operation
    when 'stage' then
      perform public.stage_product_import_rows(
        target_batch_id,
        jsonb_build_array(jsonb_build_object(
          'row_number', 999,
          'product_code', 'TEST-028-ZERO',
          'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
          'data', jsonb_build_object('physical_qty', 0)
        ))
      );
    when 'reset' then
      perform public.reset_product_import_batch_to_draft(target_batch_id);
    when 'preview' then
      perform public.preview_product_import_batch(target_batch_id);
    when 'approve' then
      perform public.approve_product_import_batch(target_batch_id);
    when 'commit' then
      perform public.commit_product_import_batch(target_batch_id);
    else
      raise exception 'TEST_FAIL: operacao desconhecida %', operation;
  end case;
  return 'NO_ERROR';
exception
  when others then
    return sqlstate || ':' || sqlerrm;
end;
$$;

do $$
declare
  v_owner_batch uuid;
  v_sp_batch uuid;
  v_pr_batch uuid;
  v_missing constant uuid := '02800000-0000-4000-8000-ffffffffffff';
  v_operation text;
  v_known_result text;
  v_missing_result text;
begin
  select id into v_owner_batch
  from phase2_test_batches where name = 'legacy_bypass_v2';
  select id into v_sp_batch from phase2_test_batches where name = 'sp_stock';
  select id into v_pr_batch from phase2_test_batches where name = 'pr_stock';

  perform set_config(
    'request.jwt.claim.sub',
    '02800000-0000-4000-8000-000000000002',
    true
  );

  foreach v_operation in array array['stage', 'reset']
  loop
    v_known_result := pg_temp.capture_v2_batch_rpc(v_operation, v_owner_batch);
    v_missing_result := pg_temp.capture_v2_batch_rpc(v_operation, v_missing);
    if v_known_result <> 'P2811:IMPORTACAO_NAO_AUTORIZADA'
       or v_missing_result <> v_known_result then
      raise exception
        'TEST_FAIL: % revelou proprietario/UUID: % / %',
        v_operation,
        v_known_result,
        v_missing_result;
    end if;
  end loop;

  foreach v_operation in array array['preview', 'approve', 'commit']
  loop
    v_known_result := pg_temp.capture_v2_batch_rpc(v_operation, v_sp_batch);
    v_missing_result := pg_temp.capture_v2_batch_rpc(v_operation, v_missing);
    if v_known_result <> 'P2811:IMPORTACAO_NAO_AUTORIZADA'
       or v_missing_result <> v_known_result then
      raise exception
        'TEST_FAIL: % revelou filial/UUID: % / %',
        v_operation,
        v_known_result,
        v_missing_result;
    end if;
  end loop;

  update public.profiles
  set ativo = false
  where id = '02800000-0000-4000-8000-000000000002';

  if exists (select 1 from public.get_allowed_import_branches()) then
    raise exception 'TEST_FAIL: perfil inativo recebeu filial permitida';
  end if;

  v_known_result := pg_temp.capture_v2_batch_rpc('preview', v_pr_batch);
  v_missing_result := pg_temp.capture_v2_batch_rpc('preview', v_missing);
  if v_known_result <> 'P2811:IMPORTACAO_NAO_AUTORIZADA'
     or v_missing_result <> v_known_result then
    raise exception
      'TEST_FAIL: perfil inativo revelou lote: % / %',
      v_known_result,
      v_missing_result;
  end if;

  update public.profiles
  set ativo = true
  where id = '02800000-0000-4000-8000-000000000002';

  update public.products_import_batches
  set created_by_profile_id = null,
      created_by = null
  where id = v_owner_batch;

  v_known_result := pg_temp.capture_v2_batch_rpc('stage', v_owner_batch);
  v_missing_result := pg_temp.capture_v2_batch_rpc('stage', v_missing);
  if v_known_result <> 'P2811:IMPORTACAO_NAO_AUTORIZADA'
     or v_missing_result <> v_known_result then
    raise exception
      'TEST_FAIL: owner nulo concedeu acesso: % / %',
      v_known_result,
      v_missing_result;
  end if;
end
$$;

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_committed_batch uuid;
  v_result jsonb;
  v_known_error text;
  v_missing_error text;
  v_known_state text;
  v_missing_state text;
begin
  select id into v_pr from public.branches where code = 'PR';

  perform set_config(
    'request.jwt.claim.sub',
    '02800000-0000-4000-8000-000000000004',
    true
  );

  select id into v_committed_batch
  from phase2_test_batches where name = 'pr_stock';

  begin
    perform public.commit_product_import_batch(v_committed_batch);
    raise exception 'TEST_FAIL: usuario sem filial leu lote COMMITTED';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: usuario sem filial leu lote COMMITTED' then
        raise;
      end if;
      v_known_error := sqlerrm;
      v_known_state := sqlstate;
  end;

  begin
    perform public.commit_product_import_batch(
      '02800000-0000-4000-8000-ffffffffffff'::uuid
    );
    raise exception 'TEST_FAIL: lote inexistente foi aceito';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: lote inexistente foi aceito' then
        raise;
      end if;
      v_missing_error := sqlerrm;
      v_missing_state := sqlstate;
  end;

  if v_known_state <> 'P2811'
     or v_missing_state <> 'P2811'
     or v_known_error <> 'IMPORTACAO_NAO_AUTORIZADA'
     or v_missing_error <> 'IMPORTACAO_NAO_AUTORIZADA' then
    raise exception 'TEST_FAIL: lote COMMITTED revelou existencia ou resumo';
  end if;

  begin
    perform public.create_product_import_batch(jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_STOCK',
      'field_mask', jsonb_build_array('product_code', 'physical_qty')
    ));
    raise exception 'TEST_FAIL: usuario sem filial criou lote';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: usuario sem filial criou lote' then
        raise;
      end if;
      if sqlerrm <> 'SEM_ACESSO_FILIAL' then
        raise exception 'TEST_FAIL: erro inesperado sem filial: %', sqlerrm;
      end if;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    '02800000-0000-4000-8000-000000000002',
    true
  );
  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_STOCK',
    'field_mask', jsonb_build_array('product_code', 'physical_qty')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-ZERO',
      'provided_fields', jsonb_build_array('product_code', 'physical_qty'),
      'data', jsonb_build_object('physical_qty', 4)
    )
  ));
  perform public.preview_product_import_batch(v_batch);

  perform set_config(
    'request.jwt.claim.sub',
    '02800000-0000-4000-8000-000000000003',
    true
  );
  perform public.approve_product_import_batch(v_batch);
  v_result := public.commit_product_import_batch(v_batch);
  if v_result->>'state' <> 'COMMITTED' then
    raise exception 'TEST_FAIL: aprovador nao confirmou lote: %', v_result;
  end if;
end
$$;

select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  true
);

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
  v_error text;
  v_state text;
  v_description_before text;
  v_stock_before numeric;
  v_movement_count integer;
  v_attempt_count integer;
begin
  select id into v_pr from public.branches where code = 'PR';
  select descricao into v_description_before
  from public.products where codigo = 'TEST-028-ZERO';
  select physical_qty into v_stock_before
  from public.product_branch_stock
  where product_code = 'TEST-028-ZERO' and branch_id = v_pr;
  select count(*) into v_movement_count
  from public.stock_movements
  where product_code = 'TEST-028-ZERO' and branch_id = v_pr;

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'CUSTOM_UPDATE',
    'field_mask', jsonb_build_array(
      'product_code', 'description', 'physical_qty', 'sale_price'
    )
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-ZERO',
      'provided_fields', jsonb_build_array(
        'product_code', 'description', 'physical_qty', 'sale_price'
      ),
      'data', jsonb_build_object(
        'description', 'Nao deve persistir',
        'physical_qty', 5,
        'sale_price', 123.4567
      )
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  select attempt_count into v_attempt_count
  from public.products_import_batches where id = v_batch;

  alter table public.product_branch_prices
    add constraint phase2_test_forced_price_failure
    check (sale_price <> 123.4567);

  begin
    perform public.commit_product_import_batch(v_batch);
    raise exception 'TEST_FAIL: erro interno nao abortou a chamada';
  exception
    when others then
      if sqlerrm = 'TEST_FAIL: erro interno nao abortou a chamada' then
        raise;
      end if;
      v_error := sqlerrm;
      v_state := sqlstate;
  end;

  alter table public.product_branch_prices
    drop constraint phase2_test_forced_price_failure;

  if v_state <> 'P2899'
     or v_error <> 'IMPORTACAO_FALHOU'
     or v_error ilike '%constraint%'
     or v_error ilike '%product_branch_prices%' then
    raise exception 'TEST_FAIL: erro interno vazou detalhe: % / %', v_state, v_error;
  end if;
  if (select state from public.products_import_batches where id = v_batch)
       <> 'APPROVED'
     or (select attempt_count from public.products_import_batches where id = v_batch)
       <> v_attempt_count
     or (select descricao from public.products where codigo = 'TEST-028-ZERO')
       is distinct from v_description_before
     or (select physical_qty from public.product_branch_stock
         where product_code = 'TEST-028-ZERO' and branch_id = v_pr)
       is distinct from v_stock_before
     or (select count(*) from public.stock_movements
         where product_code = 'TEST-028-ZERO' and branch_id = v_pr)
       <> v_movement_count
     or exists (
       select 1 from public.products_import_audit where batch_id = v_batch
     ) then
    raise exception 'TEST_FAIL: erro interno deixou alteracao parcial';
  end if;
end
$$;

grant select on phase2_test_batches to authenticated;

set local role authenticated;

do $$
declare
  v_pr uuid;
  v_sp uuid;
  v_pr_batch uuid;
  v_sp_batch uuid;
  v_legacy_created uuid;
  v_result jsonb;
  v_target text;
begin
  select id into v_pr from public.branches where code = 'PR';
  select id into v_sp from public.branches where code = 'SP';
  select id into v_pr_batch from phase2_test_batches where name = 'pr_stock';
  select id into v_sp_batch from phase2_test_batches where name = 'sp_stock';

  perform set_config(
    'request.jwt.claim.sub',
    '02800000-0000-4000-8000-000000000002',
    true
  );

  if not exists (
       select 1 from public.product_branch_prices where branch_id = v_pr
     )
     or exists (
       select 1 from public.product_branch_prices where branch_id = v_sp
     )
     or not exists (
       select 1 from public.product_branch_stock where branch_id = v_pr
     )
     or exists (
       select 1 from public.product_branch_stock where branch_id = v_sp
     ) then
    raise exception 'TEST_FAIL: leitura cruzada PR/SP permitida pela RLS';
  end if;

  if not exists (
       select 1 from public.products_import_batches where id = v_pr_batch
     )
     or exists (
       select 1 from public.products_import_batches where id = v_sp_batch
     )
     or not exists (
       select 1 from public.products_import_stage where batch_id = v_pr_batch
     )
     or exists (
       select 1 from public.products_import_stage where batch_id = v_sp_batch
     )
     or not exists (
       select 1 from public.products_import_audit where batch_id = v_pr_batch
     )
     or exists (
       select 1 from public.products_import_audit where batch_id = v_sp_batch
     ) then
    raise exception
      'TEST_FAIL: helper de policy nao isolou batches/stage/audit por filial';
  end if;

  if public.can_access_product_import_batch_row(
       1,
       v_sp,
       '02800000-0000-4000-8000-000000000002'::uuid,
       'phase2-seller',
       false,
       false,
       true
     ) then
    raise exception 'TEST_FAIL: helper aceitou filial externa';
  end if;

  foreach v_target in array array[
    'products_import_batches',
    'products_import_stage',
    'products_import_audit'
  ]
  loop
    begin
      execute format('delete from public.%I where false', v_target);
      raise exception 'TEST_FAIL: authenticated obteve escrita direta em %',
        v_target;
    exception
      when insufficient_privilege then
        null;
    end;
  end loop;

  begin
    insert into public.product_branch_prices (
      product_code, branch_id, sale_price, source
    )
    values ('TEST-028-POSITIVE', v_pr, 1, 'MANUAL');
    raise exception 'TEST_FAIL: authenticated escreveu diretamente';
  exception
    when insufficient_privilege then
      null;
  end;

  v_result := public.create_products_import_batch(jsonb_build_object(
    'import_type', 'CADASTRO_COMPLETO',
    'region', 'PR',
    'source_name', 'phase2-v0-seller.csv',
    'products', jsonb_build_array(jsonb_build_object(
      'row_number', 1,
      'codigo', 'TEST-028-POSITIVE',
      'descricao', 'Fixture preco positivo'
    ))
  ));
  v_legacy_created := (v_result->>'batch_id')::uuid;

  if v_legacy_created is null
     or v_result->>'status' <> 'validated'
     or not (v_result ?& array[
       'batch_id', 'status', 'summary', 'errors',
       'warnings', 'differences', 'preview'
     ])
     or (select contract_version from public.products_import_batches
         where id = v_legacy_created) <> 0
     or (select branch_id from public.products_import_batches
         where id = v_legacy_created) is distinct from v_pr
     or (select created_by_profile_id from public.products_import_batches
         where id = v_legacy_created)
        is distinct from '02800000-0000-4000-8000-000000000002'::uuid then
    raise exception 'TEST_FAIL: criacao V0 perdeu contrato ou escopo: %', v_result;
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    '02800000-0000-4000-8000-000000000003',
    true
  );
  v_result := public.approve_products_import_batch(v_legacy_created);

  if v_result->>'status' <> 'approved'
     or (select status from public.products_import_batches
         where id = v_legacy_created) <> 'approved' then
    raise exception
      'TEST_FAIL: supervisor da mesma filial nao aprovou lote V0: %',
      v_result;
  end if;
end
$$;

reset role;

rollback;

-- Os ensaios que exigem efeitos persistentes sao coordenados por
-- docs/BRANCH_IMPORTS_PHASE2.md:
-- 1. duas sessoes reais disputando TEST-028-CONCURRENT;
-- 2. duas sessoes reais disputando a mesma chave no-op;
-- 3. injecao controlada da unique_violation de ultima defesa;
-- 4. lock_timeout conhecido preservando APPROVED;
-- 5. rollback estrutural permitido em clone sem uso;
-- 6. rollback bloqueado em clone com lote COMMITTED;
-- 7. preflight textual bloqueando funcao PL/pgSQL externa;
-- 8. comparacao das seis funcoes legadas antes/durante/depois do rollback;
-- 9. overload externa homonima bloqueada pelo preflight por OID/assinatura;
-- 10. relacl e has_table_privilege antes/durante/depois do rollback;
-- 11. funcao/policy alheias com termos genericos nao bloqueando o rollback.
