# Banco de dados — homologação

## Contexto

O backend é PostgreSQL/Supabase. Regras transacionais, RLS, importações e o
cálculo fiscal autoritativo ficam no banco; o navegador não é fonte de verdade
para preço ou imposto.

Ambiente auditado: `mtwvxyvpnbgwgltelozw`. Produção não foi acessada.

## Baseline e migrations

O repositório canônico consolida migrations 001–090. Nenhuma migration já
aplicada foi renumerada ou reescrita durante a consolidação. Na última
verificação somente leitura, a homologação possuía 001–081 aplicadas e 082–089
permaneciam apenas no Git, aguardando backup e regressões controladas.

A migration 090 adiciona uma política comercial datada sem modificar a tabela
de preços consolidados do Excel. Para SP→SP, documentos criados a partir de
01/10/2026 usam somente base + IPI calculados pelas regras vigentes do motor
fiscal do CRM. O resultado do Excel é apenas uma referência de validação:
`MATCH`, `MISMATCH`, incompleta ou ausente. O resultado grava a política, a
regra e as diferenças no snapshot fiscal do item; documentos criados antes da
vigência permanecem inalterados.

A migration 094 torna a política SP-SP fail-closed: o preço base + IPI só fica
disponível quando a comparação com a referência Excel resultar em `MATCH`.
NCM ausente, referência incompleta ou divergência bloqueiam o item sem alterar
os dados-fonte importados. A liberação ocorre automaticamente quando a regra do
motor e a referência vigente voltarem a coincidir.

A definição real de `resolve_fiscal_tax_rule` foi recuperada por introspecção
somente leitura e considerada nos testes de resolução histórica. Dumps de
schema servem como evidência auxiliar e não substituem migrations versionadas.

## Estruturas fiscais principais

- `fiscal_tax_rules`: estado operacional atual de cada regra e sua vigência;
- `fiscal_tax_rule_versions`: snapshots imutáveis por `rule_id` e
  `rule_version`;
- `products_import_batches`, `products_import_stage` e
  `products_import_audit`: staging, idempotência e auditoria da importação;
- `quotation_items` e `order_items`: memória fiscal usada na operação;
- `logs`: auditoria administrativa antes/depois.

## Integridade da Fase 5B

- regra em uso não pode ser editada diretamente;
- nova versão nasce como `DRAFT` e fora do cálculo;
- ativação encerra a vigência anterior dentro da mesma transação;
- regra anterior permanece resolvível para datas históricas;
- `DELETE` administrativo foi substituído por desativação auditada;
- histórico rejeita `UPDATE` e `DELETE` por trigger;
- conflito de períodos ativos continua bloqueado;
- funções administrativas não possuem `EXECUTE` para `anon`/`PUBLIC`.

## Estado observado após aplicação

- 76 regras existentes;
- 76 classificadas como `REVIEW_REQUIRED` e mantidas em uso por continuidade;
- 76 snapshots de baseline em `fiscal_tax_rule_versions`;
- migrations 058 e 059 registradas;
- nenhuma alíquota, MVA, NCM, CEST, rota ou fórmula alterada.

## Rollback seguro

Não apagar a tabela de histórico nem os metadados para reverter comportamento.
Caso seja necessário suspender a governança, criar migration posterior que
desative os triggers/RPCs novos, preservando os snapshots. Nunca editar as
migrations já aplicadas.

## Confirmação fiscal SP-SP — lote 2

Em 06/10/2026, a migration 098 foi aplicada somente na homologação. Doze NCMs
em `REVIEW_REQUIRED` foram ativados depois de todos os 2.122 preços SP-SP
atuais coincidirem com a referência Excel na tolerância de R$ 0,02. A regra
manual legada de 5% do NCM `87089990` teve sua vigência encerrada em 24/08/2026;
a regra SAP sucessora de 3,25% permanece vigente desde 25/08/2026. Nenhum
registro histórico foi apagado.

Após a aplicação, a rota SP-SP possui 20 NCMs ativos cobrindo 3.336 produtos,
4 NCMs em revisão cobrindo 24 produtos e 3 NCMs sem regra cobrindo 8 produtos.
A promoção para produção permanece pendente de autorização explícita.
