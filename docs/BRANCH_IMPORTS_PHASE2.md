# Importacao por filial - Fase 2

## Escopo

Esta fase adiciona somente a base de banco para importacoes de cadastro, estoque
e preco por filial. Nao altera frontend, pedidos, cotacoes, Dashboard ou o banco
remoto.

Branch: `feature/branch-imports-phase2`.

Base: `11a1e1c7b5608796ac2a7551c6626eafcea8663d`.

## Divergencias encontradas no schema real

- `products` usa `codigo text` como chave primaria e nao possui UUID.
- `product_branch_stock` e `stock_movements` ja usam `product_code text`.
- Os lotes atuais usam `status` em minusculas e responsaveis em colunas textuais.
- `products_import_stage` guarda colunas regionais SP/PR e JSON normalizado.
- `products_import_audit` ja possui auditoria por campo desde a migration 020.
- `profiles.id` e o mesmo UUID de `auth.users.id`.
- As RPCs atuais continuam com nomes no plural, mas a 028 instala wrappers de
  compatibilidade que aceitam exclusivamente `contract_version = 0`.
- O trigger legado chama `sync_legacy_product_stock_to_pr()` em INSERT de produto
  e UPDATE de `estoque_quantidade`.

Por compatibilidade, a 028 adiciona `state`, `contract_version`, UUIDs de
responsaveis e campos V2 sem remover ou reinterpretar os contratos antigos.
Lotes existentes recebem `contract_version = 0`.

## Precos por filial

`product_branch_prices` usa chave composta `(product_code, branch_id)`.

Campos:

- preco de venda `numeric(14,4)`;
- moeda ISO de tres letras;
- versao iniciada em 1;
- origem `LEGACY_BACKFILL`, `LEGACY_SYNC`, `BRANCH_IMPORT_V2` ou `MANUAL`;
- lote de origem somente para importacao V2;
- usuario e timestamps.

Alteracao sem mudanca efetiva nao incrementa versao nem altera `updated_at`.
Escrita direta nao e concedida a usuarios autenticados.

Durante a transicao, o trigger
`products_sync_legacy_prices_to_branches` replica alteracoes reais de
`products.preco_pr` somente para PR e de `products.preco_sp` somente para SP.
Nulo remove a linha da filial, zero cria ou preserva preco zero e no-op nao
altera versao nem proveniencia. Uma escrita legada explicita prevalece sobre o
valor por filial e registra `LEGACY_SYNC`. Dentro da RPC V2, o marcador
transacional `app.price_sync_source = BRANCH_IMPORT_V2` impede a dupla
sincronizacao; nesse caso a RPC grava o preco por filial e espelha a coluna
legada sem permitir que o trigger substitua `source` ou `source_batch_id`.
Nao existe sincronizacao automatica no sentido inverso.

## Backfill

- `products.preco_pr is not null` gera linha na Matriz PR;
- `products.preco_sp is not null` gera linha na Filial SP;
- zero e preservado como preco valido;
- nulo nao gera linha;
- linha existente divergente bloqueia a migration;
- todas as linhas iniciais usam `LEGACY_BACKFILL`.

## Modos e mascara

Modos V2:

- `UPDATE_STOCK`;
- `UPDATE_PRICES`;
- `CREATE_PRODUCTS`;
- `CUSTOM_UPDATE`;
- `FULL_IMPORT`.

Campos canonicos:

`product_code`, `description`, `brand`, `application`, `year`, `ipi`,
`tax_free_price`, `stock_label`, `physical_qty`, `sale_price`, `currency`,
`stock_status`, `registration_status`, `image_url`, `group`, `category`,
`manufacturer`, `details`, `oem` e `similar`.

Campo desconhecido ou proibido pelo modo bloqueia o staging ou preview. Vazio
nao apaga valor existente. Zero numerico e valor explicito.

## Estados

Fluxo principal:

`DRAFT -> PREVIEWED -> APPROVED -> COMMITTING -> COMMITTED`

Transicoes adicionais:

- `PREVIEWED -> DRAFT`;
- `APPROVED -> REVALIDATION_REQUIRED`;
- `REVALIDATION_REQUIRED -> reset_product_import_batch_to_draft -> DRAFT`;
- `DRAFT -> novo preview -> PREVIEWED`;
- `DRAFT`, `PREVIEWED` ou `APPROVED` podem terminar em `FAILED`;
- `FAILED` e terminal;
- falha tecnica transitoria preserva `APPROVED` e registra a tentativa.

`COMMITTING` existe apenas dentro da transacao da RPC de commit. Uma falha nao
deixa lote preso nesse estado.

As RPCs sao a unica fronteira operacional suportada para transicoes. O papel
`authenticated` nao possui escrita direta nas tabelas de lote. Escrita pelo
owner, `service_role` ou por operacao administrativa manual pode violar a
maquina de estados e fica fora do contrato desta fase.

## Hash e idempotencia

O contrato V2 inicial e uma lista fechada definida pelo backend:

- `contract_version = 1`;
- `normalization_algorithm = branch-import-v1`;
- `hash_algorithm = SHA-256`.

Valores enviados pelo cliente servem apenas para validacao e qualquer
divergencia bloqueia o lote. Versoes futuras exigirao uma nova combinacao
explicitamente aceita pelo banco; texto arbitrario nunca cria um contrato.
Quando `contract_version` for enviado, somente o numero JSON inteiro canonico
`1` e aceito. Texto `"1"`, texto com espacos, `1.0` e `null` sao recusados
antes de qualquer cast. Os algoritmos aceitam apenas strings exatamente iguais
a `branch-import-v1` e `SHA-256`, sem trim, aliases ou mudanca de caixa.

