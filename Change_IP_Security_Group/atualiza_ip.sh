#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IPV4_PATTERN='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
IPV6_PATTERN='^[0-9a-fA-F:]+$'
NAME_PATTERN='^[A-Za-z0-9_.-]+$'
PORT_PATTERN='^[0-9]+$'
MAX_RETRIES=5
CLOUDFLARE_API_URL='https://api.cloudflare.com/client/v4'

function load_env {
    local env_file="$SCRIPT_DIR/.env"
    if [ ! -f "$env_file" ]; then
        echo "Arquivo .env não encontrado em $SCRIPT_DIR. Copie o .envExample para .env e preencha."
        exit 1
    fi
    echo "Carregando o .env de $SCRIPT_DIR..."
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in
            '' | '#'*) continue ;;
            *=*) export "${line%%=*}=${line#*=}" ;;
        esac
    done < "$env_file"
}

function validate_env {
    local missing=""
    local var
    for var in AWS_REGION SECURITY_GROUP_ID PORT name; do
        if [ -z "${!var:-}" ]; then
            missing="$missing $var"
        fi
    done
    if [ -n "$missing" ]; then
        echo "Faltam variáveis no .env:$missing"
        exit 1
    fi
    if [[ ! "$name" =~ $NAME_PATTERN ]]; then
        echo "O 'name' do .env só pode ter letras, números, ponto, hífen e sublinhado (sem espaço)."
        exit 1
    fi
    if [[ ! "$PORT" =~ $PORT_PATTERN ]]; then
        echo "A PORT do .env precisa ser um número."
        exit 1
    fi
}

function install_aws_cli {
    echo "Verificando se o AWS CLI está instalado..."
    if command -v aws &> /dev/null; then
        echo "AWS CLI já está instalado."
        return
    fi
    echo "AWS CLI não encontrado. Instalando..."
    local work_dir
    work_dir="$(mktemp -d)"
    if [ "$(uname -s)" = "Darwin" ]; then
        curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "$work_dir/AWSCLIV2.pkg"
        sudo installer -pkg "$work_dir/AWSCLIV2.pkg" -target /
    else
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$work_dir/awscliv2.zip"
        unzip -q "$work_dir/awscliv2.zip" -d "$work_dir"
        sudo "$work_dir/aws/install"
    fi
    rm -rf "$work_dir"
}

function check_aws_credentials {
    echo "Verificando as credenciais da AWS..."
    if aws sts get-caller-identity &> /dev/null; then
        echo "Credenciais AWS válidas."
    else
        echo "As credenciais da AWS não estão configuradas. Configurando agora..."
        aws configure
    fi
}

