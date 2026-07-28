# Estoque por filial - Fase 1: Fundacao

## Escopo

Esta fase cria somente a base relacional para estoque por filial. Ela nao altera
Importacao SAP, pedidos, cotacoes, telas operacionais, Dashboard ou regras
comerciais.

A referencia inicial e o commit `f476f87133cdfea57cee369b36bfee3b270b330e`.

## Filiais

`branches` representa qualquer unidade de origem ou destino. Nao existe regra
estrutural limitada a PR e SP. A migration cria inicialmente:

- `PR`: Matriz PR, Curitiba/PR;
- `SP`: Filial SP, Sao Paulo/SP.

Transferencias futuras terao `origin_branch_id` e `destination_branch_id` e
validarao apenas que as filiais sejam distintas e ativas.

## Usuarios e filiais

`profile_branches` permite que um usuario tenha acesso a varias filiais e no
maximo uma filial padrao ativa. A migration nao presume a filial dos usuarios
existentes. Esse mapeamento devera ser feito e validado antes de ativar pedidos
ou transferencias por filial.

Os helpers `can_access_branch(uuid)` e `get_default_branch_id()` usam
`auth.uid()` e ficam disponiveis somente para `authenticated`.

## Saldo por produto e filial

`product_branch_stock` mantem:

- saldo fisico disponivel para operacao;
- reserva de pedidos;
- reserva de transferencias;
- quantidade em transito para a filial;
- quantidade em quarentena;
- estoque minimo, ponto de reposicao e estoque alvo;
- origem preferencial e ativacao futura de reposicao automatica.

`available_qty` e gerado pelo banco:

`physical_qty - reserved_order_qty - reserved_transfer_qty`

Constraints impedem saldos negativos, reservas superiores ao fisico, origem
de reposicao igual ao destino e reposicao automatica sem origem.

Quarentena nao faz parte do saldo fisico disponivel. Recebimentos divergentes,
avariados ou excedentes deverao entrar em `quarantined_qty` ate uma liberacao
auditada em fase posterior.

## Estoque legado

Por decisao aprovada, todo `products.estoque_quantidade` existente e atribuido
inicialmente a Matriz PR. A Filial SP inicia com zero.

A migration falha se encontrar estoque legado negativo. Ela nao corrige nem
silencia esse dado.

Enquanto a importacao por filial ainda nao existe, os triggers temporarios
`products_insert_sync_legacy_stock_to_pr` e
`products_update_sync_legacy_stock_to_pr` espelham insercoes e alteracoes da
coluna legada para o saldo da Matriz PR e registram a mudanca no ledger. Assim,
aplicar apenas a fundacao nao deixa o novo saldo desatualizado.

Esse trigger devera ser removido na Fase 2 antes de ativar importacao por filial.
`products.estoque_quantidade` continuara sendo a fonte consumida pelas telas
atuais ate a migracao controlada desses leitores.

## Movimentacoes

`stock_movements` e um ledger imutavel. Cada linha registra deltas, saldo
anterior, saldo novo, origem, referencia, usuario, data e chave de idempotencia.
UPDATE e DELETE sao bloqueados por trigger. Correcoes futuras usarao movimento
`ESTORNO` vinculado ao movimento original.

Nesta fase somente dois fluxos gravam movimentos:

- migracao inicial do estoque legado para PR;
- sincronizacao temporaria da coluna legada.

Nenhum usuario recebe escrita direta em `product_branch_stock` ou
`stock_movements`.

## RLS e grants

- `branches`: leitura autenticada; escrita somente ADMIN.
- `profile_branches`: usuario le os proprios vinculos; ADMIN le e administra.
- `product_branch_stock`: leitura conforme modulos comerciais atuais.
- `stock_movements`: leitura somente ADMIN ou permissao `logs`.
- `anon` e `PUBLIC` nao recebem acesso.
- Funcoes criticas futuras deverao manter `SECURITY DEFINER`,
  `search_path = public`, grants minimos, locks e idempotencia.

## Arquitetura aprovada para fases futuras

### Transferencias genericas

