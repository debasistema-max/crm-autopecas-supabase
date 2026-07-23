# Dashboard Comercial - Fase 2C

## Objetivo

A Fase 2C consolida os indicadores comerciais em uma RPC autenticada e em um Dashboard operacional. Ela preserva HTML, CSS e JavaScript puros, Supabase/PostgreSQL, RLS e GitHub Pages. Nao cria multiempresa, portal, backend adicional nem visao de equipe.

## Perfis e escopo

| Perfil | Escopo no banco | Recursos adicionais |
| --- | --- | --- |
| `ADMIN` | Todos os documentos ou um vendedor selecionado | Ranking de vendedores, estoque e importacao |
| `SUPERVISOR` | Somente documentos cujo `user_id = auth.uid()` | Sem equipe, ranking global, estoque ou importacao |
| `VENDEDOR` | Somente documentos cujo `user_id = auth.uid()` | Produtos e clientes derivados apenas dos proprios pedidos |

O frontend nao envia ownership. A RPC obtem o usuario por `auth.uid()` e so aceita `seller_id` quando o perfil efetivo e `ADMIN`. Menus nao sao usados como barreira de seguranca. Para perfis restritos, as chaves de estoque, importacao, lista de vendedores e ranking de vendedores nem sequer fazem parte do JSON.

A visao de equipe do `SUPERVISOR` foi postergada ate existir uma relacao supervisor-equipe persistida e auditavel.

## Periodos

O Dashboard oferece hoje, ultimos 7 dias, ultimos 30 dias, mes atual, mes anterior e periodo personalizado. A RPC:

- exige data inicial menor ou igual a data final;
- limita o intervalo a 370 dias;
- converte inicio e fim do dia usando `company_settings.timezone`;
- usa `America/Sao_Paulo` se o timezone configurado nao for valido;
- agrupa a serie por dia ate 31 dias, semana ate 180 dias e mes acima disso;
- usa parametros JSON tipados, sem SQL dinamico ou interpolacao.

## Regras dos KPIs

| KPI | Regra |
| --- | --- |
| Pedidos validos | Todos os pedidos do periodo, exceto `CANCELADO` |
| Valor realizado | Soma de pedidos `APROVADO` e `FATURADO` |
| Ticket medio | Valor realizado dividido pela quantidade de pedidos `APROVADO`/`FATURADO` |
| Cotacoes elegiveis | `ENVIADA`, `APROVADA` e `CONVERTIDA` |
| Valor em cotacoes | Soma das cotacoes elegiveis; nao e faturamento |
| Cotacoes pendentes | `NOVA` e `ENVIADA` |
| Cotacoes aprovadas | `APROVADA` e `CONVERTIDA` |
| Clientes movimentados | Clientes distintos dos pedidos nao cancelados no periodo, por codigo SAP, CNPJ ou nome normalizado |
| Produtos vendidos | Codigos distintos em pedidos `APROVADO`/`FATURADO` |

Pedidos `NOVO` e `EM_ANALISE` aparecem na distribuicao por status, mas nao entram no valor realizado. Pedidos cancelados nao entram em pedidos validos, vendas, ticket, rankings ou curva ABC. Cotacoes `NOVA` e `CANCELADA` nao entram em valor ou denominador de conversao.

Margem, lucro, custo, comissao, meta, rentabilidade, devolucao e faturamento fiscal nao sao exibidos porque o schema nao oferece fontes confiaveis para essas metricas.

## Conversao

O numerador conta cotacoes elegiveis que possuem registro em `quotation_order_conversions`. O denominador e a quantidade de cotacoes `ENVIADA`, `APROVADA` ou `CONVERTIDA` criadas no periodo e no escopo. Pedidos manuais nao entram no numerador. A serie temporal de conversoes usa `converted_at`, enquanto a taxa usa a coorte de cotacoes criadas no periodo.

## Rankings

- Vendedores: somente `ADMIN`, por valor realizado, limitado a 10. Usuarios inativos nao tem o nome exposto e aparecem como `Usuario inativo`.
- Produtos: por valor realizado e quantidade, limitado a 10 e sempre respeitando o escopo.
- Clientes: por valor realizado, limitado a 10 e sempre respeitando o escopo.
- Empates usam nome/codigo como ordenacao deterministica.

`SUPERVISOR` e `VENDEDOR` recebem apenas seus rankings de produtos e clientes. O payload de ranking de vendedores permanece vazio.

## Curva ABC

A curva usa itens de pedidos `APROVADO`/`FATURADO`, ordenados pelo valor total. A classificacao considera o percentual acumulado anterior ao item: A ate 80%, B ate 95% e C no restante. Isso garante que o produto de maior valor sempre inicie a classe A. O retorno e agregado por classe e respeita o mesmo escopo do usuario.

## Estoque e importacao

Somente `ADMIN` recebe:

- produtos cadastrados;
- produtos com estoque geral menor ou igual a zero;
- produtos sem preco em SP e PR;
- produtos sem imagem;
- ultimo lote de `products_import_batches`;
- quantidade de lotes com falha/erro no periodo.

Nao ha separacao de estoque SP/PR no cadastro de produtos. Estoque minimo foi postergado porque nao existe campo confiavel. O Dashboard nao modifica nem acopla o fluxo da Importacao SAP.

## RPC, grants e seguranca

`public.get_dashboard_summary(filters jsonb)` e `SECURITY DEFINER`, fixa `search_path = public`, valida perfil ativo e permissao de Dashboard e retorna somente agregados necessarios. Nao usa service role, SQL dinamico, parametro de ownership nem consulta por card.

Grants efetivos da Fase 2C:

```sql
revoke all on function public.get_dashboard_summary(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.get_dashboard_summary(jsonb) to authenticated;
```

`PUBLIC`, `anon` e `service_role` nao recebem `EXECUTE` explicito na RPC. O owner tecnico `postgres` conserva os privilegios inerentes de ownership. `authenticated` pode executar, mas o escopo e decidido internamente. As RLS existentes continuam protegendo consultas diretas; a RPC nao amplia grants de tabelas.

## Performance

A migration adiciona quatro indices: `status/created_at` e `user_id/status/created_at` para pedidos e cotacoes. Os indices existentes de `user_id/created_at`, status isolado e as chaves unicas dos itens foram preservados, sem criar equivalentes redundantes. O frontend realiza uma chamada de resumo. Rankings tem limite 10, vendedores para filtro tem limite 200 e a serie tem no maximo aproximadamente 32 pontos diarios, 27 semanais ou 13 mensais no intervalo permitido.

Nao foram criadas views ou materialized views. O payload contem agregados compactos, sem documentos completos e sem N+1.

## Frontend e mobile

O Dashboard inclui periodos predefinidos, datas personalizadas, filial, filtro de vendedor somente quando autorizado, KPIs, serie em CSS, status, rankings, curva ABC, blocos administrativos e atalhos. Todos os valores textuais vindos do banco passam por escape antes de entrar no HTML.

Em ate 680 px, filtros, KPIs, rankings, indicadores e atalhos usam uma coluna; botoes mantem altura minima de 44 px. O grafico usa colunas fluidas, sem biblioteca externa.

## Fallback antes da migration 026

O frontend tenta `get_dashboard_summary(filters jsonb)` uma unica vez por carregamento da aplicacao. Se o PostgREST informar que a assinatura nao existe, a tentativa e desativada em memoria e as atualizacoes seguintes usam `get_commercial_dashboard_summary(filters jsonb)` da V2.1. Uma mensagem identifica o resumo basico.

Erros de permissao, periodo ou rede nao acionam fallback. A antiga RPC nao e chamada em loop. Os indicadores avancados nao devem ser considerados validados no banco antes da aplicacao da 026.

## Aplicacao controlada

1. Criar e validar backup remoto.
2. Confirmar migrations 024 e 025 aplicadas e migration 027 ausente.
3. Revisar `026_dashboard_commercial.sql` e executar em transacao.
4. Confirmar assinatura, owner, `prosecdef`, `proconfig` e ACL da funcao.
5. Testar `ADMIN`, `SUPERVISOR` e `VENDEDOR` com dados sinteticos removiveis.
6. Validar isolamento por ownership, periodos, status, conversao e payload.
7. Remover dados e usuarios temporarios.

Esta rodada nao aplica a migration no banco remoto.

## Testes locais

- `node --check` nos JavaScripts alterados;
- `git diff --check`;
- revisao estatica da migration e rollback;
- fallback para a RPC V2.1 com resposta vazia;
- navegador em 1440x900 e 390x844;
- perfis `ADMIN`, `SUPERVISOR` e `VENDEDOR` simulados apenas no harness local;
- loading, vazio, erro, botoes, overflow, console e identidade `Nova Empresa`.

Os KPIs novos so poderao receber teste funcional real depois da aplicacao controlada da migration.

## Rollback

`supabase/rollback/026_dashboard_commercial_rollback.sql` remove somente a sobrecarga `get_dashboard_summary(jsonb)` e os quatro indices da Fase 2C. A RPC legada sem parametros, a RPC V2.1, as migrations 024/025 e todos os dados comerciais permanecem preservados. O rollback nunca e executado automaticamente.

## Limitacoes atuais

- sem visao de equipe para `SUPERVISOR`;
- sem meta x realizado;
- sem margem, lucro, custo, comissao ou faturamento fiscal;
- sem estoque minimo;
- clientes dos documentos sao correlacionados por codigo SAP, CNPJ ou nome, pois pedidos/cotacoes nao possuem `client_id`;
- o Dashboard permanece monoempresa;
- validacao remota da RPC depende de backup e autorizacao posterior.