O hash autoritativo e calculado no banco sobre:

- algoritmo de normalizacao, algoritmo de hash e versao do contrato;
- filial e modo;
- mascara ordenada;
- linhas de staging em ordem;
- codigo normalizado;
- campos fornecidos ordenados;
- somente os valores tipados e canonicos das chaves presentes na mascara.

Numeros semanticamente iguais, como `1`, `1.0` e `1.0000`, produzem a mesma
representacao. Texto recebe somente trim externo e preserva espacos internos.
Ausencia, `null`, texto vazio e zero possuem representacoes distintas. Chave
extra ou nome nao canonico e recusado. O hash do frontend e apenas consultivo.

## Escritor unico de estoque

A RPC usa:

`set_config('app.stock_sync_source', 'BRANCH_IMPORT_V2', true)`

O trigger da 027 retorna sem sincronizar quando esse marcador esta ativo. Fora
dele, sua definicao e comportamento permanecem iguais aos da 027.

O novo fluxo:

1. atualiza o saldo da filial;
2. cria exatamente um movimento `BRANCH_IMPORT_V2`;
3. espelha PR em `products.estoque_quantidade`;
4. nunca espelha SP no estoque legado.

## RPCs V2

- `create_product_import_batch(jsonb)`;
- `stage_product_import_rows(uuid, jsonb)`;
- `reset_product_import_batch_to_draft(uuid)`;
- `preview_product_import_batch(uuid)`;
- `approve_product_import_batch(uuid)`;
- `commit_product_import_batch(uuid)`;
- `get_allowed_import_branches()`.

As RPCs validam usuario ativo, permissao, filial ativa e acesso. Funcoes de
hash e mascara nao possuem grant para `authenticated`.

O reset aceita exclusivamente `PREVIEWED` ou `REVALIDATION_REQUIRED`, limpa
snapshots, versoes, acoes, erros e avisos, incrementa `staging_revision` e
retorna o lote a `DRAFT`. Staging novo so e aceito em `DRAFT`.

## Concorrencia

O commit bloqueia:

1. lote;
2. advisory lock transacional da chave canonica no namespace
   `BRANCH_IMPORT_V2:IDEMPOTENCY:<idempotency_key>`;
3. advisory locks transacionais no namespace
   `BRANCH_IMPORT_V2:PRODUCT:<normalized_code>`, em ordem de codigo;
4. produtos ordenados por codigo;
5. precos ordenados por codigo;
6. saldos ordenados por codigo.

Versoes capturadas no preview sao comparadas antes da escrita. Divergencia
retorna `REVALIDATION_REQUIRED` sem alteracao comercial.

Depois de todos os locks, o backend recalcula hash e chave canonica e procura
novamente outro lote `COMMITTED` com a mesma chave. O vencedor e devolvido
somente quando o chamador tambem possui acesso a filial. O lote perdedor fica
`REVALIDATION_REQUIRED`, com retorno `idempotent = true`, sem escrita
comercial. O indice parcial unico permanece como ultima defesa; uma
`unique_violation` desse indice recebe o mesmo tratamento controlado e nao e
convertida em `P2899`.

O advisory lock cobre inclusive produto ainda inexistente. Depois de obtido, a
existencia e verificada novamente; criacao concorrente retorna
`PRODUTO_CRIADO_CONCORRENTEMENTE`. `hashtextextended` pode, em teoria, mapear
codigos diferentes para o mesmo inteiro de 64 bits. Uma colisao apenas
serializa lotes independentes e nao compromete dados, porque as validacoes
continuam usando o codigo completo.

Falhas sao classificadas assim:

- preview ou versao desatualizada e produto criado concorrentemente:
  `REVALIDATION_REQUIRED`;
- `lock_not_available`, `serialization_failure` e `deadlock_detected`:
  permanece `APPROVED`, com falha sanitizada e repetivel;
- regra de negocio irrecuperavel: `FAILED`;
- erro SQL inesperado: a chamada falha com `P2899 / IMPORTACAO_FALHOU` e toda
  alteracao da chamada e revertida.

O envelope publico nao inclui `SQLERRM`, nomes de tabela, constraints ou
detalhes internos. A autorizacao e validada antes do retorno idempotente de
lote `COMMITTED`, usando a mesma resposta generica para lote ausente ou
inacessivel.

## Compatibilidade e isolamento do fluxo legado

A migration captura `pg_get_functiondef`, owner, ACL, configuracao e MD5 das
seis funcoes legadas antes de substitui-las:

- `create_products_import_batch(jsonb)`;
- `preview_products_import_batch(uuid)`;
- `approve_products_import_batch(uuid)`;
- `commit_products_import_batch(uuid)`;
- `get_products_import_batches_report(jsonb)`;
- `get_products_import_batch_details(uuid, integer, integer)`.

As implementacoes originais sao preservadas em funcoes internas sem grant para
`public`, `anon` ou `authenticated`. Os wrappers publicos mantem assinatura,
retorno, owner, grants, `SECURITY DEFINER` e `search_path` do objeto original.
Preview, aprovacao e commit recusam lote V2 com
`P2812 / IMPORTACAO_NAO_DISPONIVEL_NESTE_FLUXO`, antes de ler estado, filial,
resumo ou staging.

