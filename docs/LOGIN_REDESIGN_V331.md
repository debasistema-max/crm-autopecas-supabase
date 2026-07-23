# Sprint v3.3.1 - Redesign da tela de login

## Objetivo

Redesenhar exclusivamente a apresentacao da tela de login, preservando Supabase Auth, resolucao de usuario, sessao, perfis, permissoes e redirecionamento existentes.

## Arquivos

- `public/index.html`: estrutura semantica e reduzida da tela.
- `public/css/login.css`: estilos isolados, responsivos e white label.
- `public/js/auth.js`: estados visuais, controle de reenvio e exibicao temporaria da senha.

## Identidade e fallback

A tela continua consumindo `get_public_company_identity` pelo mecanismo existente em `company_settings.js`. Nome, logo e cores sao aplicados dinamicamente. Antes da resposta da rede, a interface usa `Nova Empresa`, o logo neutro local e cores seguras. Uma URL de logo invalida retorna para o logo neutro.

## Autenticacao

A funcao `supabaseLogin`, o armazenamento da sessao e o redirecionamento para `app.html` nao foram alterados. A camada visual impede envios simultaneos, informa carregamento e sucesso, oculta novamente a senha e apresenta erro generico sem detalhes tecnicos.

## Limites

Nao foram adicionadas migrations, tabelas, RPCs, policies, dependencias, imagens externas ou mudancas nos demais modulos do CRM.
