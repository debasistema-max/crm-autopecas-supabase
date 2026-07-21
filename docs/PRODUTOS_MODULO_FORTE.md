# Produtos - Fase 2A

## Objetivo

Fortalecer o modulo Produtos como principal ferramenta comercial de consulta, sem alterar regras de negocio, sem alterar Importacao SAP, sem iniciar reorganizacao arquitetural e sem aplicar alteracoes no banco nesta etapa.

## Escopo implementado

- Pesquisa rapida com debounce e paginacao incremental.
- Busca por codigo, descricao, marca, aplicacao, grupo, linha/categoria, montadora, OEM, similares, detalhes e ano.
- Filtros por marca, grupo, linha/categoria, montadora, disponibilidade, imagem, OEM e favoritos.
- Cards com codigo, descricao, marca, montadora, aplicacao, OEM, similares, disponibilidade visual, estoque atual e preco por UF selecionada.
- Painel de detalhe com apenas campos reais do schema `products`.
- Fotos via `products.url_imagem`, com fallback neutro quando ausente ou quando a imagem falha.
- Favoritos por usuario.
- Produtos recentemente consultados por usuario.
- Produtos mais vendidos como complemento restrito por perfil.
- Historico real de precos e estoque a partir de `products_import_audit`.
- Layout responsivo para desktop e celular, incluindo largura 390x844.

## Banco preparado

A migration `supabase/migrations/024_products_experience.sql` prepara:

- `public.product_favorites`
- `public.product_recent_views`
- `public.record_product_recent_view(product_code, max_items)`
- `public.get_product_price_history(product_code, limit_count)`
- `public.get_product_stock_history(product_code, limit_count)`
- `public.get_top_selling_products(limit_count)`

Tambem cria indices auxiliares em campos ja existentes de `products`:

- `categoria`
- `grupo`
- `montadora`
- `oem`
- `similar`
- `aplicacao`
- `url_imagem` preenchida

## RLS e permissoes

`product_favorites`:

- SELECT somente do proprio `auth.uid()`.
- INSERT somente do proprio `auth.uid()`.
- DELETE somente do proprio `auth.uid()`.
- Sem UPDATE concedido.
- ADMIN nao recebe leitura automatica dos favoritos de outros usuarios.

`product_recent_views`:

- SELECT, INSERT, UPDATE e DELETE somente do proprio `auth.uid()`.
- O RPC `record_product_recent_view` valida usuario ativo e acesso a `produtos`, `novo_pedido` ou `nova_cotacao`.
- O RPC limita a lista recente por usuario, mantendo no maximo 30 itens por padrao.

`get_top_selling_products`:

- Retorna ranking agregado apenas para perfis `ADMIN` e `SUPERVISOR`.
- Para `VENDEDOR`, retorna lista vazia.
- Esta decisao evita expor ranking global a vendedor sem uma regra confiavel de time/carteira.

Todas as funcoes usam `security definer` somente onde necessario e definem `search_path = public`. Grants para `anon` e `public` foram revogados; `authenticated` recebe apenas os grants necessarios.

## Compatibilidade e fallback

O frontend permanece preparado para funcionar de forma controlada caso os objetos complementares da migration 024 ainda nao estejam disponiveis em outro ambiente:

- A busca principal usa `products` e continua operacional.
- Favoritos e recentes usam fallback local por usuario no navegador quando as tabelas/RPCs ainda nao existem.
- Historicos e ranking retornam vazio quando as RPCs ainda nao existem.
- Erros de recurso ausente sao tratados de forma controlada, sem repeticao em loop.

## Limitacoes atuais

- Nao ha multiempresa.
- Nao foi alterada Importacao SAP.
- Nao foi criado novo modelo de Produtos.
- O schema atual possui preco por UF (`preco_sp`, `preco_pr`), mas nao possui estoque separado por filial. Por isso a UI exibe estoque real atual do produto e precos SP/PR, sem inventar estoque SP/PR.
- Historicos dependem de dados reais em `products_import_audit`.
- Mais vendidos depende de `order_items` e fica restrito a ADMIN/SUPERVISOR ate existir regra segura para escopo comercial de vendedor.

## Rollback

Rollback preparado em:

`supabase/rollback/024_products_experience_rollback.sql`

O rollback remove apenas objetos da Fase 2A:

- tabelas `product_favorites` e `product_recent_views`;
- policies dessas tabelas;
- RPCs da experiencia de Produtos;
- indices auxiliares criados pela 024.

Nao remove produtos, pedidos, cotacoes, importacao, objetos da Fase 1 ou extensoes compartilhadas.

## Aplicacao e validacao

Em 21/07/2026, a migration 024 foi aplicada de forma controlada no banco remoto depois de backup completo com PostgreSQL Client 17.6. A aplicacao usou transacao e `ON_ERROR_STOP`. Em seguida foram validados:

- estrutura, indices, constraints, RLS, policies e grants;
- funcoes `security definer` com `search_path` seguro;
- busca e filtros com produtos temporarios importados pelo fluxo oficial;
- favoritos e recentes com usuarios reais ADMIN e VENDEDOR;
- isolamento entre usuarios;
- historicos reais de preco e estoque;
- ranking permitido para ADMIN e SUPERVISOR e vazio seguro para VENDEDOR;
- layouts desktop e 390x844;
- limpeza integral dos produtos, lote e usuarios temporarios.

O historico remoto foi reparado pelo comando oficial `supabase migration repair 024 --status applied`, sem reaplicar o SQL da migration.

## Estado desta etapa

- Implementacao local preparada na worktree isolada da Fase 2A.
- Migration 024 aplicada, validada e registrada no historico remoto.
- Deploy nao executado.
- Commit nao criado.
- Push nao executado.
