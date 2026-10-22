# Promocao controlada de 22/10/2026

## Escopo

- Portal do vendedor com navegacao e catalogo responsivos.
- Ampliacao acessivel da foto e informacoes tecnicas do catalogo instalado.
- Listas por multiplas linhas e segmento comercial de veiculo.
- Catalogo geral paginado e exportacoes completas CSV/XLSX.
- Inatividade persistente ADMIN, selecao e inativacao em lote (ate 200).
- Exclusoes comerciais permanentes dos 74 codigos da migration 112.
- Fila independente para sincronizar o catalogo instalado nesta maquina.

## Fronteiras preservadas

O frontend continua em `public/`. As configuracoes do CRM, B2B e cadastro
publico continuam apontando para producao. Nao copiar configuracoes, dados,
usuarios, sessoes ou credenciais de homologacao.

Migrations antigas, regras fiscais, Edge Functions de login e Excel, workflow
privado do Excel e normalizador OneDrive de producao nao foram substituidos.
Pedidos, cotacoes e login conservam seus contratos existentes.

## Sequencia operacional

1. Backup PostgreSQL 17 completo, roles sem senhas, hashes e indice verificados.
2. Ensaio das migrations 106-112 e regressoes dentro de transacao com rollback.
3. Comparar produtos, usuarios, pedidos, cotacoes, anos, precos, estoque e fiscal.
4. Aplicar 106-112 numa transacao, com registro no historico de migrations.
5. Provisionar executor exclusivo de producao, sem conceder acesso a tabelas.
6. CI completo, revisao e merge da PR; aguardar GitHub Pages.
7. Verificar arquivos publicados e respostas anonimas bloqueadas.

As fixtures 106/107 agora inativam seus produtos ficticios pela RPC ADMIN;
insercoes da origem nao podem escolher a atividade desde a migration 109.

## Executor local de producao

O script desta branch aceita exclusivamente `doenvnjzrecrtvwooaai`; rejeita
homologacao e usuarios administrativos. Configuracao privada separada:
`%LOCALAPPDATA%\IPSCRM\InstalledCatalogWorkerProduction\config.json`.
Tarefa: `IPS Catalogo Local Producao`. A tarefa de homologacao permanece intacta.
Registro usa caminhos fisicos e verifica TLS/role antes de ativar a tarefa.
Nao registrar segredos em Git, argumentos de processo, logs ou frontend.

Publicacao nao significa copiar os dados de homologacao nem iniciar uma
importacao definitiva. A sincronizacao real e solicitada por ADMIN na Central
de Dados, com snapshot, validacao de concorrencia e auditoria propria.

## Recuperacao

Se o frontend falhar, republicar o commit anterior mantendo os novos dados e
auditoria; nao remover tabelas de controle nem reativar itens automaticamente.
Se houver falha durante a aplicacao transacional, executar rollback e interromper
a publicacao. Restauracao integral exige manutencao e autorizacao separada.
O backup nao inclui os corpos de objetos do Storage nem constitui ensaio de
restauracao. Evidencias operacionais e dumps permanecem fora do repositorio.