function lower {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

function fetch_public_ip {
    local version="$1"
    local pattern="$2"
    local ip
    ip="$(curl "-$version" -fsS --max-time 10 "https://ipv$version.icanhazip.com" 2> /dev/null | tr -d '[:space:]' || true)"
    if [[ "$ip" =~ $pattern ]]; then
        printf '%s' "$ip"
    fi
}

function list_port_rules {
    local cidr_key="$1"
    aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=$SECURITY_GROUP_ID" \
        --query "SecurityGroupRules[?IsEgress==\`false\` && IpProtocol=='tcp' && FromPort==\`$PORT\` && ToPort==\`$PORT\` && $cidr_key!=null].[SecurityGroupRuleId,$cidr_key,Description]" \
        --output text
}

function sync_security_group_rule {
    local label="$1"
    local ip="$2"
    local prefix="$3"
    local cidr_key="$4"
    local range_key="$5"
    local cidr_param="$6"
    local description="${name}+${label}"
    local wanted_cidr=""
    if [ -n "$ip" ]; then
        wanted_cidr="$ip/$prefix"
    fi

    local rules
    rules="$(list_port_rules "$cidr_key")"

    local stale_rule_ids=()
    local cidr_already_allowed=false
    local rule_id cidr rule_description
    while IFS=$'\t' read -r rule_id cidr rule_description; do
        [ -z "$rule_id" ] && continue
        if [ "$cidr" = "$wanted_cidr" ]; then
            cidr_already_allowed=true
        elif [ "$(lower "$rule_description")" = "$(lower "$description")" ]; then
            stale_rule_ids+=("$rule_id")
            echo "$description: IP antigo $cidr será removido."
        fi
    done <<< "$rules"

    if [ -z "$wanted_cidr" ]; then
        echo "$description: esta rede não tem $label."
    elif [ "$cidr_already_allowed" = true ]; then
        echo "$description: $wanted_cidr já está liberado."
    else
        echo "$description: liberando $wanted_cidr..."
        aws ec2 authorize-security-group-ingress \
            --group-id "$SECURITY_GROUP_ID" \
            --ip-permissions "IpProtocol=tcp,FromPort=$PORT,ToPort=$PORT,$range_key=[{$cidr_param=$wanted_cidr,Description=$description}]" \
            > /dev/null
    fi

    if [ "${#stale_rule_ids[@]}" -gt 0 ]; then
        aws ec2 revoke-security-group-ingress --group-id "$SECURITY_GROUP_ID" --security-group-rule-ids "${stale_rule_ids[@]}" > /dev/null
        echo "$description: IPs antigos removidos."
    fi
}

function team_list_items {
    {
        list_port_rules CidrIpv4 | awk -F'\t' '$2 ~ /\/32$/'
        list_port_rules CidrIpv6 | awk -F'\t' '$2 ~ /\/128$/'
    } | awk -F'\t' '{ sub(/\/(32|128)$/, "", $2); if (!seen[$2]++) print $2 "\t" $3 }' | sort
}

function cloudflare_api {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    local args=(-sS --max-time 30 -X "$method" -H "Content-Type: application/json")
    if [ -n "$body" ]; then
        args+=(--data "$body")
    fi
    printf 'header = "Authorization: Bearer %s"\n' "$CLOUDFLARE_API_TOKEN" \
        | curl --config - "${args[@]}" "$CLOUDFLARE_API_URL/accounts/$CLOUDFLARE_ACCOUNT_ID/rules/lists$path"
}

function json_field {
    grep -oE "\"$1\": ?\"[^\"]*\"" | sed -E 's/.*"([^"]*)"$/\1/'
}

function is_success {
    grep -qE '"success": ?true'
}

function wait_bulk_operation {
    local operation_id="$1"
    local attempt=1
    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        local status
        status="$(cloudflare_api GET "/bulk_operations/$operation_id" | json_field status | head -1)"
        case "$status" in
            completed) return 0 ;;
            failed) return 1 ;;
        esac
        sleep "$attempt"
        attempt=$((attempt + 1))
    done
    return 1
}

function sync_cloudflare_list {
    if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] || [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ] || [ -z "${CLOUDFLARE_LIST_ID:-}" ]; then
        echo "ATENÇÃO: faltam CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID ou CLOUDFLARE_LIST_ID no .env. Só o banco foi atualizado; o Swagger continua com a lista antiga."
        return
    fi

    local items desired current response
    items="$(team_list_items)"
    desired="$(printf '%s\n' "$items" | cut -f1 | grep -v '^$' | sort -u || true)"

    response="$(cloudflare_api GET "/$CLOUDFLARE_LIST_ID/items?per_page=500")"
    if ! printf '%s' "$response" | is_success; then
        echo "Cloudflare recusou a leitura da lista: $response"
        exit 1
    fi
    current="$(printf '%s' "$response" | json_field ip | sed -E 's#/(32|128)$##' | sort -u || true)"

    if [ "$current" = "$desired" ]; then
        echo "Swagger: lista do Cloudflare já está atualizada."
        return
    fi

    local body="[" separator="" ip comment
    while IFS=$'\t' read -r ip comment; do
        [ -z "$ip" ] && continue
        comment="$(printf '%s' "$comment" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
        body="$body$separator{\"ip\":\"$ip\",\"comment\":\"$comment\"}"
        separator=","
    done <<< "$items"
    body="$body]"

    local attempt=1
    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        response="$(cloudflare_api PUT "/$CLOUDFLARE_LIST_ID/items" "$body")"
        if printf '%s' "$response" | is_success; then
            if wait_bulk_operation "$(printf '%s' "$response" | json_field operation_id | head -1)"; then
                echo "Swagger: liberado para $(printf '%s' "$desired" | grep -c . || true) IP(s) do time."
                return
            fi
            echo "Swagger: o Cloudflare não confirmou a atualização. Rode o script de novo."
            exit 1
        fi
        echo "Swagger: Cloudflare ocupado com outra atualização, tentando de novo..."
        attempt=$((attempt + 1))
        sleep "$attempt"
    done
    echo "Cloudflare recusou a atualização da lista: $response"
    exit 1
}

function main {
    load_env
    validate_env
    install_aws_cli
    check_aws_credentials

    local ipv4 ipv6
    ipv4="$(fetch_public_ip 4 "$IPV4_PATTERN")"
    ipv6="$(fetch_public_ip 6 "$IPV6_PATTERN")"
    if [ -z "$ipv4" ] && [ -z "$ipv6" ]; then
        echo "Não consegui descobrir seu IP público. Confira a internet e rode de novo."
        exit 1
    fi
    echo "IP público: IPv4=${ipv4:-nenhum} IPv6=${ipv6:-nenhum}"

    sync_security_group_rule "Ipv4" "$ipv4" 32 CidrIpv4 IpRanges CidrIp
    sync_security_group_rule "Ipv6" "$ipv6" 128 CidrIpv6 Ipv6Ranges CidrIpv6
    sync_cloudflare_list
    echo "Pronto."
}

main
