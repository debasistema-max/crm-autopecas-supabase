drop policy if exists company_assets_admin_delete on storage.objects;
drop policy if exists company_assets_admin_insert on storage.objects;

-- Preserva os arquivos enviados em um rollback. O bucket deixa de ser publico,
-- mas nao e removido para evitar perda irreversivel de dados do usuario.
update storage.buckets
set public = false
where id = 'company-assets';
