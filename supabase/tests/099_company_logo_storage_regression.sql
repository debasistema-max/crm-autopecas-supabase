begin;

do $test$
declare
  v_bucket storage.buckets%rowtype;
begin
  select * into v_bucket
  from storage.buckets
  where id = 'company-assets';

  if not found then
    raise exception 'Bucket company-assets nao foi criado';
  end if;
  if not v_bucket.public then
    raise exception 'O logo precisa ser publico para aparecer antes do login';
  end if;
  if v_bucket.file_size_limit <> 2097152 then
    raise exception 'Limite do logo diferente de 2 MB';
  end if;
  if not (v_bucket.allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']::text[]) then
    raise exception 'Tipos de imagem esperados nao estao permitidos';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'company_assets_admin_insert'
      and roles = array['authenticated']::name[]
      and with_check like '%is_admin()%'
      and with_check like '%identity/%'
  ) then
    raise exception 'Politica de upload administrativo ausente ou ampla demais';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'company_assets_admin_delete'
      and roles = array['authenticated']::name[]
      and qual like '%is_admin()%'
      and qual like '%identity/%'
  ) then
    raise exception 'Politica de exclusao administrativa ausente ou ampla demais';
  end if;
end;
$test$;

rollback;
