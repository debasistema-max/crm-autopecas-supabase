# CRM IPS/Yokomitsu

## Escopo e segurança

- Trabalhe primeiro em homologação. Nunca aplique migration, publique Edge Function ou faça deploy em produção sem autorização explícita.
- Não altere nem renumere migrations já aplicadas. Toda mudança de banco deve ser uma migration nova e reversível quando tecnicamente possível.
- Nunca coloque senhas, tokens, refresh tokens, `service_role` ou client secrets no frontend, nos testes ou no Git.
- Preserve a importação manual como contingência e reutilize o pipeline de staging, validação, commit e auditoria.
- Campos vazios de integração não podem apagar valores válidos; limpeza deve ser explícita.

## Onde trabalhar

- Frontend publicado: `public/`.
- Regras de banco e RLS: `supabase/migrations/`.
- Edge Functions: `supabase/functions/`.
- Normalização OneDrive/Excel: `scripts/`.
- Regressões estáticas/Python: `tests/`.
- Regressões SQL: `supabase/tests/` e somente em banco descartável ou transação com `ROLLBACK`.

## Documentação por contexto

- Consulte `docs/architecture.md` ao mudar fronteiras entre frontend, Supabase e integrações.
- Consulte `docs/database.md` antes de mudanças de schema, RLS ou RPC.
- Consulte `docs/data-sync.md` ao mudar Excel, OneDrive, staging ou commit.
- Consulte `docs/testing.md` ao preparar validação ou deploy.

## Verificação mínima

- Execute `npm test` antes de entregar alterações de código.
- Verifique `git diff` e confirme que nenhum segredo ou arquivo XLSX foi incluído.
- Alterações de integração devem comprovar idempotência, preservação de campos vazios e continuidade do CRM quando a origem estiver indisponível.
