# CRM no Supabase

## Arquitetura final

- GitHub: versionamento e deploy do frontend pelo GitHub Pages.
- Supabase: Authentication, PostgreSQL, RLS, RPCs, produtos, pedidos, usuarios e logs.
- Frontend: HTML, CSS e JavaScript puro em `public/`.

## Banco

1. Em um projeto Supabase, execute `supabase/migrations/001_schema.sql`.
2. Em Authentication > Providers, habilite Email.
3. Crie usuarios no Supabase Auth.
4. Insira ou atualize os perfis correspondentes em `profiles`.
   - Para o admin inicial, use `supabase/seed/002_create_admin_profile_template.sql`.

## Importacao inicial

```powershell
& "C:\Users\deivi\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" .\scripts\xlsx_to_supabase_csv.py .\planilha_google.xlsx .\supabase_import
```

Depois importe com:

```powershell
$env:SUPABASE_DB_URL="SUA_URL_DO_POOLER"
node .\scripts\import_supabase_csv.mjs
Remove-Item Env:\SUPABASE_DB_URL
```

## Frontend

Configure `public/js/config.js` com:

- `SUPABASE_CONFIG.url`
- `SUPABASE_CONFIG.anonKey`

O frontend nao usa Firebase, Apps Script ou backend Node proprio.

## GitHub Pages

O workflow `.github/workflows/pages.yml` publica a pasta `public/` automaticamente em push na branch `main`.

## Arquivos gerados localmente

O conversor ja foi testado com `planilha_google.xlsx` e gerou:

- `supabase_import/products.csv`
- `supabase_import/carriers.csv`
- `supabase_import/payment_terms.csv`

## Observacao sobre senhas

Senhas antigas nao devem ser migradas. Crie usuarios no Supabase Auth e envie senha temporaria ou reset por email.
