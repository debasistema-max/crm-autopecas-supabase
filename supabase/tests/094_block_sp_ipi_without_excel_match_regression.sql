begin;

do $$
declare
  v_branch_sp uuid;
  v_match jsonb;
  v_mismatch jsonb;
  v_missing jsonb;
  v_pr jsonb;
  v_source jsonb:=jsonb_build_object(
    'product_code','9900000094','route','SP-SP',
    'origin_state','SP','destination_state','SP',
    'base_price',100,'total_taxes',3.25,'final_price',103.25,
    'ipi_amount',3.25,'tax_breakdown',jsonb_build_object('ipi',3.25),
    'status','OK_SEM_ST','warnings','[]'::jsonb,
    'price_source','EXCEL_ROUTE_PRICE'
  );
begin
  select id into v_branch_sp from public.branches where code='SP' and active limit 1;
  if v_branch_sp is null then raise exception 'FILIAL_SP_AUSENTE'; end if;

  insert into public.products(codigo,descricao,ncm,cest,ipi_rate,ipi_defined)
  values('9900000094','TESTE BLOQUEIO VALIDACAO SP','99000094','9999999',0.0325,true)
  on conflict(codigo) do update set ncm=excluded.ncm,cest=excluded.cest,
    ipi_rate=excluded.ipi_rate,ipi_defined=true;

  insert into public.product_branch_prices(product_code,branch_id,sale_price,source)
  values('9900000094',v_branch_sp,100,'MANUAL')
  on conflict(product_code,branch_id) do update set sale_price=100,source='MANUAL';

  perform set_config('app.fiscal_transition','1',true);
  update public.fiscal_tax_rules set active=false
  where ncm='99000094' and uf_origem='SP' and uf_destino='SP'
    and operation_type='VENDA' and customer_type='REVENDA' and active;
  insert into public.fiscal_tax_rules(
    ncm,uf_origem,uf_destino,operation_type,customer_type,
    interstate_icms_rate,internal_icms_rate,mva_rate,ipi_rate,
    pis_rate,cofins_rate,fcp_rate,base_reduction_rate,
    freight_rate,insurance_rate,other_expenses_rate,has_st,
    resale_include_own_icms,effective_from,source,
    lifecycle_status,review_required_at,active
  ) values(
    '99000094','SP','SP','VENDA','REVENDA',
    0.12,0.18,0.40,0.0325,0,0,0,0,0,0,0,true,false,
    date '2026-01-01','TEST','REVIEW_REQUIRED',now(),true
  );

  v_match:=public.apply_commercial_tax_policy(v_source,'SP','SP',date '2026-10-01');
  if v_match->>'status'<>'OK_SEM_ST'
     or v_match->>'validation_status'<>'MATCH'
     or coalesce((v_match->>'tax_policy_applied')::boolean,false) is not true
     or coalesce((v_match->>'tax_policy_validation_blocked')::boolean,true) is not false
     or (v_match->>'final_price')::numeric<>103.25 then
    raise exception 'MATCH_NAO_LIBERADO: %',v_match;
  end if;

  v_mismatch:=public.apply_commercial_tax_policy(
    v_source||jsonb_build_object('ipi_amount',0,'final_price',100,
      'tax_breakdown',jsonb_build_object('ipi',0)),
    'SP','SP',date '2026-10-01'
  );
  if v_mismatch->>'status'<>'PRECO_FISCAL_INDISPONIVEL'
     or v_mismatch->>'validation_status'<>'MISMATCH'
     or v_mismatch->>'price_source'<>'CRM_FISCAL_ENGINE_BLOCKED'
     or v_mismatch->'final_price'<>'null'::jsonb
     or coalesce((v_mismatch->>'tax_policy_validation_blocked')::boolean,false) is not true
     or coalesce((v_mismatch->>'tax_policy_applied')::boolean,true) is not false
     or not (v_mismatch->'warnings' ? 'VALIDACAO_FISCAL_PENDENTE') then
    raise exception 'MISMATCH_NAO_BLOQUEADO: %',v_mismatch;
  end if;

  v_missing:=public.apply_commercial_tax_policy(
    v_source||jsonb_build_object('status','PRECO_FISCAL_INDISPONIVEL',
      'final_price',null,'total_taxes',null,'tax_breakdown','{}'::jsonb),
    'SP','SP',date '2026-10-01'
  );
  if v_missing->>'status'<>'PRECO_FISCAL_INDISPONIVEL'
     or v_missing->>'validation_status'<>'EXCEL_REFERENCE_MISSING'
     or coalesce((v_missing->>'tax_policy_validation_blocked')::boolean,false) is not true then
    raise exception 'REFERENCIA_AUSENTE_NAO_BLOQUEADA: %',v_missing;
  end if;

  v_pr:=public.apply_commercial_tax_policy(
    v_source||jsonb_build_object('route','PR-PR'),'PR','PR',date '2026-10-01'
  );
  if v_pr is distinct from (v_source||jsonb_build_object('route','PR-PR')) then
    raise exception 'BLOQUEIO_SP_ALTEROU_OUTRA_ROTA: %',v_pr;
  end if;

  if has_function_privilege(
    'authenticated',
    'public.apply_commercial_tax_policy_raw_094(jsonb,text,text,date)',
    'EXECUTE'
  ) then
    raise exception 'FUNCAO_INTERNA_094_EXPOSTA';
  end if;
end;
$$;

rollback;