`rollback_products_import_batch(uuid)` foi revisada e nao e substituida: a
definicao legada sempre encerra com
`ROLLBACK_IMPORTACAO_NAO_HABILITADO`, sem consultar lote, staging ou auditoria.
`create_products_import_batch(jsonb)` permanece integralmente no contrato 0 e
nao aceita `batch_id`; seu wrapper executa a implementacao literal preservada
e conserva o mesmo envelope de retorno. Depois da criacao, preenche
`created_by_profile_id` e, para `region` PR/SP, `branch_id` somente quando a
filial e inequivoca e o perfil ativo tem acesso a ela. A versao V2 usa a RPC
singular separada.

Os relatorios continuam mostrando lotes V2 a ADMIN e a usuarios com permissao
de relatorio e vinculo ativo na filial. Lote inexistente e lote sem acesso
produzem o mesmo detalhe vazio. O filtro e executado dentro das funcoes
`SECURITY DEFINER`.

Lotes legados com `region` inequivocamente igual a `PR` ou `SP` recebem a
filial canonica correspondente. Quando o criador textual identifica exatamente
um perfil, `created_by_profile_id` tambem e preenchido. Para
`contract_version = 0` ainda sem filial, a excecao transitoria e fechada:
somente ADMIN ou o criador identificavel pode ler. Um usuario comum nunca
recebe acesso amplo apenas por possuir modulo comercial.

## Leitura por filial

A policy ampla de `product_branch_stock` herdada da 027 e substituida na 028.
ADMIN le todas as filiais. Usuario comum precisa de modulo comercial e de
vinculo ativo em `profile_branches`; usuario sem filial nao le saldo. A mesma
regra de filial protege `product_branch_prices` e as policies V2 de lote,
staging e auditoria. Funcoes internas `SECURITY DEFINER` conservam somente o
acesso necessario.

As tres tabelas legadas de importacao declaram grants de forma fechada:
`authenticated` recebe somente `SELECT`; `INSERT`, `UPDATE` e `DELETE` diretos
ficam revogados, assim como todo acesso de `anon` e `public`. O helper
`can_access_product_import_batch_row(...)` pode ser executado por
`authenticated` para permitir a avaliacao das policies, mas nao por `anon` ou
`public`; ele retorna apenas booleano e sempre combina perfil ativo, permissao
e acesso real a filial.

Antes de normalizar esses grants, a migration captura `relacl`, owner e o ACL
efetivo completo de `products_import_batches`, `products_import_stage` e
`products_import_audit`. O rollback remove os grants da 028 e reconstrui cada
privilegio original, incluindo grantee, grantor e grant option. A validacao
compara o conjunto retornado por `aclexplode` e, quando o `relacl` original era
explicito, exige tambem o mesmo hash da representacao bruta.

Quando `relacl` era `NULL`, o PostgreSQL representa os privilegios padrao por
`acldefault`. Depois de um ciclo de `REVOKE/GRANT`, DDL publico pode
materializar o mesmo ACL em vez de voltar ao marcador `NULL`. Nesse caso, a
garantia e igualdade integral do ACL efetivo e de `has_table_privilege`, com a
representacao bruta registrada separadamente; nenhum catalogo de sistema e
alterado diretamente.

Todas as RPCs V2 que recebem `batch_id` fazem a primeira selecao combinando
lote, contrato, perfil ativo, permissao, filial e, em staging/reset, criador.
Lote inexistente, outra filial, perfil inativo, permissao ausente, criador
incompativel e criador nulo retornam
`P2811 / IMPORTACAO_NAO_AUTORIZADA`. Comparacoes anulaveis usam
`IS DISTINCT FROM`.

## Rollback estrutural

O rollback aborta quando encontra lote V2 confirmado, movimento V2, auditoria
V2, rollback operacional, preco nao originado do backfill, versao superior a 1
ou divergencia com os precos legados. Antes do primeiro `DROP`, um preflight
em `pg_depend`, `pg_rewrite`, `pg_proc`, `pg_trigger`, `pg_policy` e
`pg_constraint` lista views, materialized views, funcoes, triggers, policies,
constraints e FKs externas. A revisao preventiva tambem pesquisa
`pg_proc.prosrc`, expressoes de policies, definicoes de views, triggers,
defaults e event triggers para referencias textuais que o `pg_depend` pode nao
registrar. Objetos pertencentes a propria 028 sao excluidos por OID obtido de
assinatura completa, nunca apenas por `proname`; uma overload externa homonima
continua sendo bloqueador. Dependencias nas tres tabelas legadas sao
classificadas por coluna (`refobjsubid`) quando o catalogo permite, reduzindo
falsos bloqueios para objetos que usam somente colunas anteriores a 028.
O fallback textual nao considera nomes genericos isolados, como
`contract_version` ou `staging_revision`: exige um objeto exclusivo da 028 ou
a combinacao entre uma tabela de importacao e uma coluna adicionada pela 028.
Funcoes e policies alheias que apenas reutilizem esses nomes nao bloqueiam.
Qualquer bloqueador aborta a transacao sem desmontagem parcial e nenhum
`CASCADE` e utilizado. O preflight e diagnostico preventivo, nao uma garantia
matematica absoluta; a transacao unica e o PostgreSQL continuam como defesa
final.

Quando seguro, remove somente os objetos da 028 e restaura literalmente a
funcao e a policy de estoque da 027. Antes de remover colunas, restaura as seis
funcoes legadas a partir dos snapshots capturados e exige igualdade do MD5,
owner, ACL e configuracao. Os grants originais das tres tabelas legadas tambem
sao reconstruidos e validados antes da remocao do snapshot. O resolvedor
canonico valida PR e SP no inicio e
armazena os IDs antes de qualquer preflight ou `DROP`. O trigger temporario de
precos e removido. Nao altera produtos, filiais, saldos, movimentos ou precos
legados.

