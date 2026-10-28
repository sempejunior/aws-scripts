# aws-scripts

Scripts do dia a dia do time InnovaNote na AWS. Cada script funciona no **Windows** (PowerShell), no **macOS** e no **Linux** (bash), e não precisa instalar nada antes: se faltar o AWS CLI, o próprio script instala.

## Scripts

| Script | Para que serve | Guia |
|---|---|---|
| Liberar meu IP | Liberar o seu IP atual no banco de produção e no Swagger, apagando o IP antigo | [Change_IP_Security_Group](./Change_IP_Security_Group/readme.md) |

## Como rodar qualquer script

Abra o terminal na pasta do script (cada guia explica como) e rode:

| Sistema | Comando |
|---|---|
| Windows | `powershell -ExecutionPolicy Bypass -File .\nome_do_script.ps1` |
| macOS e Linux | `bash nome_do_script.sh` |

Cada script lê a configuração de um arquivo `.env` na mesma pasta. Copie o `.envExample` para `.env` e preencha. O `.env` tem chaves de acesso: está no `.gitignore` e nunca deve ser enviado a ninguém.

## Este repositório é público

Nada que identifique a infraestrutura vai para cá: chaves, IDs de recursos, IPs ou regras de firewall. Esses valores ficam no `.env` de cada pessoa e são passados por um gerenciador de senhas.

## Contribuir

Um script novo precisa:
- ter as duas versões, `.ps1` e `.sh`, com o mesmo comportamento;
- vir com um `.envExample` sem valores reais;
- ter um `readme.md` na própria pasta, com o passo a passo para quem não é técnico;
- ganhar uma linha na tabela acima.

O `.sh` precisa rodar no bash 3.2, que é o padrão do macOS: nada de `declare -A`, `mapfile` ou `${var,,}`.
