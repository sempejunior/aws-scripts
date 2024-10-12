#!/bin/bash

# Obtenha o diretório onde o script está localizado
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Função para carregar o arquivo .env
function load_env {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        echo "Carregando o arquivo .env do diretório $SCRIPT_DIR..."
        export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
    else
        echo "Arquivo .env não encontrado no diretório $SCRIPT_DIR! Certifique-se de que está na mesma pasta que o script."
        exit 1
    fi
}

# Função para instalar o AWS CLI automaticamente se não estiver instalado
function install_aws_cli {
    echo "Verificando se o AWS CLI está instalado..."
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI não encontrado. Instalando o AWS CLI..."

        # Baixa o instalador do AWS CLI v2
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install

        # Limpa arquivos de instalação
        rm -rf awscliv2.zip aws/
    else
        echo "AWS CLI já está instalado."
    fi
}

# Função para verificar se as credenciais da AWS estão configuradas
function check_aws_credentials {
    echo "Verificando se as credenciais da AWS estão configuradas..."
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "As credenciais da AWS não estão configuradas. Configurando agora..."
        aws configure
    else
        echo "Credenciais AWS encontradas e válidas."
    fi
}

# Função para verificar se o IP já existe com base no 'name'
function check_existing_ip {
    local name=$1
    local ip_version=$2

    echo "Verificando IP existente para $name..."

    if [ "$ip_version" == "IPv4" ]; then
        EXISTING_IP=$(aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP_ID" --query "SecurityGroups[0].IpPermissions[?IpRanges[?Description=='$name']].IpRanges[0].CidrIp" --output text)
    else
        EXISTING_IP=$(aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP_ID" --query "SecurityGroups[0].IpPermissions[?Ipv6Ranges[?Description=='$name']].Ipv6Ranges[0].CidrIpv6" --output text)
    fi

    echo "IP encontrado: $EXISTING_IP"
}

# Função para remover regras antigas associadas ao nome
function remove_old_rules {
    local name=$1
    local ip_version=$2

    echo "Removendo regras antigas associadas ao nome $name..."

    if [ "$ip_version" == "IPv4" ]; then
        aws ec2 revoke-security-group-ingress --group-id "$SECURITY_GROUP_ID" --ip-permissions "IpProtocol=tcp,FromPort=$PORT,ToPort=$PORT,IpRanges=[{Description=\"$name\"}]" > /dev/null 2>&1
    else
        aws ec2 revoke-security-group-ingress --group-id "$SECURITY_GROUP_ID" --ip-permissions "IpProtocol=tcp,FromPort=$PORT,ToPort=$PORT,Ipv6Ranges=[{Description=\"$name\"}]" > /dev/null 2>&1
    fi
}

# Função principal para atualizar o IP no Security Group
function update_security_group_ip {
    # Obtém o IP público atual (IPv4 e IPv6)
    IPV4=$(curl -s https://ipv4.icanhazip.com)
    IPV6=$(curl -s https://ipv6.icanhazip.com)

    # Verifica se o IPv4 foi obtido
    if [[ -z "$IPV4" ]]; then
        echo "Nenhum endereço IPv4 encontrado."
        exit 1
    fi

    # Verifica se o IPv6 foi obtido
    if [[ -z "$IPV6" ]]; then
        echo "Nenhum endereço IPv6 encontrado."
        exit 1
    fi

    # Define o nome da regra a partir da variável `name` do arquivo .env
    NAME_IPV4="${name}+Ipv4"
    NAME_IPV6="${name}+Ipv6"
    echo "NAME_IPV4 = $NAME_IPV4, NAME_IPV6 = $NAME_IPV6"

    # Verifica os IPs atuais no Security Group para IPv4 e IPv6
    check_existing_ip "$NAME_IPV4" "IPv4"
    if [[ "$EXISTING_IP" != "$IPV4/32" ]]; then
        echo "O IP IPv4 mudou, removendo o antigo e adicionando o novo..."
        remove_old_rules "$NAME_IPV4" "IPv4"
        aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --ip-permissions IpProtocol=tcp,FromPort="$PORT",ToPort="$PORT",IpRanges="[{CidrIp=$IPV4/32,Description=\"$NAME_IPV4\"}]" > /dev/null 2>&1
        echo "IPv4 atualizado com sucesso!"
    else
        echo "O IP IPv4 é o mesmo, nenhuma alteração necessária."
    fi

    check_existing_ip "$NAME_IPV6" "IPv6"
    if [[ "$EXISTING_IP" != "$IPV6/128" ]]; then
        echo "O IP IPv6 mudou, removendo o antigo e adicionando o novo..."
        remove_old_rules "$NAME_IPV6" "IPv6"
        aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --ip-permissions IpProtocol=tcp,FromPort="$PORT",ToPort="$PORT",Ipv6Ranges="[{CidrIpv6=$IPV6/128,Description=\"$NAME_IPV6\"}]" > /dev/null 2>&1
        echo "IPv6 atualizado com sucesso!"
    else
        echo "O IP IPv6 é o mesmo, nenhuma alteração necessária."
    fi
}

# Função para validar a instalação e as credenciais AWS, carregar o .env, e atualizar o IP
function main {
    load_env
    install_aws_cli
    check_aws_credentials
    update_security_group_ip
}

# Inicia o processo
main
