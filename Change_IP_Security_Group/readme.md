# Atualizador de IP no Security Group da AWS

Este repositório contém scripts que automatizam o processo de atualização do seu IP no **Security Group** da AWS. Isso é útil quando você precisa garantir que seu IP atual tenha permissão para acessar recursos na AWS, como bancos de dados RDS, mas seu IP muda frequentemente.

### Compatibilidade
- **Windows**: Script em PowerShell.
- **Linux**: Script em Bash.

## Funcionalidades
- Instala automaticamente o **AWS CLI** se ele não estiver instalado.
- Verifica se as credenciais da AWS estão configuradas, orientando o usuário se necessário.
- Obtém o IP público da máquina e atualiza automaticamente o **Security Group** na AWS com esse IP.
- Remove regras anteriores para a porta específica, garantindo que apenas o novo IP tenha acesso.
- Suporte para **IPv4** e **IPv6**.
- Usa o nome definido no arquivo `.env` para definir regras exclusivas no Security Group.


---

## **Pré-requisitos**

Antes de usar o script, você precisa de:

1. **Conta AWS** com permissões para alterar Security Groups.
2. **ID do Security Group** onde você deseja adicionar seu IP.
3. **AWS CLI** instalado (caso não tenha, o script cuida disso).
4. **Credenciais de Acesso da AWS** (Access Key e Secret Key) configuradas.

## **Configuração do Arquivo `.env`**

O script utiliza um arquivo `.env` para armazenar informações sensíveis e variáveis de configuração. O arquivo `.env` deve ser configurado da seguinte forma:

```bash
# .env
name=SeuNomeAqui            # Nome que será utilizado para descrever as regras no Security Group (ex: Carlos)
SECURITY_GROUP_ID=sg-0123456789abcdef0  # ID do Security Group da AWS
PORT=5432                   # Porta utilizada no Security Group (exemplo: PostgreSQL usa a porta 5432)
AWS_ACCESS_KEY_ID=blabla
AWS_SECRET_ACCESS_KEY=bleble
AWS_REGION=us-east-1
```
---

## **Como Usar (Windows)**

1. **Obtenha suas credenciais da AWS:**
    - Acesse o [Painel IAM](https://console.aws.amazon.com/iam/home) da AWS.
    - Crie um novo usuário ou selecione um existente.
    - Gere **Access Key ID** e **Secret Access Key** para acesso programático.
    - **Anote essas chaves**, pois você precisará delas ao rodar o script.
    

2. **Edite o Script para Usar o ID do Seu Security Group:**
    - Abra o arquivo `atualiza_ip_windows.ps1` no editor de texto de sua escolha.
    - Crie o env conforme mencionado anteriormente.

3. **Execute o Script no PowerShell:**
    - Abra o PowerShell como **Administrador**.
    - Navegue até o diretório onde o script está localizado.
    - Crie o env conforme mencionado anteriormente.
    - Execute o comando:
    ```powershell
    .\atualiza_ip_windows.ps1
    ```

4. **O que o Script Faz:**
    - Instala o AWS CLI (se não estiver instalado).
    - Configura suas credenciais da AWS se ainda não estiverem configuradas.
    - Obtém seu IP público (ipv4 e ipv6) e atualiza o Security Group na AWS.

---

## **Como Usar (Linux)**

1. **Obtenha suas credenciais da AWS:**
    - Acesse o [Painel IAM](https://console.aws.amazon.com/iam/home) da AWS.
    - Crie um novo usuário ou selecione um existente.
    - Gere **Access Key ID** e **Secret Access Key** para acesso programático.
    - **Anote essas chaves**, pois você precisará delas ao rodar o script.

2. **Edite o Script para Usar o ID do Seu Security Group:**
    - Abra o arquivo `atualiza_ip_linux.sh` no editor de texto de sua escolha.
    - Altere a linha que contém o ID do Security Group:
   

3. **Execute o Script no Terminal:**
    - Abra o terminal.
    - Navegue até o diretório onde o script está localizado.
    - Crie o env conforme mencionado anteriormente.
    - Torne o script executável (se necessário):
    ```bash
    chmod +x atualiza_ip_rds_linux.sh
    ```
    - Execute o script:
    ```bash
    ./atualiza_ip_linux.sh
    ```

4. **O que o Script Faz:**
    - Instala o AWS CLI (se não estiver instalado).
    - Configura suas credenciais da AWS se ainda não estiverem configuradas.
    - Obtém seu IP público (ipv4 e ipv6) e atualiza o Security Group na AWS.

---

## **Obtenção de Credenciais AWS**

Se você ainda não tem as credenciais da AWS configuradas, siga estas etapas:

1. Acesse o [Painel IAM da AWS](https://console.aws.amazon.com/iam/home).
2. Crie um novo usuário com permissões para modificar **Security Groups**.
3. No momento da criação, marque a opção "Acesso Programático".
4. Após a criação, vá até a aba "Credenciais de Segurança" do usuário e gere uma **Access Key** e uma **Secret Key**.
5. Configure suas credenciais no AWS CLI (caso já não estejam configuradas):
    ```bash
    aws configure
    ```