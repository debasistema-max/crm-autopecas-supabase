begin;

drop function if exists public.b2b_create_document(text,jsonb);
alter function public.b2b_create_document_raw_090(text,jsonb) rename to b2b_create_document;
grant execute on function public.b2b_create_document(text,jsonb) to authenticated;

drop function if exists public.b2b_get_catalog_product_detail(text);
alter function public.b2b_get_catalog_product_detail_raw_090(text) rename to b2b_get_catalog_product_detail;
grant execute on function public.b2b_get_catalog_product_detail(text) to authenticated;

drop function if exists public.b2b_search_catalog(text,text,boolean,integer);
alter function public.b2b_search_catalog_raw_090(text,text,boolean,integer) rename to b2b_search_catalog;
grant execute on function public.b2b_search_catalog(text,text,boolean,integer) to authenticated;

drop function if exists public.convert_quotation_to_order(uuid);
alter function public.convert_quotation_to_order_raw_090(uuid) rename to convert_quotation_to_order;
grant execute on function public.convert_quotation_to_order(uuid) to authenticated;

drop function if exists public.commercial_update_document_items(text,jsonb);
alter function public.commercial_update_document_items_raw_090(text,jsonb) rename to commercial_update_document_items;
grant execute on function public.commercial_update_document_items(text,jsonb) to authenticated;

drop function if exists public.commercial_create_document(text,jsonb);
alter function public.commercial_create_document_raw_090(text,jsonb) rename to commercial_create_document;
grant execute on function public.commercial_create_document(text,jsonb) to authenticated;

drop function if exists public.normalize_document_tax_policy(text,uuid);

drop function if exists public.get_product_commercial_price(text,text,text,date,text);
alter function public.get_product_commercial_price_raw_090(text,text,text,date,text)
  rename to get_product_commercial_price;
grant execute on function public.get_product_commercial_price(text,text,text,date,text) to authenticated;

drop function if exists public.apply_commercial_tax_policy(jsonb,text,text,date);
drop function if exists public.commercial_business_date();
drop table if exists public.commercial_tax_policies;

commit;