O cabecalho futuro nao tera PR/SP fixos. Toda transferencia usara origem e
destino relacionais. A geracao PR para SP sera apenas o primeiro caso de uso.

### Modulo Transferencias

Uma fase posterior criara listagem, detalhe, dados fiscais e de transporte,
itens consolidados, pedidos vinculados, recebimentos, divergencias e historico
em linha do tempo.

### Dashboard logistico

Sera criado depois que existirem movimentos e transferencias reais. Indicadores
previstos: saldo por filial, reservas, transito, quarentena, rupturas, pedidos
aguardando, transferencias por status, prazo medio e divergencias.

### Reposicao automatica

Os parametros ja existem na fundacao, mas nenhum pedido de reposicao e gerado
automaticamente nesta fase. A automacao futura devera respeitar compromissos
ativos, capacidade da origem, lote minimo, idempotencia e aprovacao.

### Prioridade de pedidos

Pedidos receberao prioridade e data de promessa somente na fase de reservas.
A distribuicao futura respeitara vinculo explicito, prioridade, promessa e
antiguidade, nessa ordem.

## Fases seguintes

1. Importacao de estoque por filial e retirada do espelho legado.
2. Filial do pedido, prioridade, reservas e necessidades pendentes.
3. Transferencias genericas, consolidacao, aprovacao e expedicao.
4. Recebimento parcial, quarentena, divergencias e estornos.
5. Modulo Transferencias e linha do tempo.
6. Dashboard logistico e reposicao automatica.
7. Atualizacao final de Produtos, Dashboard e desativacao do saldo legado.

## Rollback

O rollback e protegido e aborta se detectar:

- usuarios vinculados a filiais;
- filiais adicionais;
- reservas, transito, quarentena ou parametros de reposicao;
- movimentos fora da migracao e do espelho legado.

Quando permitido, ele remove o trigger de compatibilidade, helpers, policies,
tabelas e indices da fundacao. `products.estoque_quantidade`, pedidos,
importacao, usuarios e demais dados atuais permanecem intactos.

## Estado atual em producao

A migration foi aplicada e validada em producao em 28/07/2026.

- inicio: `15:00:20.407 -03:00`;
- fim: `15:00:50.204 -03:00`;
- projeto: `doenvnjzrecrtvwooaai`;
- ambiente: `main / Production`;
- versao: `027`;
- nome: `branch_stock_foundation`;
- commit: `a868c939335cd50d08ffa67c2a29b804b66912f1`;
- SHA-256 da migration:
  `121F22532B9971F9AD831CD03A3AF50D29113719C66FDD7FB732CCC5738ABB2B`;
- SHA-256 do rollback:
  `E305E9906828793DB7CC78B3F77B936A650DA234A2F6A438938B54E65BA917FF`.

### Resultados validados

- filiais: `2`;
- matrizes: `1`;
- produtos por filial: `4.035`;
- total de linhas de saldo: `8.070`;
- estoque legado: `104.587`;
- estoque fisico PR: `104.587`;
- estoque fisico SP: `0`;
- movimentos iniciais: `2.922`;
- soma dos deltas: `104.587`;
- inconsistencias: `0`;
- reservas: `0`;
- tabelas com RLS: `4`;
- policies: `9`;
- teste transacional executado e revertido com sucesso.

### Aviso da Supabase CLI

Apos a aplicacao, a CLI apresentou o aviso:

```text
Warning: failed to cache migrations catalog:
Failed to read certificate file
'/workspace/supabase/.temp/pgdelta/pgdelta-target-ca.crt'
```

O aviso afetou somente o cache local do catalogo. O comando terminou com exit
code `0`, e o banco confirmou a migration e todos os objetos esperados. O
comando nao foi repetido.

### Alerta operacional

> A migration 027 ja esta aplicada em producao.
>
> Nao executar novamente.
> Nao usar `migration repair`.
> Nao usar `--include-all`.
> Nao reaplicar manualmente pelo Dashboard.
> Nao repetir `db push` para tentar eliminar o aviso de cache.
