begin;

do $$
declare
  v_search_definition text;
  v_detail_definition text;
  v_search_compact text;
  v_detail_compact text;
begin
  select pg_get_functiondef(
    'public.b2b_search_catalog(text,text,boolean,integer)'::regprocedure
  ) into v_search_definition;
  select pg_get_functiondef(
    'public.b2b_get_catalog_product_detail(text)'::regprocedure
  ) into v_detail_definition;

  v_search_compact:=regexp_replace(v_search_definition,'[[:space:]]','','g');
  v_detail_compact:=regexp_replace(v_detail_definition,'[[:space:]]','','g');

  if position('upper(coalesce(e.calc->>''status'',''''))like''OK%''' in v_search_compact)=0 then
    raise exception 'BUSCA_B2B_NAO_ACEITA_STATUS_OK_DA_PLANILHA';
  end if;
  if position('upper(coalesce(v_calc->>''status'',''''))notlike''OK%''' in v_detail_compact)=0 then
    raise exception 'DETALHE_B2B_NAO_ACEITA_STATUS_OK_DA_PLANILHA';
  end if;

  if position('e.calc->>''status''in(''OK'',''OK_SEM_ST'')' in v_search_compact)>0 then
    raise exception 'FILTRO_EXATO_ANTIGO_PERMANECE_NA_BUSCA';
  end if;
  if position('v_calc->>''status''notin(''OK'',''OK_SEM_ST'')' in v_detail_compact)>0 then
    raise exception 'FILTRO_EXATO_ANTIGO_PERMANECE_NO_DETALHE';
  end if;
end;
$$;

rollback;
