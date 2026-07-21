# Fase 2B - Fluxo Comercial

## Objetivo

Fortalecer Pedidos, Cotacoes e Parceiros sem mudar a stack, o estoque, a importacao SAP, o Dashboard ou o modelo monoempresa. A migration `025_commercial_flow.sql` permanece local ate backup e autorizacao de aplicacao.

## Modelo encontrado

- `orders.user_id` e `quotations.user_id` sao os proprietarios reais.
- `vendedor` e uma copia textual para exibicao e auditoria, nao uma autorizacao.
- Itens pertencem ao cabecalho por `order_id` ou `quotation_id`.
- `clients` representa clientes/parceiros internos. Nao ha portal de clientes neste modulo.
- Nao existe coluna de proprietario em `clients` nem tabela que associe SUPERVISOR a uma equipe.
- Os status validos sao os enums existentes: pedidos `NOVO`, `EM_ANALISE`, `APROVADO`, `CANCELADO`, `FATURADO`; cotacoes `NOVA`, `ENVIADA`, `APROVADA`, `CANCELADA`, `CONVERTIDA`.

## Ownership e perfis

- ADMIN consulta e opera todos os documentos.
- VENDEDOR consulta e opera somente documentos cujo `user_id = auth.uid()`.
- SUPERVISOR usa a mesma regra restritiva de ownership do VENDEDOR. Visao de equipe foi postergada porque o schema nao possui vinculo seguro de equipe.
- O proprietario de novos documentos e sempre derivado da sessao autenticada.
- A migration concede `novo_pedido` ao SUPERVISOR, mantendo ownership proprio.
- Parceiros permanecem uma referencia interna compartilhada conforme a permissao `parceiros` existente. O schema nao possui vendedor responsavel no cliente; esse campo nao e exibido nem inventado.

## Pedidos e cotacoes

As RPCs `commercial_create_order` e `commercial_create_quotation` validam sessao, modulo, cliente textual, regiao, lista de itens, produto, quantidade, preco e desconto. Cabecalho, itens, totais e log sao gravados na mesma transacao da chamada. Precos sao obtidos do produto para SP ou PR e o estoque nao e alterado.

Edicao de itens usa `commercial_update_order_items` e `commercial_update_quotation_items`. ADMIN pode editar qualquer documento; os demais somente os proprios. Pedidos cancelados/faturados/aprovados e cotacoes aprovadas/canceladas/convertidas nao aceitam alteracao de itens.

Status usa RPCs separadas com transicoes compativeis com os enums existentes. Estados terminais nao podem ser reabertos por usuario comum ou ADMIN por essas RPCs.

## Numeracao

`order_commercial_number_seq` e `quotation_commercial_number_seq` substituem a estrategia concorrente `MAX + 1`. A inicializacao considera os numeros puramente numericos existentes, nao renumera documentos antigos e preserva o formato de seis digitos usado no frontend.

## Conversao

`convert_quotation_to_order` aceita somente cotacao `APROVADA`, com itens, dentro do ownership do usuario ou do acesso ADMIN. A operacao:

1. bloqueia a cotacao durante a transacao;
2. verifica `quotation_order_conversions` para idempotencia;
3. preserva proprietario, cabecalho, itens e valores aprovados;
4. cria pedido `NOVO` com numero de sequence;
5. registra o vinculo e muda a cotacao para `CONVERTIDA`;
6. grava log e timeline.

Cotacoes canceladas, novas, enviadas ou ja convertidas nao geram um segundo pedido.

## Parceiros, favoritos e notas

`customer_favorites` e particular por usuario, com unicidade `(user_id, client_id)`, sem UPDATE e sem acesso de `anon` ou `PUBLIC`.

`customer_notes` exige cliente ativo, autor da sessao e texto de 1 a 2000 caracteres. O frontend exibe texto escapado. VENDEDOR e SUPERVISOR leem somente as proprias notas; ADMIN pode ler todas. Edicao e exclusao sao permitidas ao autor ou ADMIN pelas RPCs controladas. A autoria nao pode ser alterada diretamente.

O perfil comercial retorna somente dados basicos necessarios, metricas, dez documentos recentes, notas e timeline do escopo. Observacoes cadastrais internas do cliente sao removidas do retorno.

## Timeline

Eventos sao gerados por triggers de pedidos/cotacoes e pelas RPCs de notas. Escrita direta na tabela nao e concedida. Tipos sao limitados por constraint e metadados ficam restritos a titulo, descricao curta, entidade, UUID, valor e data.

## RLS e grants

- Pedidos/cotacoes: SELECT e UPDATE por ADMIN ou proprietario; itens herdam o acesso do cabecalho.
- Escrita direta em pedidos, cotacoes e itens e revogada; criacao e alteracoes passam pelas RPCs.
- Favoritos: SELECT/INSERT/DELETE apenas do proprio usuario.
- Notas e timeline: SELECT do autor ou ADMIN; escrita somente por RPC/trigger.
- Conversoes: ADMIN ou proprietario da cotacao.
- RPCs publicas da 025: somente `authenticated`.
- Helpers internos e RPCs legadas recebem `REVOKE` de `PUBLIC`, `anon` e `authenticated` quando substituidos.

## Frontend e fallback

O frontend tenta uma RPC da 025 uma vez. Se o PostgREST indicar funcao ausente, marca a capacidade como indisponivel na sessao, registra um unico `console.info` e usa as RPCs legadas apenas para criar, editar itens e atualizar status. Perfil comercial e conversao exibem uma mensagem clara ate a migration ser aplicada. Isso evita 404 repetitivo.

Duplicar abre um novo rascunho local com os dados do documento acessivel. Nada e salvo sem revisao e clique em Salvar; o servidor volta a validar ownership, produtos, precos e desconto.

No celular, itens viram blocos verticais, campos numericos e acoes mantem altura minima de 44px, totais ficam fora da tabela e a pagina nao depende de overflow horizontal.

## Aplicacao controlada

1. Criar e validar backup remoto.
2. Confirmar que a migration 025 ainda esta pendente.
3. Revisar diff e executar a migration em uma unica transacao.
4. Atualizar o cache do PostgREST se necessario.
5. Testar ADMIN, SUPERVISOR e VENDEDOR com documentos descartaveis.
6. Confirmar ownership, RLS, sequencias, conversao idempotente e limpeza dos dados de teste.

## Rollback

`supabase/rollback/025_commercial_flow_rollback.sql` nao e automatico. Ele remove triggers, RPCs, policies e tabelas complementares da fase, restaura as policies legadas de leitura e reabilita as RPCs anteriores. Pedidos, cotacoes, itens, produtos, clientes, perfis e `company_settings` sao preservados.

Favoritos, notas, timeline e vinculos de conversao sao dados complementares e seriam perdidos no rollback. Pedidos ja criados por conversao permanecem; por isso deve ser feito backup antes do rollback e uma conciliacao manual pode ser necessaria.

## Limitacoes

- Sem relacao supervisor-equipe, nao existe visao de equipe segura nesta fase.
- `clients` nao possui proprietario/vendedor responsavel.
- O documento comercial nao possui FK para `clients`; o vinculo para perfil/timeline usa codigo SAP ou CNPJ normalizado quando disponivel. O nome do cliente continua obrigatorio para compatibilidade.
- Recursos novos nao podem ser aprovados funcionalmente contra o banco remoto antes da aplicacao controlada da migration 025.
