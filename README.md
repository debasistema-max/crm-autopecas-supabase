# CRM IPS do Brasil / Yokomitsu

CRM estático publicado no GitHub Pages, com Supabase para autenticação, banco,
RLS, RPCs e Edge Functions. O Supabase é a fonte operacional; Excel/OneDrive é
uma origem de atualização e nunca é consultado pelo CRM durante uma venda.

## Arquitetura

```text
OneDrive pessoal -> Microsoft Graph -> executor GitHub privado
                 -> Edge Function excel-sync
                 -> staging -> validação -> commit -> auditoria
                 -> Supabase -> CRM

Upload manual    -> staging -> validação -> commit -> auditoria
SAP (futuro)     -> adapter -> mesmo contrato Data Sync
```

O executor com o refresh token Microsoft permanece no repositório privado
`ips-crm-excel-sync-private`. Este repositório não deve receber esse token.

## Pré-requisitos

- Git;
- Node.js 20 ou superior;
- Python 3.12 ou superior;
- Supabase CLI para operações controladas de banco e Edge Functions;
- acesso ao projeto Supabase de homologação.

## Preparar um computador novo

```powershell
git clone https://github.com/debasistema-max/crm-autopecas-supabase.git
cd crm-autopecas-supabase
npm install
npm run setup:python
Copy-Item .env.example .env.local
npm test
npm run dev
```

Confirme `python --version` antes de continuar. Em Windows, desative o alias da
Microsoft Store caso ele esteja ocultando a instalação real do Python.

Abra `http://localhost:4173`. O arquivo `.env.local` é ignorado pelo Git.
Valores sensíveis devem ser configurados no Supabase ou no GitHub, nunca nos
arquivos de `public/`.

## Ambientes

- **Homologação:** recebe primeiro migrations, Edge Functions e testes de integração.
- **Produção:** somente depois de backup, regressões em homologação e aprovação manual.

As chaves `anon` presentes nos arquivos públicos identificam o projeto e não
são credenciais administrativas. A segurança depende de RLS e das permissões
das RPCs. `service_role`, tokens Graph, PATs e senhas são sempre secretos.

## Comandos

```powershell
npm run dev                         # servidor estático em public/
npm test                            # sequência, sintaxe, contratos e testes Python
npm run check:migrations            # exige sequência histórica 001-089
npm run supabase:migrations:status  # somente leitura no projeto vinculado
```

Os comandos `legacy:supabase:*` existem apenas para rastreabilidade do bootstrap
antigo. Não devem ser usados para reconstruir ou atualizar homologação/produção.

## Banco de dados

- migrations aplicadas são imutáveis;
- novas mudanças recebem o próximo número sequencial;
- regressões SQL ficam em `supabase/tests/`;
- testes SQL devem usar banco descartável ou transação encerrada com `ROLLBACK`;
- nenhuma migration deve ser aplicada automaticamente durante o deploy do frontend.

O histórico versionado contém `001-089`. O banco remoto de homologação deve ser
tratado separadamente: na última auditoria, `001-081` estavam aplicadas e
`082-089` ainda aguardavam validação.

## OneDrive pessoal

A configuração alvo usa fluxo de dispositivo, `offline_access` e
`Files.ReadWrite.AppFolder`. A planilha e os backups ficam dentro da pasta do
aplicativo. A agenda permanece desativada enquanto `DATA_SYNC_ENABLED` não for
explicitamente definido como `true` no executor privado.

Consulte [docs/data-sync.md](docs/data-sync.md) para o contrato operacional e
[docs/testing.md](docs/testing.md) para as validações antes de publicar. O
procedimento de ambientes e rollback está em
[docs/deployment.md](docs/deployment.md).

## Deploy

O GitHub Pages publica somente `public/`. O merge em `main` não deve ocorrer
antes de validar a configuração do ambiente e confirmar que os testes passaram.
Produção deve usar GitHub Environment protegido e aprovação manual.
