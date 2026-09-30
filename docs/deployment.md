# Publicação e ambientes

## Regra principal

Código, migrations e Edge Functions são promovidos nesta ordem:

```text
branch -> CI -> homologação -> validação -> aprovação -> produção
```

Nenhuma etapa de frontend aplica migrations automaticamente. Produção exige
backup verificável e autorização explícita.

## Repositórios

- `crm-autopecas-supabase`: fonte canônica de código e migrations;
- `crm-autopecas-supabase-homolog`: destino temporário do GitHub Pages de
  homologação, sem desenvolvimento independente;
- `ips-crm-excel-sync-private`: executor privado com os secrets Microsoft.

O repositório de homologação pode ser mantido como espelho de deploy enquanto
o GitHub Pages não oferecer dois sites independentes no repositório canônico.
O conteúdo deve sempre ser gerado a partir de uma revisão do canônico.

## Preparar GitHub

1. Proteja `main` e exija o workflow `Security checks`.
2. Bloqueie push direto em `main`.
3. No ambiente `github-pages`, permita deploy somente de `main` e configure um
   aprovador obrigatório para produção.
4. Crie ambiente `homologacao` com variáveis próprias e sem secrets de produção.
5. Mantenha o executor OneDrive privado com `DATA_SYNC_ENABLED=false` até o
   teste ponta a ponta ser aprovado.

## Homologação

1. Execute `npm test`.
2. Confirme que `git diff --check` não apresenta erro.
3. Confirme que migrations aplicadas não foram editadas.
4. Gere backup do Supabase e registre data, responsável e mecanismo de restauração.
5. Compare migrations locais e remotas com `npm run supabase:migrations:status`.
6. Execute regressões SQL em transação com `ROLLBACK` ou banco descartável.
7. Aplique somente migrations pendentes revisadas.
8. Publique Edge Functions compatíveis.
9. Publique o frontend de homologação a partir do mesmo commit.
10. Execute smoke tests administrativos, comerciais, B2B e Data Sync.

## Produção

1. Escolha exatamente o commit aprovado em homologação.
2. Confirme backup/PITR e procedimento de restauração.
3. Revise novamente a lista de migrations pendentes.
4. Aplique banco e Edge Functions antes do frontend quando houver dependência.
5. Libere o deploy no ambiente protegido `github-pages`.
6. Execute smoke tests somente leitura e uma operação controlada autorizada.
7. Registre resultado, horário e responsável.

## Rollback

- frontend: republicar o último commit aprovado;
- Edge Function: republicar a versão anterior conhecida;
- banco: preferir migration corretiva; não reescrever migration aplicada;
- dados: restaurar backup/PITR somente com decisão explícita, pois a restauração
  pode substituir alterações realizadas após o ponto escolhido;
- integração: definir `DATA_SYNC_ENABLED=false`; o CRM continua usando os
  últimos dados válidos do Supabase.
