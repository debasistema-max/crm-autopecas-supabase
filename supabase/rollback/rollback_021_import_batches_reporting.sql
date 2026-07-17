-- Rollback manual da migration 021_import_batches_reporting.sql.
-- Nao executar automaticamente. Este arquivo remove somente objetos criados pela 021.
-- Nao remove tabelas, dados, nem objetos criados pela migration 020.

drop policy if exists products_import_batches_read on public.products_import_batches;
drop policy if exists products_import_stage_read on public.products_import_stage;
drop policy if exists products_import_audit_read on public.products_import_audit;

drop function if exists public.get_products_import_batch_details(uuid, integer, integer);
drop function if exists public.get_products_import_batches_report(jsonb);
drop function if exists public.can_view_products_import_batches();

drop index if exists public.products_import_stage_status_idx;
drop index if exists public.products_import_batches_created_by_idx;
drop index if exists public.products_import_batches_region_idx;

-- Remover apenas se a permissao foi criada exclusivamente para a 021 e nao estiver em uso operacional.
delete from public.role_permissions
where modulo = 'visualizar_lotes_importacao'
  and perfil = 'ADMIN';

-- Opcional: se for necessario manter leitura direta igual ao comportamento anterior,
-- recrie manualmente as policies originais da migration 018 apos avaliar o ambiente.