## Reaplicacao

A migration foi validada para reaplicacao somente na janela pre-operacional,
antes da existencia de alteracoes de origem, versao ou uso comercial dos
objetos V2.

Depois do uso operacional, nao reaplicar, nao executar `migration repair` e
nao executar manualmente a 028. Qualquer evolucao deve usar uma nova migration
incremental.

## Validacao local

Validado em PostgreSQL 17 isolado, aplicando o historico local de `001_schema`
ate a 027 antes da 028. Como o container nao executa o servico Supabase
Storage, foram criados apenas stubs descartaveis de `storage.buckets` e
`storage.objects` para permitir a reproducao das migrations 004 e 015.

Cobertura da suite transacional atual:

- backfill PR/SP com preco nulo, zero e positivo;
- incremento unitario de versao em mudanca real;
- preservacao de versao e ausencia de auditoria em no-op;
- mascara valida e invalida;
- staging e commit repetidos;
- hash distinto para o mesmo conteudo em filiais diferentes;
- lote invalido terminal em `FAILED`;
- falha transitoria preservando `APPROVED` e sem `COMMITTING` persistido;
- conflito sequencial de preview enviado para `REVALIDATION_REQUIRED`;
- disputa idempotente sequencial de dois lotes no-op;
- RPCs legadas de preview, approve e commit contra UUID V2;
- relatorio e detalhe legados contra lote V2 de outra filial;
- respostas uniformes para UUID ausente, outra filial, perfil inativo,
  proprietario divergente e proprietario nulo;
- contrato JSON como numero inteiro, texto, texto com espacos, decimal e nulo;
- algoritmo com caixa divergente;
- lote legado com filial inferida e lote legado sem filial;
- vendedor criando lote V0 com preenchimento de filial/proprietario e
  supervisor da mesma filial aprovando;
- isolamento de estoque PR/SP e espelho legado somente para PR;
- exatamente um movimento por alteracao efetiva;
- cadastro de produto novo e auditoria `PRODUCT`;
- campo vazio sem sobrescrita e sem auditoria espuria;
- ADMIN, usuario com `alimentacao`, aprovador e usuario sem acesso a filial;
- RLS de lotes, staging e auditoria sob `SET ROLE authenticated`, grants
  fechados e tentativa real de escrita direta nas tres tabelas;
- captura do `relacl` anterior e materializacao do ACL fechado durante a 028.

Aplicacao, reaplicacao, concorrencia em duas sessoes, preflight e rollback
estrutural sao ensaios externos a suite. Devem ser registrados separadamente;
a lista acima nao os considera aprovados apenas porque seus comandos existem
nesta documentacao.

O script reproduzivel esta em
`supabase/tests/028_branch_imports_validation.sql`. As fixtures de backfill sao
criadas antes da 028 pelo roteiro abaixo; a suite cria novamente com
`ON CONFLICT DO NOTHING`, cria usuarios, perfis, permissoes, lotes legados e
V2 dentro da propria transacao e termina com `ROLLBACK`.

### Laboratorio PostgreSQL 17.6 do zero

Executar a partir da raiz deste worktree. O container nao publica portas e nao
possui conexao com Supabase:

```powershell
$container = "crm-branch-imports-028"

docker pull postgres:17.6
docker run `
  --name $container `
  -e POSTGRES_PASSWORD=postgres `
  -e POSTGRES_DB=crm028 `
  -d postgres:17.6

docker exec $container pg_isready -U postgres -d crm028

docker exec $container psql -U postgres -d crm028 -v ON_ERROR_STOP=1 -c @"
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create schema storage;
create schema extensions;
create table auth.users (
  id uuid primary key,
  aud text,
  role text,
  email text unique,
  encrypted_password text,
  confirmed_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create function auth.uid()
returns uuid
language sql
stable
as 'select nullif(current_setting(''request.jwt.claim.sub'', true), '''')::uuid';
create table storage.buckets (
  id text primary key,
  name text,
  public boolean,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text,
  name text
);
alter table storage.objects enable row level security;
"@

docker cp "supabase/migrations/." "${container}:/migrations"

docker exec $container sh -c @'
set -eu
psql -U postgres -d crm028 -v ON_ERROR_STOP=1 \
  -f /migrations/001_schema.sql
for file in /migrations/*.sql; do
  name=$(basename "$file")
  case "$name" in
    001_*|028_*) continue ;;
  esac
  psql -U postgres -d crm028 -v ON_ERROR_STOP=1 -f "$file"
done
'@
```

Criar as fixtures que precisam existir antes do backfill e capturar as seis
definicoes legadas:

