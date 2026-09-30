# Prontidao de producao - politica SP somente IPI

Data da auditoria: 30/09/2026.

## Limites desta execucao

- Producao foi consultada em modo somente leitura e permaneceu sem migrations ou alteracoes de dados.
- O projeto de producao estava pausado e foi apenas retomado para permitir a auditoria.
- O ensaio foi executado em um clone PostgreSQL local restaurado do schema `public` de producao.
- Nenhum secret, token, cliente, pedido ou usuario foi exportado para o repositorio.

## Estado encontrado

- Producao possui migrations registradas somente ate `030`.
- As migrations `031` a `090` ainda nao existem em producao.
- Producao tinha 4.035 produtos, nenhum NCM preenchido, nenhuma regra fiscal e nenhum preco por filial.
- O runner privado do OneDrive permanece apontado para homologacao e desabilitado para agenda automatica.
- A planilha corrente no OneDrive tem versao
  `733fefc38565276f9fa173128415861037aab92218d39595f690929154444f0b`.

## Ensaio integral no clone de producao

As migrations `031` a `092` foram aplicadas em sequencia no clone. O lote corrente da
homologacao foi entao processado pelo pipeline normal:

| Area | Linhas | Resultado |
| --- | ---: | --- |
| Produtos | 4.240 | 205 inseridos e 4.035 atualizados |
| Estoques PR | 4.045 | 10 inseridos e 4.035 atualizados |
| Precos base PR/SP | 6.736 | inseridos |
| Precos por rota | 10.104 | inseridos |
| Total | 25.125 | zero erro, zero aviso |

Resultado do commit:

- 17.055 insercoes;
- 8.070 atualizacoes;
- 168.959 registros de auditoria por campo;
- segunda execucao reconhecida como duplicada;
- somente um lote persistido para a mesma versao/hash.

As bases imutaveis usadas para comparar o motor do CRM com a planilha tambem foram
carregadas: 82 regras por NCM e 168 regras por grupo. A segunda carga retornou
`duplicate=true`.

## Defeitos de upgrade encontrados e corrigidos

### Timestamp tecnico bloqueava o primeiro estoque

A migration `033` executa um UPSERT legado que toca `updated_at` e `version` mesmo
quando o saldo nao muda. Aplicada imediatamente antes da primeira sincronizacao,
ela fazia 4.035 estoques validos parecerem mais antigos que o banco.

A migration `091` corrige somente a pegada exata desse no-op: filial PR, sem origem
atribuida, versao 1 e saldo ainda igual ao ultimo movimento auditado. Saldos,
reservas e movimentos nao sao alterados.

### Produto novo criava conflito com o proprio estoque do lote

O gatilho legado criava saldo zero ao inserir um produto. Para 10 produtos novos
que tambem tinham estoque no mesmo lote, isso convertia o INSERT planejado em um
conflito de concorrencia.

A migration `092` deixa de pre-criar somente a filial que ja possui uma linha
STOCK valida no mesmo lote. As demais filiais continuam recebendo a fundacao de
saldo zero. O segundo ensaio integral terminou sem conflitos.

## Bloqueio fiscal atual

As 76 regras fiscais existentes em homologacao nao podem ser promovidas como estao:
todas permanecem em `REVIEW_REQUIRED`, sem validacao nem ativacao formal do fluxo
de governanca.

Para SP -> SP em 01/10/2026, a homologacao apresenta:

- 3.368 produtos com preco SP;
- 2.228 calculos CRM que conferem com a planilha;
- 81 calculos com divergencia exclusivamente no IPI;
- 1.059 produtos bloqueados por falta de regra CRM aplicavel;
- 24 regras CRM candidatas, todas em `REVIEW_REQUIRED`;
- na comparacao por NCM: 22 IPIs conferem, 1 diverge, 1 esta indefinido e 6 regras
  da planilha nao possuem correspondente no CRM.

A politica `SP_IPI_ONLY_2026_10_01` remove ICMS-ST do total, mas deliberadamente
bloqueia o preco quando regra/base/IPI do motor CRM estiver ausente. Isso evita
vender com tributacao presumida.

## Gate obrigatorio antes de producao

Producao nao deve receber a carga fiscal enquanto nao houver aprovacao dos IPIs e
da cobertura dos NCMs abaixo:

1. validar a regra de IPI divergente;
2. definir o IPI da regra atualmente incompleta;
3. criar ou aprovar as seis regras ausentes no CRM;
4. revisar os 1.059 produtos atualmente bloqueados;
5. promover regras pelo fluxo de governanca, registrando responsavel e fundamento;
6. repetir o relatorio e exigir zero `MISMATCH` e zero
   `PRECO_FISCAL_INDISPONIVEL` para os produtos liberados para venda.

## Sequencia segura para a janela noturna

1. Confirmar backup/PITR do Supabase e gerar novo dump imediatamente antes da janela.
2. Manter o runner OneDrive desabilitado.
3. Aplicar migrations em producao e conferir a tabela de historico.
4. Rodar smoke tests de autenticacao, catalogo, cotacao e pedido sem gravar documento fiscal.
5. Carregar primeiro produtos, estoques e precos pelo pipeline idempotente.
6. Conferir contagens, erros, avisos e auditoria.
7. Carregar as bases Excel somente como referencia de validacao.
8. Promover apenas as regras fiscais formalmente aprovadas.
9. Executar o relatorio SP -> SP de 01/10/2026 e validar amostras com o responsavel fiscal.
10. Somente depois apontar o runner privado e a Edge Function para producao.

Em qualquer falha, manter o runner desabilitado. O CRM continua operando com o
ultimo estado valido do Supabase. O retorno completo de schema/dados deve usar o
dump/PITR da janela; a politica `090` tambem possui rollback dedicado.
