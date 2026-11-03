begin;
set local lock_timeout = '10s';
set local statement_timeout = '110s';

-- Preserve the existing RPC and its privileges. Only file-extension case changes.
do $migration$
declare
  target regprocedure := 'public.finish_installed_catalog_sync(uuid,uuid,jsonb)'::regprocedure;
  old_pattern text := '^https://pub-1c42f71f3a974244953a13b83a68b545[.]r2[.]dev/[^?#]+[.](png|jpg|jpeg|webp)$';
  new_pattern text := '^https://pub-1c42f71f3a974244953a13b83a68b545[.]r2[.]dev/[^?#]+[.]([pP][nN][gG]|[jJ][pP][gG]|[jJ][pP][eE][gG]|[wW][eE][bB][pP])$';
  definition text;
  source_before text;
  metadata_before jsonb;
  source_after text;
  metadata_after jsonb;
begin
  select pg_get_functiondef(p.oid), p.prosrc, to_jsonb(p) - 'prosrc'
    into definition, source_before, metadata_before
    from pg_proc p where p.oid = target;
  if strpos(source_before, old_pattern) = 0 and strpos(source_before, new_pattern) > 0 then
    return;
  end if;
  if (length(source_before) - length(replace(source_before, old_pattern, ''))) / length(old_pattern) <> 1
     or strpos(source_before, new_pattern) > 0 then
    raise exception 'CATALOG_IMAGE_VALIDATOR_UNEXPECTED';
  end if;
  execute replace(definition, old_pattern, new_pattern);
  select p.prosrc, to_jsonb(p) - 'prosrc' into source_after, metadata_after
    from pg_proc p where p.oid = target;
  if source_after is distinct from replace(source_before, old_pattern, new_pattern)
     or metadata_after is distinct from metadata_before then
    raise exception 'CATALOG_RPC_CONTRACT_CHANGED';
  end if;
end $migration$;

commit;