```powershell
docker exec $container psql -U postgres -d crm028 -v ON_ERROR_STOP=1 -c @"
alter table public.products
  alter column preco_pr drop not null,
  alter column preco_sp drop not null;

insert into public.products (
  codigo, descricao, preco_pr, preco_sp, estoque_quantidade
)
values
  ('TEST-028-NULL', 'Fixture sem preco', null, null, 0),
  ('TEST-028-ZERO', 'Fixture preco zero', 0, 0, 0),
  ('TEST-028-POSITIVE', 'Fixture preco positivo', 10.25, 11.50, 3);

grant select, insert on public.products_import_batches to authenticated;
grant select on public.products_import_stage to anon;
grant select, update on public.products_import_audit
to service_role with grant option;

create table public.phase2_table_acls_before as
select
  c.oid::regclass::text as table_name,
  c.relacl as raw_acl_state,
  coalesce(c.relacl, acldefault('r', c.relowner)) as effective_acl_state,
  md5(coalesce(c.relacl::text, '<NULL>')) as raw_acl_md5
from pg_class c
where c.oid in (
  'public.products_import_batches'::regclass,
  'public.products_import_stage'::regclass,
  'public.products_import_audit'::regclass
);

create table public.phase2_table_privileges_before as
select
  role_name,
  table_name,
  has_table_privilege(role_name, table_name, 'SELECT') as can_select,
  has_table_privilege(role_name, table_name, 'INSERT') as can_insert,
  has_table_privilege(role_name, table_name, 'UPDATE') as can_update,
  has_table_privilege(role_name, table_name, 'DELETE') as can_delete
from unnest(array['anon', 'authenticated', 'service_role']) role_name
cross join unnest(array[
  'public.products_import_batches',
  'public.products_import_stage',
  'public.products_import_audit'
]) table_name;

create table public.phase2_legacy_hashes_before as
select
  p.oid::regprocedure::text as signature,
  md5(pg_get_functiondef(p.oid)) as definition_md5,
  pg_get_userbyid(p.proowner) as owner_name,
  coalesce(p.proacl::text, '<NULL>') as acl_state,
  coalesce(p.proconfig::text, '<NULL>') as config_state
from pg_proc p
where p.oid in (
  'public.create_products_import_batch(jsonb)'::regprocedure,
  'public.preview_products_import_batch(uuid)'::regprocedure,
  'public.approve_products_import_batch(uuid)'::regprocedure,
  'public.commit_products_import_batch(uuid)'::regprocedure,
  'public.get_products_import_batches_report(jsonb)'::regprocedure,
  'public.get_products_import_batch_details(uuid,integer,integer)'::regprocedure
);

create table public.phase2_stock_function_before as
select
  p.oid::regprocedure::text as signature,
  md5(pg_get_functiondef(p.oid)) as definition_md5,
  pg_get_userbyid(p.proowner) as owner_name,
  coalesce(p.proacl::text, '<NULL>') as acl_state,
  coalesce(p.proconfig::text, '<NULL>') as config_state
from pg_proc p
where p.oid = 'public.sync_legacy_product_stock_to_pr()'::regprocedure;
"@

docker exec $container psql -U postgres -d crm028 `
  -v ON_ERROR_STOP=1 `
  -f /migrations/028_branch_imports.sql

docker exec $container psql -U postgres -d crm028 -v ON_ERROR_STOP=1 -c @"
select
  snapshot.table_name,
  snapshot.raw_acl_md5 = before.raw_acl_md5 as snapshot_matches_before,
  c.relacl::text as relacl_during_028,
  has_table_privilege(
    'authenticated', snapshot.table_name, 'SELECT'
  ) as authenticated_can_select,
  not has_table_privilege(
    'authenticated', snapshot.table_name, 'INSERT'
  ) as authenticated_cannot_insert,
  not has_table_privilege(
    'anon', snapshot.table_name, 'SELECT'
  ) as anon_cannot_select
from public.branch_import_legacy_table_acl_snapshots snapshot
join public.phase2_table_acls_before before using (table_name)
join pg_class c on c.oid = snapshot.table_name::regclass
order by snapshot.table_name;

select
  before.definition_md5 <> md5(pg_get_functiondef(p.oid))
    as definition_changed_by_028,
  position(
    'current_setting(''app.stock_sync_source'', true)'
    in pg_get_functiondef(p.oid)
  ) > 0 as marker_present,
  before.owner_name = pg_get_userbyid(p.proowner) as owner_preserved,
  before.acl_state = coalesce(p.proacl::text, '<NULL>') as acl_preserved,
  before.config_state = coalesce(p.proconfig::text, '<NULL>') as config_preserved
from public.phase2_stock_function_before before
join pg_proc p on p.oid = to_regprocedure(before.signature);
"@

# Reaplicacao permitida apenas nesta janela pre-operacional.
docker exec $container psql -U postgres -d crm028 `
  -v ON_ERROR_STOP=1 `
  -f /migrations/028_branch_imports.sql

docker cp `
  "supabase/tests/028_branch_imports_validation.sql" `
  "${container}:/028_branch_imports_validation.sql"

docker exec $container psql -U postgres -d crm028 `
  -v ON_ERROR_STOP=1 `
  -f /028_branch_imports_validation.sql
```

A suite usa IDs deterministicos apenas dentro da propria transacao. Para os
ensaios externos, recriar o ADMIN do laboratorio depois que a suite executar
seu `ROLLBACK`:

```powershell
docker exec $container psql -U postgres -d crm028 -v ON_ERROR_STOP=1 -c @"
insert into auth.users (
  id, aud, role, email, encrypted_password, confirmed_at, created_at, updated_at
)
values (
  '02800000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'phase2-admin@example.invalid',
  '',
  now(),
  now(),
  now()
);

insert into public.profiles (
  id, usuario, nome, email, perfil, ativo
)
values (
  '02800000-0000-4000-8000-000000000001',
  'phase2-admin',
  'Phase 2 Admin',
  'phase2-admin@example.invalid',
  'ADMIN',
  true
);
"@
```

### Concorrencia em duas sessoes

