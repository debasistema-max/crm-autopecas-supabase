# Desconto sobre a base - pedidos e cotacoes

## Contrato

- A base original e os componentes fiscais vem do snapshot aprovado da rota/NCM.
- Desconto monetario = base original x percentual / 100.
- A base e os componentes proporcionais de IPI/ST sao recalculados pelo fator
  `(1 - percentual / 100)`. A regra vigente, a rota e o NCM nao sao alterados.
- ICMS proprio destacado na memoria nao e somado novamente ao total.
- Outros componentes existentes sao preservados e identificados, nunca descartados.
- Precisao: componentes com seis casas; final unitario com quatro; total de
  cada linha com duas. Total do documento e a soma dos totais das linhas.
- `subtotal` passa a representar a base original; `desconto_total` representa
  somente o desconto sobre essa base. `total` inclui a base descontada e impostos.

## Persistencia

Migration 117 envolve as RPCs transacionais existentes, preservando suas
verificacoes de sessao, permissao, carteira e status. O calculo do navegador e
apenas previa; o servidor ignora totais enviados pelo cliente.

`fiscal_details.undiscounted_price` preserva a evidencia aprovada e impede desconto
duplicado ao reabrir/editar. Os campos fiscais operacionais registram os valores
apos desconto. Cada gravacao registra `RECALCULAR_IMPOSTOS_DESCONTO_BASE`.

Nao ha atualizacao em massa de documentos, produtos, precos ou regras durante a
migration. Documentos existentes somente mudam quando o usuario salva os itens.
A conversao copia o snapshot salvo e mantem a autorizacao legada.
O portal B2B nao tem seu fluxo de criacao alterado nesta etapa.

## Publicacao controlada

1. Backup novo de producao, com hash, tamanho e leitura do TOC verificados.
2. Ensaiar migration e regressao 117 em transacao terminada em rollback.
3. Conferir hashes dos registros protegidos antes/depois.
4. Aplicar 117 somente com ensaio aprovado e backup recente verificado.
5. Publicar frontend completo (incluindo os novos JS/CSS e cache-bust).
6. Testar criacao e edicao nas duas telas, desktop/mobile, com e sem desconto.

Os testes transacionais criam identidades e documentos sinteticos descartados;
sequencias PostgreSQL podem consumir numeros mesmo com rollback. Nao restaurar
sequencias concorrentes para tentar remover lacunas.

## Contingencia

Nao apagar snapshots nem restaurar um dump sobre producao em uso. Antes de
reverter, inspecionar documentos criados apos a mudanca. Uma migration corretiva
pode restaurar os wrappers anteriores a partir das funcoes `*_raw_117`, mantendo
os documentos novos para tratamento explicito. Nunca executar o finalizador em
documentos antigos por rotina de manutencao.

Homologacao esta indisponivel por falta de disco; nao tentar aplicar nada nela
antes da recuperacao. A validacao visual em navegador e uma etapa distinta dos
testes unitarios e SQL, e precisa ser registrada explicitamente.
