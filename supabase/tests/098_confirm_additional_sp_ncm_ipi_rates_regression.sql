begin;

do $$
declare
  v_row record;
  v_rule_count integer;
  v_product_count integer;
  v_invalid_count integer;
begin
  for v_row in
    select * from (values
      ('87088000'::text, 0.03250000::numeric, '539'::text),
      ('87082999'::text, 0.03250000::numeric, '512'::text),
      ('85122011'::text, 0.09750000::numeric, '296'::text),
      ('87089483'::text, 0.03250000::numeric, '593'::text),
      ('87082993'::text, 0.03250000::numeric, '485'::text),
      ('87089990'::text, 0.03250000::numeric, '647'::text),
      ('87081000'::text, 0.03250000::numeric, '431'::text),
      ('87082991'::text, 0.03250000::numeric, '458'::text),
      ('85122021'::text, 0.09750000::numeric, '350'::text),
      ('87089100'::text, 0.03250000::numeric, '566'::text),
      ('84212300'::text, 0.05200000::numeric, '107'::text),
      ('84821010'::text, 0.07800000::numeric, '188'::text)
    ) as confirmed(ncm, ipi_rate, source_code)
  loop
    if not exists(
      select 1
      from public.fiscal_tax_rules r
      where r.ncm = v_row.ncm
        and r.uf_origem = 'SP'
        and r.uf_destino = 'SP'
        and r.operation_type = 'VENDA'
        and r.customer_type = 'GERAL'
        and r.active
        and r.lifecycle_status = 'ACTIVE'
        and r.ipi_rate = v_row.ipi_rate
        and r.source = 'SAP_FISCAL'
        and r.source_code = v_row.source_code
        and r.effective_from <= date '2026-10-01'
        and (r.effective_to is null or r.effective_to >= date '2026-10-01')
    ) then
      raise exception 'REGRA_098_NAO_CONFIRMADA: %', v_row.ncm;
    end if;
  end loop;

  select count(*) into v_rule_count
  from public.fiscal_tax_rules r
  where r.ncm = any(array[
      '87088000','87082999','85122011','87089483','87082993','87089990',
      '87081000','87082991','85122021','87089100','84212300','84821010'
    ])
    and r.uf_origem = 'SP'
    and r.uf_destino = 'SP'
    and r.operation_type = 'VENDA'
    and r.customer_type = 'GERAL'
    and r.active
    and r.lifecycle_status = 'ACTIVE';

  if v_rule_count <> 12 then
    raise exception 'QUANTIDADE_REGRAS_098_INVALIDA: %', v_rule_count;
  end if;

  if exists(
    select 1
    from public.fiscal_tax_rules legacy
    join public.fiscal_tax_rules successor
      on successor.ncm = legacy.ncm
     and successor.uf_origem = legacy.uf_origem
     and successor.uf_destino = legacy.uf_destino
     and successor.operation_type = legacy.operation_type
     and successor.customer_type = legacy.customer_type
     and daterange(successor.effective_from, successor.effective_to, '[]')
         && daterange(legacy.effective_from, legacy.effective_to, '[]')
    where legacy.ncm = '87089990'
      and legacy.source = 'MANUAL'
      and successor.source = 'SAP_FISCAL'
      and successor.source_code = '647'
      and legacy.active
      and successor.active
  ) then
    raise exception 'VIGENCIAS_87089990_SOBREPOSTAS';
  end if;

  with evaluated as (
    select public.apply_commercial_tax_policy(
      jsonb_build_object(
        'product_code', rp.product_code,
        'route', rp.route,
        'origin_state', 'SP',
        'destination_state', 'SP',
        'base_price', rp.base_price,
        'total_taxes', rp.total_taxes,
        'final_price', rp.final_price,
        'ipi_amount', rp.tax_breakdown->'ipi',
        'icms_st_amount', rp.tax_breakdown->'icms_st',
        'tax_breakdown', rp.tax_breakdown,
        'status', coalesce(rp.calculation_status, 'OK'),
        'warnings', '[]'::jsonb
      ),
      'SP',
      'SP',
      date '2026-10-06'
    ) calc
    from public.product_route_prices rp
    join public.branches b
      on b.id = rp.origin_branch_id
     and b.code = 'SP'
     and b.active
    join public.products p
      on p.codigo = rp.product_code
    where rp.route = 'SP-SP'
      and p.ncm = any(array[
        '87088000','87082999','85122011','87089483','87082993','87089990',
        '87081000','87082991','85122021','87089100','84212300','84821010'
      ])
  )
  select count(*), count(*) filter(
    where calc->>'validation_status' <> 'MATCH'
       or calc->>'status' <> 'OK_SEM_ST'
       or coalesce((calc->>'tax_policy_applied')::boolean, false) is not true
  )
  into v_product_count, v_invalid_count
  from evaluated;

  if v_product_count = 0 then
    raise exception 'REFERENCIA_SP_SP_098_AUSENTE';
  end if;
  if v_invalid_count <> 0 then
    raise exception 'REFERENCIA_SP_SP_098_DIVERGENTE: % de %', v_invalid_count, v_product_count;
  end if;
end;
$$;

rollback;