O laboratorio prepara dois lotes `APPROVED` para o mesmo codigo inexistente,
`TEST-028-CONCURRENT`, e guarda os UUIDs em
`public.phase2_test_concurrency_batches`. O indice de idempotencia e unico
somente para `COMMITTED`, portanto previews concorrentes sao permitidos e a
unicidade final continua protegida. Em banco descartavel, preparar com:

```sql
create table public.phase2_test_concurrency_batches (
  slot text primary key,
  batch_id uuid not null
);

select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  false
);

do $$
declare
  v_pr uuid;
  v_batch uuid;
  v_result jsonb;
  v_slot text;
begin
  select id into v_pr from public.branches where code = 'PR';
  foreach v_slot in array array['A', 'B'] loop
    v_result := public.create_product_import_batch(jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'CREATE_PRODUCTS',
      'field_mask', jsonb_build_array(
        'product_code', 'description', 'physical_qty', 'sale_price'
      )
    ));
    v_batch := (v_result->>'batch_id')::uuid;
    perform public.stage_product_import_rows(v_batch, jsonb_build_array(
      jsonb_build_object(
        'row_number', 1,
        'product_code', 'TEST-028-CONCURRENT',
        'provided_fields', jsonb_build_array(
          'product_code', 'description', 'physical_qty', 'sale_price'
        ),
        'data', jsonb_build_object(
          'description', 'Produto concorrente',
          'physical_qty', 1,
          'sale_price', case when v_slot = 'A' then 10 else 11 end
        )
      )
    ));
    perform public.preview_product_import_batch(v_batch);
    perform public.approve_product_import_batch(v_batch);
    insert into public.phase2_test_concurrency_batches values (v_slot, v_batch);
  end loop;
end
$$;
```

A Sessao A executa:

```sql
begin;
select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  true
);
select pg_advisory_xact_lock(
  hashtextextended('BRANCH_IMPORT_V2:PRODUCT:TEST-028-CONCURRENT', 0)
);
select pg_sleep(3);
select public.commit_product_import_batch(
  (select batch_id from public.phase2_test_concurrency_batches where slot = 'A')
);
commit;
```

Durante o `pg_sleep`, a Sessao B executa com `\timing on`:

```sql
select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  false
);
select public.commit_product_import_batch(
  (select batch_id from public.phase2_test_concurrency_batches where slot = 'B')
);
```

O tempo da Sessao B deve provar espera real. A deve terminar `COMMITTED`; B
deve terminar `REVALIDATION_REQUIRED` com
`PRODUTO_CRIADO_CONCORRENTEMENTE`. A conferencia final exige um produto, zero
erro de chave unica, zero auditoria ou movimento do lote B e nenhum dado
parcial. Um segundo ensaio mantem o advisory lock em A e usa
`lock_timeout = '200ms'` em B; B deve permanecer `APPROVED` com
`TRANSIENT_FAILURE`.

### Concorrencia da chave idempotente sem alteracao efetiva

Preparar dois lotes iguais para o preco que ja esta persistido:

```sql
create table public.phase2_test_idempotency_batches (
  slot text primary key,
  batch_id uuid not null
);

select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  false
);

do $$
declare
  v_pr uuid;
  v_price numeric;
  v_batch uuid;
  v_result jsonb;
  v_slot text;
  v_rows jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';
  select sale_price into v_price
  from public.product_branch_prices
  where product_code = 'TEST-028-ZERO' and branch_id = v_pr;

  v_rows := jsonb_build_array(jsonb_build_object(
    'row_number', 1,
    'product_code', 'TEST-028-ZERO',
    'provided_fields', jsonb_build_array('product_code', 'sale_price'),
    'data', jsonb_build_object('sale_price', v_price)
  ));

  foreach v_slot in array array['NOOP_A', 'NOOP_B'] loop
    v_result := public.create_product_import_batch(jsonb_build_object(
      'branch_id', v_pr,
      'mode', 'UPDATE_PRICES',
      'field_mask', jsonb_build_array('product_code', 'sale_price')
    ));
    v_batch := (v_result->>'batch_id')::uuid;
    perform public.stage_product_import_rows(v_batch, v_rows);
    perform public.preview_product_import_batch(v_batch);
    perform public.approve_product_import_batch(v_batch);
    insert into public.phase2_test_idempotency_batches values (v_slot, v_batch);
  end loop;
end
$$;
```

A Sessao A mantem o advisory lock da chave por tres segundos e confirma:

```sql
\timing on
begin;
select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  true
);
select pg_advisory_xact_lock(hashtextextended(
  'BRANCH_IMPORT_V2:IDEMPOTENCY:' || (
    select b.idempotency_key
    from public.products_import_batches b
    join public.phase2_test_idempotency_batches t on t.batch_id = b.id
    where t.slot = 'NOOP_A'
  ),
  0
));
select pg_sleep(3);
select public.commit_product_import_batch(
  (select batch_id
   from public.phase2_test_idempotency_batches
   where slot = 'NOOP_A')
);
commit;
```

Durante o `pg_sleep`, a Sessao B executa:

```sql
\timing on
select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  false
);
select public.commit_product_import_batch(
  (select batch_id
   from public.phase2_test_idempotency_batches
   where slot = 'NOOP_B')
);
```

Resultado obrigatorio: A `COMMITTED`; B
`REVALIDATION_REQUIRED / CONTEUDO_JA_CONFIRMADO`, `idempotent = true`,
`committed_batch_id` apontando para A, espera proxima de tres segundos, um
unico lote `COMMITTED`, nenhum `P2899`, nenhum movimento duplicado e nenhuma
auditoria comercial do lote B.

