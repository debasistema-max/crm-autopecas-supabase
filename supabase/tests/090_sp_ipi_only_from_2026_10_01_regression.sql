begin;

do $$
declare
  v_source jsonb:=jsonb_build_object(
    'product_code','TESTE-SP-090','route','SP-SP','origin_state','SP','destination_state','SP',
    'base_price',100,'total_taxes',23.25,'final_price',123.25,
    'ipi_amount',3.25,'icms_st_amount',20,
    'tax_breakdown',jsonb_build_object('ipi',3.25,'icms_proprio',12,'icms_st',20),
    'status','OK','warnings','[]'::jsonb,'price_source','EXCEL_ROUTE_PRICE'
  );
  v_before jsonb;
  v_after jsonb;
  v_pr jsonb;
begin
  v_before:=public.apply_commercial_tax_policy(v_source,'SP','SP',date '2026-09-30');
  if v_before is distinct from v_source then
    raise exception 'POLITICA_SP_ATIVADA_ANTES_DA_VIGENCIA: %',v_before;
  end if;

  v_after:=public.apply_commercial_tax_policy(v_source,'SP','SP',date '2026-10-01');
  if v_after->>'status'<>'OK_SEM_ST'
     or v_after->>'price_source'<>'EXCEL_ROUTE_PRICE_SP_IPI_ONLY'
     or coalesce((v_after->>'tax_policy_applied')::boolean,false) is not true
     or (v_after->>'base_price')::numeric<>100
     or (v_after->>'total_taxes')::numeric<>3.25
     or (v_after->>'final_price')::numeric<>103.25
     or (v_after->>'ipi_amount')::numeric<>3.25
     or (v_after->>'icms_st_amount')::numeric<>0
     or (v_after#>>'{tax_breakdown,icms_st}')::numeric<>0
     or (v_after->>'source_final_price')::numeric<>123.25
     or (v_after->>'source_total_taxes')::numeric<>23.25 then
    raise exception 'POLITICA_SP_IPI_INCORRETA: %',v_after;
  end if;

  v_pr:=public.apply_commercial_tax_policy(v_source||jsonb_build_object('route','PR-PR'),'PR','PR',date '2026-10-01');
  if v_pr is distinct from (v_source||jsonb_build_object('route','PR-PR')) then
    raise exception 'POLITICA_SP_ALTEROU_OUTRA_ROTA: %',v_pr;
  end if;

  if has_function_privilege('authenticated','public.get_product_commercial_price_raw_090(text,text,text,date,text)','EXECUTE')
     or has_function_privilege('authenticated','public.normalize_document_tax_policy(text,uuid)','EXECUTE') then
    raise exception 'FUNCAO_INTERNA_EXPOSTA';
  end if;
  if not has_function_privilege('authenticated','public.get_product_commercial_price(text,text,text,date,text)','EXECUTE') then
    raise exception 'FUNCAO_COMERCIAL_SEM_ACESSO_AUTENTICADO';
  end if;
end;
$$;

rollback;
