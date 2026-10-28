# Liberar meu IP: banco de produção e Swagger

O banco de produção e as docs da API (Swagger) só aceitam os IPs do time. Seu IP muda quando você troca de rede (casa, escritório, celular) e às vezes sozinho, porque a operadora troca. Este script libera o seu IP atual e apaga o antigo.

**Rode sempre que** o banco não conectar ou o Swagger der erro 403.

| Seu computador | Arquivo |
|---|---|
| Windows | `atualiza_ip.ps1` |
| macOS | `atualiza_ip.sh` |
| Linux | `atualiza_ip.sh` |

---

## Primeira vez (uns 10 minutos)

### 1. Baixe o repositório

Com git: `git clone https://github.com/sempejunior/aws-scripts.git`

Sem git: no GitHub, **Code → Download ZIP**, e descompacte.

### 2. Pegue sua chave da AWS

1. Entre no console da AWS com o seu usuário.
2. No canto superior direito, clique no seu nome → **Security credentials**.
3. Em **Access keys**, clique em **Create access key** → **Command Line Interface (CLI)** → marque a confirmação → **Create**.
4. Copie o **Access key** e o **Secret access key**. O segredo só aparece nessa tela.

### 3. Peça os valores do time

Peça para quem administra a AWS os valores de `SECURITY_GROUP_ID`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` e `CLOUDFLARE_LIST_ID`. São iguais para todo o time e chegam por um gerenciador de senhas, nunca por WhatsApp ou e-mail.

### 4. Crie o arquivo `.env`

Abra o terminal **na pasta `Change_IP_Security_Group`**:

- **Windows:** abra a pasta no Explorador de Arquivos, clique na barra de endereço, digite `powershell` e aperte Enter.
- **macOS:** no Finder, clique com o botão direito na pasta → **Serviços → Novo Terminal na Pasta**. Se a opção não aparecer, abra o Terminal, digite `cd ` (com espaço), arraste a pasta para a janela e aperte Enter.
- **Linux:** clique com o botão direito dentro da pasta → **Abrir no terminal**.

Copie o modelo e abra para editar:

| Sistema | Comandos |
|---|---|
| Windows | `Copy-Item .envExample .env` e depois `notepad .env` |
| macOS | `cp .envExample .env` e depois `open -e .env` |
| Linux | `cp .envExample .env` e depois `nano .env` (salvar: Ctrl+O, Enter, Ctrl+X) |

O macOS e o Linux escondem arquivos que começam com ponto. Por isso use o terminal, e não o Finder ou o gerenciador de arquivos.

Preencha depois do `=`, sem espaços e sem aspas:

```
AWS_ACCESS_KEY_ID=<sua chave do passo 2>
AWS_SECRET_ACCESS_KEY=<seu segredo do passo 2>
AWS_REGION=us-east-1
SECURITY_GROUP_ID=<valor do time>
PORT=5432
name=<seu nome e máquina, ex.: Maria-Notebook>
CLOUDFLARE_API_TOKEN=<valor do time>
CLOUDFLARE_ACCOUNT_ID=<valor do time>
CLOUDFLARE_LIST_ID=<valor do time>
```

**O `name` precisa ser diferente em cada computador.** O script apaga os IPs antigos que têm o mesmo `name`. Se o notebook e o desktop usarem o mesmo, um tira o acesso do outro. Use `Maria-Notebook`, `Maria-Mac` e assim por diante: só letras, números, `.`, `-` e `_`, sem espaço.

O `.env` guarda a sua chave da AWS. Nunca envie esse arquivo para ninguém nem faça commit dele.

---

## Rodar

Sempre na pasta `Change_IP_Security_Group`:

| Sistema | Comando |
|---|---|
| Windows | `powershell -ExecutionPolicy Bypass -File .\atualiza_ip.ps1` |
| macOS | `bash atualiza_ip.sh` |
| Linux | `bash atualiza_ip.sh` |

Na primeira vez, se o AWS CLI não estiver instalado, o script instala sozinho:
- **macOS e Linux:** ele pede a senha do seu computador. Ao digitar, nada aparece na tela; é normal.
- **Windows:** abra o PowerShell como Administrador **só nessa primeira vez** (menu Iniciar → digite `PowerShell` → botão direito → Executar como administrador). Depois de instalar, feche e abra o PowerShell de novo.

### Deu certo quando aparece algo assim

```
IP público: IPv4=189.6.x.x IPv6=nenhum
Maria-Notebook+Ipv4: liberando 189.6.x.x/32...
Maria-Notebook+Ipv4: IP antigo 177.10.x.x/32 será removido.
Maria-Notebook+Ipv4: IPs antigos removidos.
Maria-Notebook+Ipv6: esta rede não tem Ipv6.
Swagger: liberado para 8 IP(s) do time.
Pronto.
```

`IPv6=nenhum` é normal em muitas redes. Rodar de novo sem trocar de rede não muda nada: o script responde "já está liberado".

---

## Problemas comuns

| Mensagem ou sintoma | O que fazer |
|---|---|
| `Arquivo .env não encontrado` | O `.env` precisa estar na mesma pasta do script. Refaça o passo 4. |
| `Faltam variáveis no .env: ...` | Preencha o campo citado. Confira se não ficou espaço antes do `=`. |
| `O 'name' do .env só pode ter...` | Tire espaços e acentos do `name`. |
| `Não consegui descobrir seu IP público` | Sem internet, ou uma VPN/proxy está bloqueando. Tente de novo. |
| `AuthFailure`, `InvalidClientTokenId` ou `SignatureDoesNotMatch` | Chave da AWS errada ou desativada. Refaça o passo 2 e cole de novo. |
| `UnauthorizedOperation` | Seu usuário da AWS não tem permissão. Fale com quem administra a AWS. |
| `Cloudflare recusou a leitura da lista` | `CLOUDFLARE_*` errado no `.env`. Peça os valores de novo. |
| `ATENÇÃO: faltam CLOUDFLARE_...` | O banco foi liberado, mas o Swagger não. Preencha os três `CLOUDFLARE_*`. |
| `Cloudflare ocupado... tentando de novo` | Outra pessoa rodou ao mesmo tempo. O script tenta sozinho; não precisa fazer nada. |
| Windows: `a execução de scripts foi desabilitada` | Use o comando completo com `-ExecutionPolicy Bypass` da seção Rodar. |
| Windows: `aws não é reconhecido` logo após instalar | Feche e abra o PowerShell, e rode de novo. |
| macOS: o `git clone` pede para instalar "ferramentas de linha de comando" | Aceite e espere terminar, ou baixe o ZIP (passo 1). |
| Linux: `unzip: command not found` ao instalar o AWS CLI | `sudo apt install unzip` (ou o equivalente da sua distribuição) e rode de novo. |
| macOS/Linux: `$'\r': command not found` | O `.sh` foi salvo com quebra de linha do Windows. Baixe de novo do GitHub, sem editar no Windows. |
| Swagger dá 403 mesmo depois de rodar | Uma VPN ligada muda o seu IP. Desligue, ou rode com ela ligada, se for usar assim. |

---

## O que o script faz, por dentro

1. Descobre o seu IP público (IPv4 e, se a rede tiver, IPv6).
2. No Security Group do banco, libera esse IP com a descrição `<name>+Ipv4` / `<name>+Ipv6`.
3. Apaga as regras antigas com essa descrição (maiúsculas e minúsculas não importam). Regras de outras pessoas e de outras portas não são tocadas.
4. Copia para a lista `innovanote_team` do Cloudflare todos os IPs individuais liberados no banco. **Quem acessa o banco acessa o Swagger.** Quem sai do banco perde o Swagger na próxima execução de qualquer pessoa do time.

### Como o Swagger é protegido

A API passa pelo Cloudflare antes de chegar à AWS, então a AWS só enxerga IPs do Cloudflare e não consegue filtrar por pessoa. Quem filtra é uma regra de WAF do Cloudflare (plano gratuito): ela bloqueia os caminhos de docs das APIs quando o IP não está na lista `innovanote_team`. O resto do tráfego passa normalmente.

### Configuração única no Cloudflare (só quem administra)

1. **Lista:** Manage Account → Configurations → Lists → Create new list. Nome `innovanote_team`, tipo IP. O ID está no fim da URL da lista.
2. **Token:** My Profile → API Tokens → Create Custom Token, com a permissão **Account → Account Filter Lists → Edit**, só na conta do InnovaNote. Se vazar, o máximo que dá para fazer é editar essa lista.
3. **Preencher a lista:** rode este script uma vez.
4. **Regra:** no domínio → Security → Security rules → Custom rules, com ação **Block**. Ela cobre os domínios da API e do app. A expressão exata fica com quem administra o Cloudflare, fora deste repositório público.

**Para desfazer:** desligue a regra no painel e as docs voltam a abrir na hora.

### Permissões AWS necessárias

`ec2:DescribeSecurityGroupRules`, `ec2:AuthorizeSecurityGroupIngress` e `ec2:RevokeSecurityGroupIngress` no Security Group do banco.