### Injecao controlada da ultima defesa de unicidade

O fluxo normal e serializado pelo advisory lock e nao deve atingir a
constraint. Para provar o handler de `unique_violation`, somente no banco
descartavel, instalar um trigger de pausa no staging, iniciar o commit de um
lote `APPROVED` e, durante a pausa, inserir por uma segunda sessao um vencedor
`COMMITTED` com a mesma chave sem respeitar o advisory lock:

```sql
select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  false
);

do $$
declare
  v_pr uuid;
  v_price numeric;
  v_batch uuid;
  v_result jsonb;
begin
  select id into v_pr from public.branches where code = 'PR';
  select sale_price into v_price
  from public.product_branch_prices
  where product_code = 'TEST-028-POSITIVE' and branch_id = v_pr;

  v_result := public.create_product_import_batch(jsonb_build_object(
    'branch_id', v_pr,
    'mode', 'UPDATE_PRICES',
    'field_mask', jsonb_build_array('product_code', 'sale_price')
  ));
  v_batch := (v_result->>'batch_id')::uuid;
  perform public.stage_product_import_rows(v_batch, jsonb_build_array(
    jsonb_build_object(
      'row_number', 1,
      'product_code', 'TEST-028-POSITIVE',
      'provided_fields', jsonb_build_array('product_code', 'sale_price'),
      'data', jsonb_build_object('sale_price', v_price)
    )
  ));
  perform public.preview_product_import_batch(v_batch);
  perform public.approve_product_import_batch(v_batch);
  insert into public.phase2_test_idempotency_batches values ('FAULT', v_batch);
end
$$;

create or replace function public.phase2_test_pause_before_stage_imported()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'imported' and old.status is distinct from new.status then
    perform pg_sleep(5);
  end if;
  return new;
end
$$;

create trigger phase2_test_pause_before_stage_imported
before update on public.products_import_stage
for each row execute function public.phase2_test_pause_before_stage_imported();
```

A Sessao A executa:

```sql
select set_config(
  'request.jwt.claim.sub',
  '02800000-0000-4000-8000-000000000001',
  false
);
select public.commit_product_import_batch(
  (select batch_id
   from public.phase2_test_idempotency_batches
   where slot = 'FAULT')
);
```

Durante a pausa de cinco segundos, a Sessao B insere:

```sql
insert into public.products_import_batches (
  created_by,
  import_type,
  region,
  source_name,
  status,
  summary,
  branch_id,
  mode,
  contract_version,
  field_mask,
  normalized_file_hash,
  normalization_algorithm,
  hash_algorithm,
  idempotency_key,
  state,
  created_by_profile_id,
  committed_by_profile_id,
  committed_at,
  imported_at
)
select
  created_by,
  import_type,
  region,
  'fault-injected-winner',
  'imported',
  '{}'::jsonb,
  branch_id,
  mode,
  contract_version,
  field_mask,
  normalized_file_hash,
  normalization_algorithm,
  hash_algorithm,
  idempotency_key,
  'COMMITTED',
  created_by_profile_id,
  '02800000-0000-4000-8000-000000000001',
  now(),
  now()
from public.products_import_batches
where id = (
  select batch_id
  from public.phase2_test_idempotency_batches
  where slot = 'FAULT'
);
```

A deve retornar o vencedor de modo idempotente, sem `P2899` e sem expor o nome
da constraint. Remover os objetos de injecao ao final:

```sql
drop trigger phase2_test_pause_before_stage_imported
on public.products_import_stage;
drop function public.phase2_test_pause_before_stage_imported();
```

### Ordem reproduzivel

1. Criar PostgreSQL 17 descartavel.
2. Aplicar migrations 001 a 027.
3. Remover `NOT NULL` apenas no laboratorio para `preco_pr` e `preco_sp`.
4. Inserir `TEST-028-NULL`, `TEST-028-ZERO` e `TEST-028-POSITIVE`.
5. Capturar definicao, owner, ACL e configuracao das seis funcoes legadas e
   da funcao de estoque da 027.
6. Aplicar a 028 e reaplica-la antes de qualquer uso operacional.
7. Executar `028_branch_imports_validation.sql`.
8. Recriar o ADMIN descartavel depois do `ROLLBACK` da suite.
9. Executar concorrencia de produto novo, timeout e idempotencia no-op.
10. Executar a injecao controlada da ultima defesa unica.
11. Em clone sem uso operacional, validar preflight textual, rollback e hashes.
12. Em clone com lote confirmado, exigir bloqueio do rollback e preservacao de
    todos os objetos.

Para provar a exclusao por OID e assinatura completa, criar uma overload
externa homonima. Criar tambem uma view que usa somente colunas legadas; essa
view nao deve ser falso positivo:

```sql
create function public.preview_products_import_batch(batch_id text)
returns bigint
language plpgsql
as $$
declare
  v_count bigint;
begin
  select count(*) into v_count from public.product_branch_prices;
  return v_count;
end
$$;

create view public.phase2_legacy_batch_columns as
select id, status, source_name
from public.products_import_batches;

create function public.phase2_unrelated_generic_terms()
returns bigint
language plpgsql
as $$
declare
  contract_version integer := 7;
  staging_revision bigint := 11;
begin
  return contract_version + staging_revision;
end
$$;

create table public.phase2_unrelated_policy_target (
  id bigint primary key,
  contract_version integer not null,
  staging_revision bigint not null
);

alter table public.phase2_unrelated_policy_target enable row level security;

create policy phase2_unrelated_generic_policy
on public.phase2_unrelated_policy_target
for select
using (contract_version >= 0 and staging_revision >= 0);
```

