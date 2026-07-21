# V3 - Identidade neutra da empresa

## Objetivo

Separar a identidade da empresa da estrutura do CRM, sem implementar multiempresa e sem alterar regras de negocio.

Esta etapa prepara o CRM para consumir uma configuracao institucional unica em `public.company_settings`.

## Backup antes da alteracao

Backup completo criado antes de qualquer edicao desta etapa:

- Arquivo: `C:\Users\deivi\OneDrive\Documentos\New project\supabase\admin\backups\crm_supabase_full_v3_prechange_20260719_220438.dump`
- Data/hora: `2026-07-19 22:04:38 -03:00`
- `pg_dump`: exit code `0`
- Tamanho: `465.730 bytes`
- `pg_restore --list`: exit code `0`
- SHA-256: `976467A17DEBDCCF0CDECAEF9ACF7DC157843531F90E05B16A12284CF8062397`

## Arquivos criados

- `supabase/migrations/023_company_settings.sql`
- `supabase/rollback/023_company_settings_rollback.sql`
- `public/js/company_settings.js`

## Arquivos alterados

- `public/index.html`
- `public/app.html`
- `public/js/app.js`
- `public/css/app.css`
- `public/css/login.css`
- `public/js/orders.js`
- `public/js/quotes.js`
- `public/cadastro-publico/index.html`
- `public/cadastro-publico/js/portal.js`

## Banco

A migration cria a tabela singleton `public.company_settings` com:

- nome da empresa;
- nome fantasia;
- CNPJ;
- endereco;
- cidade;
- UF;
- CEP;
- telefone;
- WhatsApp;
- e-mail;
- site;
- logotipo;
- cor principal;
- cor secundaria;
- moeda;
- timezone;
- idioma;
- data de criacao;
- ultima atualizacao.

Nao ha coluna de tenant, empresa ativa por usuario, escopo por empresa ou qualquer regra multiempresa.

## RLS e permissoes

- Leitura direta de `company_settings`: restrita a `authenticated`.
- Leitura publica antes do login: feita pela RPC `public.get_public_company_identity()`, que retorna somente campos institucionais reduzidos.
- Escrita: restrita por `public.is_admin()`.
- `ADMIN` recebe permissao `configuracoes_empresa`.

## Frontend

A tela `Configuracoes da Empresa` foi adicionada ao app como modulo administrativo.

O carregador `company_settings.js`:

- busca a identidade publica pela RPC `get_public_company_identity`;
- busca a configuracao completa diretamente na tabela apenas para usuarios autenticados na tela administrativa;
- aplica nome, logotipo, idioma e cores na tela de login e no shell do app;
- usa fallback neutro `Nova Empresa` se a tabela ainda nao existir ou se a migration ainda nao foi aplicada.

## Pontos neutralizados

- Titulo da tela de login.
- Eyebrow da tela de login.
- Logotipo/nome exibidos no login.
- Titulo do app.
- Marca exibida na sidebar do app.
- Filial exibida em pedidos e cotacoes.
- Identidade exibida no portal publico de cadastro.

## Escopo nao alterado

Por requisito, nao foram alterados fluxos ou regras de:

- Produtos;
- Pedidos;
- Cotacoes;
- Dashboard;
- Importacao SAP.

Textos tecnicos de planilhas/importacao que mencionam `CODIGO IPS` nao foram alterados nesta etapa porque fazem parte do fluxo de Importacao SAP, explicitamente fora do escopo.

## Aplicacao

Ordem sugerida quando for autorizado aplicar:

1. Confirmar backup recente.
2. Aplicar `supabase/migrations/023_company_settings.sql`.
3. Validar existencia de `public.company_settings`.
4. Validar leitura anonima da identidade no login.
5. Validar edicao como ADMIN.
6. Validar que Produtos, Pedidos, Cotacoes, Dashboard e Importacao SAP continuam sem mudancas funcionais.
7. Somente depois, publicar/deployar o frontend.

## Rollback

Rollback preparado em:

`supabase/rollback/023_company_settings_rollback.sql`

O rollback remove:

- permissao `ADMIN/configuracoes_empresa`;
- policies da tabela;
- trigger de atualizacao;
- tabela `public.company_settings`.

Nao altera dados de Produtos, Pedidos, Cotacoes, Dashboard ou Importacao SAP.

## Estado desta entrega

- Backup criado.
- Migration criada.
- Rollback criado.
- Documentacao criada.
- Frontend preparado localmente.
- Migration nao aplicada no Supabase remoto.
- Deploy nao executado.
- Migration corretiva `027_company_settings_hardening.sql` preparada porque o status remoto da `023` nao pode ser confirmado sem token da CLI Supabase.
- O pedido original citava `024_company_settings_hardening.sql`; como `024`, `025` e `026` ja existem no repositório, foi criada a proxima migration livre, `027_company_settings_hardening.sql`, para preservar a sequencia.

## Auditoria da Fase 1 - 2026-07-20

