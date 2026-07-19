# Dashboard Comercial V2.1

## Escopo

Primeira versao tecnica do Dashboard Comercial, mantendo o frontend estatico e o Supabase como backend. O objetivo e retornar indicadores agregados por RPC, sem carregar tabelas inteiras no navegador.

Incluido nesta etapa:

- total de pedidos no periodo;
- valor total de pedidos no periodo;
- pedidos por status;
- cotacoes pendentes;
- cotacoes por status;
- produtos com estoque zerado;
- ultima importacao SAP;
- lotes de importacao por status;
- ate 10 atividades recentes sem payloads sensiveis.

Fora do escopo:

- produtos mais vendidos;
- desempenho por vendedor;
- metas;
- clientes recentes;
- carteira de clientes;
- conversao de cotacao em pedido;
- produtos consultados;
- graficos complexos;
- estoque baixo configuravel;
- estrutura normalizada de filiais.

## RPC

Migration:

`supabase/migrations/022_dashboard_comercial_v21.sql`

Funcao:

`public.get_commercial_dashboard_summary(filters jsonb default '{}'::jsonb)`

A funcao usa `SECURITY DEFINER` porque precisa centralizar agregacoes comerciais e retornar dados ja filtrados sem expor consultas diretas no frontend. A RPC valida `auth.uid()`, consulta o perfil ativo, fixa `search_path = public`, qualifica tabelas com schema e limita explicitamente os campos retornados.

Filtros aceitos:

- `date_from`: data inicial, padrao primeiro dia do mes atual;
- `date_to`: data final, padrao data atual;
- `region`: `SP` ou `PR`;
- `seller_id`: UUID do vendedor, aceito somente para ADMIN ou perfil com permissao `dashboard_comercial`.

Limites e datas:

- periodo maximo de 370 dias;
- datas invalidas retornam `DATA_INVALIDA`;
- data final menor que data inicial retorna `PERIODO_INVALIDO`;
- a data final e inclusiva, usando `created_at >= date_from` e `created_at < date_to + 1 dia`;
- `seller_id` invalido retorna `VENDEDOR_INVALIDO`;
- filtro de vendedor enviado por usuario sem permissao e ignorado.

## Retorno

Estrutura principal:

```json
{
  "filters": {},
  "access": {},
  "orders": {},
  "quotations": {},
  "products": {},
  "imports": {},
  "recent_activities": []
}
```

`recent_activities` retorna somente:

- data/hora;
- usuario;
- acao;
- entidade;
- id da entidade.

Nao retorna `dados_anteriores`, `dados_novos`, e-mails, tokens ou payloads tecnicos.

Quando o usuario pode filtrar vendedor, a resposta inclui `sellers` com no maximo 200 perfis ativos, retornando somente:

- `id`;
- `nome`;
- `usuario`.

## Perfis Reais E Regras De Acesso

Perfis reais encontrados no enum `public.user_profile`:

- `ADMIN`;
- `SUPERVISOR`;
- `VENDEDOR`.

Nao existe perfil `REPRESENTANTE` no schema atual. Se a empresa passar a usar representante, o caminho seguro e criar o perfil de forma explicita em migration propria ou mapear esse usuario para `VENDEDOR` nesta fase.

ADMIN e usuarios com permissao `dashboard_comercial` recebem escopo `all`.

Usuarios autenticados sem `dashboard`, sem `dashboard_comercial` e sem ADMIN recebem `SEM_PERMISSAO`, mesmo chamando a RPC diretamente.

VENDEDOR/SUPERVISOR com permissao `dashboard`, mas sem permissao ampla, recebem escopo `own`, limitado a:

- `orders.user_id = auth.uid()`;
- `quotations.user_id = auth.uid()`;
- `logs.user_id = auth.uid()` quando nao possuem permissao de logs.

Importacoes SAP aparecem somente para:

- ADMIN;
- usuarios com `dashboard_comercial`;
- usuarios com `visualizar_lotes_importacao`;
- usuarios com `alimentacao`.

Produtos zerados aparecem somente para usuarios com acesso de produto/pedido/cotacao ou ADMIN.

A migration cria de forma controlada:

- `ADMIN/dashboard_comercial`, para visao ampla;
- `VENDEDOR/dashboard`, para permitir a visao propria do dashboard comercial.

## Regras Dos KPIs

Valor total dos pedidos:

- usa `orders.total`, coluna oficial ja gravada no pedido;
- nao recalcula por `order_items`;
- respeita o periodo filtrado por `orders.created_at`;
- inclui todos os status existentes no periodo, inclusive cancelados, porque nesta primeira versao o card representa movimento total gravado, nao faturamento liquido.

Cotacoes pendentes:

- usa `quotations.status in ('NOVA', 'ENVIADA')`;
- exclui `APROVADA`, `CANCELADA` e `CONVERTIDA`;
- `status` nao e nulo no schema.

Estoque zerado:

- usa `products.estoque_quantidade <= 0`;
- conta codigos de produtos;
- nao separa SP/PR nesta primeira versao porque o schema atual possui uma coluna numerica agregada `estoque_quantidade`;
- nao mistura com `status_cadastro`.

Ultima importacao SAP:

- usa `products_import_batches`;
- considera somente lotes com `status in ('imported', 'committed')` e `imported_at is not null`;
- escolhe o lote mais recente por `imported_at desc`;
- portanto mostra a ultima importacao SAP concluida com sucesso.

## Aplicacao Futura

Aplicar somente apos revisao:

```powershell
supabase db push
```

Ou executar a migration 022 pelo fluxo controlado ja usado no projeto.

## Rollback

Rollback manual:

`supabase/rollbacks/022_dashboard_comercial_v21_rollback.sql`

Remove apenas:

- RPC `public.get_commercial_dashboard_summary(jsonb)`;
- permissao `ADMIN/dashboard_comercial`;
- permissao `VENDEDOR/dashboard` criada pela migration 022.

## Teste Pos-Aplicacao

Checklist:

- login ADMIN;
- abrir Dashboard;
- alterar periodo;
- filtrar regiao;
- conferir pedidos por status;
- conferir cotacoes por status;
- conferir estoque zerado;
- conferir ultima importacao SAP;
- conferir atividades recentes;
- login VENDEDOR;
- confirmar escopo proprio;
- confirmar que filtro vendedor nao aparece;
- confirmar que Importacao SAP e Lotes continuam abrindo.

## Teste Local Sem RPC Remota

Para validar somente a renderizacao antes de aplicar a migration, abrir o app em ambiente local com:

`?mockDashboard=1`

O mock so e aceito quando o host for `localhost`, `127.0.0.1` ou protocolo `file:`. Em GitHub Pages/producao ele nao fica ativo.

## Proximos Indicadores

Proximas etapas sugeridas:

- produtos mais vendidos;
- desempenho por vendedor;
- metas comerciais;
- carteira de clientes;
- conversao cotacao para pedido;
- estoque baixo configuravel.