O rollback deve falhar com
`P2830 / ROLLBACK_028_DEPENDENCIAS_EXTERNAS`, listar
`function body public.preview_products_import_batch(batch_id text)`, nao listar
`view public.phase2_legacy_batch_columns`,
`function public.phase2_unrelated_generic_terms()` ou
`policy phase2_unrelated_generic_policy`, e preservar tabela, RPCs e colunas.
Depois:

```sql
drop function public.preview_products_import_batch(text);
```

A view, a funcao e a policy de controle negativo devem permanecer durante o
rollback permitido e podem ser removidas depois da prova.

Executar o rollback permitido e comparar as seis funcoes e a funcao de estoque:

```powershell
docker cp `
  "supabase/rollback/028_branch_imports_rollback.sql" `
  "${container}:/028_branch_imports_rollback.sql"

docker exec $container psql -U postgres -d crm028 `
  -v ON_ERROR_STOP=1 `
  -f /028_branch_imports_rollback.sql

docker exec $container psql -U postgres -d crm028 -v ON_ERROR_STOP=1 -c @"
select
  before.signature,
  before.definition_md5 as before_md5,
  md5(pg_get_functiondef(to_regprocedure(before.signature))) as after_md5,
  before.owner_name = pg_get_userbyid(p.proowner) as owner_equal,
  before.acl_state = coalesce(p.proacl::text, '<NULL>') as acl_equal,
  before.config_state = coalesce(p.proconfig::text, '<NULL>') as config_equal
from public.phase2_legacy_hashes_before before
join pg_proc p on p.oid = to_regprocedure(before.signature)
order by before.signature;

select
  before.signature,
  before.definition_md5 =
    md5(pg_get_functiondef(to_regprocedure(before.signature)))
    as definition_restored,
  before.owner_name = pg_get_userbyid(p.proowner) as owner_restored,
  before.acl_state = coalesce(p.proacl::text, '<NULL>') as acl_restored,
  before.config_state = coalesce(p.proconfig::text, '<NULL>')
    as config_restored
from public.phase2_stock_function_before before
join pg_proc p on p.oid = to_regprocedure(before.signature);

select
  before.table_name,
  before.raw_acl_state::text as relacl_before,
  c.relacl::text as relacl_after,
  before.raw_acl_state is not distinct from c.relacl
    as raw_relacl_equal,
  not exists (
    (
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode(before.effective_acl_state)
      except
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode(coalesce(c.relacl, acldefault('r', c.relowner)))
    )
    union all
    (
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode(coalesce(c.relacl, acldefault('r', c.relowner)))
      except
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode(before.effective_acl_state)
    )
  ) as effective_acl_equal
from public.phase2_table_acls_before before
join pg_class c on c.oid = before.table_name::regclass
order by before.table_name;

select
  before.*,
  before.can_select = has_table_privilege(
    before.role_name, before.table_name, 'SELECT'
  )
  and before.can_insert = has_table_privilege(
    before.role_name, before.table_name, 'INSERT'
  )
  and before.can_update = has_table_privilege(
    before.role_name, before.table_name, 'UPDATE'
  )
  and before.can_delete = has_table_privilege(
    before.role_name, before.table_name, 'DELETE'
  ) as privileges_equal
from public.phase2_table_privileges_before before
order by before.table_name, before.role_name;
"@

docker exec $container psql -U postgres -d crm028 -v ON_ERROR_STOP=1 -c `
  "drop view public.phase2_legacy_batch_columns;
   drop function public.phase2_unrelated_generic_terms();
   drop table public.phase2_unrelated_policy_target"

docker rm -f $container
```

### Resultado da implementacao atual

- PostgreSQL `17.6`, historico 001 a 027, aplicacao da revisao atual da 028 e
  reaplicacao na janela pre-operacional: aprovados;
- suite `028_branch_imports_validation.sql`: aprovada integralmente e revertida
  ao final, incluindo RLS real sob `SET ROLE authenticated` e contrato V0;
- bypass das tres RPCs operacionais legadas por UUID V2: bloqueado;
- leitura cruzada em relatorio e detalhe: bloqueada;
- autorizacao uniforme de `stage`, `reset`, `preview`, `approve` e `commit`:
  aprovada na suite;
- disputa idempotente no-op sequencial: um `COMMITTED`, um retorno idempotente,
  sem `P2899`;
- preflight: overload externa homonima bloqueada pela assinatura completa e
  view dependente apenas de colunas legadas preservada;
- rollback permitido: aprovado, incluindo restauracao literal das seis funcoes
  legadas e da funcao de estoque da 027, com definicao, owner, ACL e
  configuracao iguais;
- concorrencia real em duas conexoes: produto novo e idempotencia no-op
  aprovados, com espera observada de `3890 ms` e `3889 ms`, respectivamente;
- ultima defesa de `unique_violation`: retorno idempotente controlado, sem
  `P2899` ou escrita comercial parcial;
- rollback com lote confirmado: bloqueado, preservando os objetos da 028;
- preflight textual: dependencia PL/pgSQL real detectada e controles negativos
  preservados sem falso positivo.

## Aplicacao

Esta migration nao esta autorizada para aplicacao remota. Antes de qualquer
`db push` sera necessario novo backup, dry-run controlado e autorizacao
separada.
