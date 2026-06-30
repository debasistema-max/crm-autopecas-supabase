-- Execute depois de criar o usuario admin em Supabase Auth.
-- Troque os valores abaixo pelo UUID e e-mail do usuario criado.

insert into public.profiles (
  id,
  legacy_id,
  usuario,
  nome,
  email,
  perfil,
  ativo
) values (
  'COLE_AQUI_O_UUID_DO_AUTH_USER'::uuid,
  'admin',
  'admin',
  'Administrador',
  'admin@seudominio.com',
  'ADMIN',
  true
)
on conflict (id) do update set
  usuario = excluded.usuario,
  nome = excluded.nome,
  email = excluded.email,
  perfil = excluded.perfil,
  ativo = excluded.ativo;