### Finalidade

`company_settings` centraliza a identidade institucional do CRM em um unico registro de configuracao. O sistema continua monoempresa: nao existe tenant, selecao de empresa por usuario, escopo por empresa em pedidos/produtos/cotacoes ou regra multiempresa.

### Campos disponiveis

- `company_name`: nome legal, obrigatorio.
- `trade_name`: nome fantasia, opcional.
- `cnpj`: somente digitos no frontend, opcional.
- `address`, `city`, `state`, `zip_code`: endereco, opcionais.
- `phone`, `whatsapp`, `email`, `website`: contatos, opcionais.
- `logo_url`: URL/caminho do logotipo, opcional.
- `primary_color`, `secondary_color`: cores hexadecimais `#RRGGBB`, obrigatorias.
- `currency`: moeda, padrao `BRL`.
- `timezone`: timezone, padrao `America/Sao_Paulo`.
- `language`: idioma, padrao `pt-BR`.
- `created_at`, `updated_at`: controle de criacao e atualizacao.

### Permissoes auditadas

Policies previstas na migration:

- `company_settings_read`: `for select using (auth.uid() is not null)`.
- `company_settings_admin_write`: `for all using (public.is_admin()) with check (public.is_admin())`.

Grants previstos:

- `revoke all on public.company_settings from anon`.
- `grant select on public.company_settings to authenticated`.
- `grant insert, update, delete on public.company_settings to authenticated`.
- `grant execute on function public.get_public_company_identity() to anon, authenticated`.

Conclusao: anon nao acessa a tabela diretamente. A marca do login e do portal publico vem da RPC com payload reduzido. Escrita depende de usuario autenticado e passa por RLS `public.is_admin()`. No frontend, o modulo tambem esta marcado como `adminOnly`.

### Como cadastrar ou trocar logo

Na tela `Configuracoes da Empresa`, informar `Logotipo URL` com caminho relativo (`assets/logo-neutral.svg`) ou URL absoluta. Ao salvar, o frontend atualiza os elementos com `data-company-logo` no login e no shell do app.

Formatos recomendados: PNG, SVG, JPG ou WEBP hospedados em origem acessivel pelo navegador. A migration nao valida MIME/type porque armazena apenas URL.

### Comportamento padrao

Se a tabela ainda nao existir, se a migration nao tiver sido aplicada ou se a consulta falhar, o frontend usa:

- nome: `Nova Empresa`;
- logo: `assets/logo-neutral.svg`;
- cor principal: `#0d6b5f`;
- cor secundaria: `#17212b`;
- moeda: `BRL`;
- timezone: `America/Sao_Paulo`;
- idioma: `pt-BR`.

Campos opcionais vazios sao salvos como `null`.

### Backup e rollback

Backup validado:

- `supabase/admin/backups/crm_supabase_full_v3_prechange_20260719_220438.dump`
- SHA-256: `976467A17DEBDCCF0CDECAEF9ACF7DC157843531F90E05B16A12284CF8062397`
- `pg_restore --list`: exit code `0`, 814 linhas listadas.

Rollback:

- `supabase/rollback/023_company_settings_rollback.sql`

O rollback remove a permissao `ADMIN/configuracoes_empresa`, policies, trigger e tabela `company_settings`.

### Limitacoes e pendencias encontradas

- A migration `023` foi endurecida localmente, mas se ela ja tiver sido aplicada no remoto, deve-se aplicar a corretiva `027`.
- `cnpj` permanece sem constraint de tamanho/validacao no banco para evitar bloquear cadastros legados; a normalizacao continua no frontend.
- `email` e `website` permanecem com validacao de frontend; a `027` nao muda dados comerciais.
- A migration historica `007_portal_cadastros_settings.sql` ainda contem o e-mail antigo como historico de migration. A `027` neutraliza o valor gravado em `settings` se ele ainda estiver igual ao antigo.
- `CODIGO IPS` permanece em textos tecnicos da Importacao SAP por compatibilidade com planilhas existentes.

### Correcao das pendencias da auditoria - 2026-07-20

- Login: watermark do logotipo deixou de ser CSS fixo e passou a usar `data-company-logo-watermark`.
- App e login: logo com `onerror` volta para `assets/logo-neutral.svg` quando a imagem configurada falha.
- Portal publico: consome `get_public_company_identity()` para nome, logo, cores e contato, sem leitura direta da tabela.
- Pedidos e cotacoes: campo `Filial` usa `formatCompanyBranchLabel(company_settings)`.
- Edicao de pedidos/cotacoes existentes: campo readonly de filial usa a identidade carregada em cache.
- Edge Function de cadastro: removidos defaults antigos de destinatario e remetente; agora exige `CADASTRO_EMAIL_TO` e `CADASTRO_EMAIL_FROM` ou `GMAIL_SMTP_USER`.
- Script de admin inicial: removido default de e-mail antigo; agora exige `SUPABASE_ADMIN_EMAIL`.
