# Função para carregar o arquivo .env
function Load-Env {
    $envFile = ".env"
    if (Test-Path $envFile) {
        Write-Host "Carregando o arquivo .env..."
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^\s*([^#]+?)=(.+)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                [Environment]::SetEnvironmentVariable($key, $value)
            }
        }
    } else {
        Write-Host "Arquivo .env não encontrado! Certifique-se de que está na mesma pasta que o script."
        exit 1
    }
}

# Função para instalar o AWS CLI automaticamente se não estiver instalado
function Install-AwsCLI {
    Write-Host "Verificando se AWS CLI está instalado..."
    if (!(Get-Command "aws" -ErrorAction SilentlyContinue)) {
        Write-Host "AWS CLI não encontrado. Iniciando instalação..."

        $installerPath = "$env:TEMP\AWSCLIV2.msi"
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $installerPath

        Start-Process msiexec.exe -ArgumentList "/i", "`"$installerPath`"", "/quiet", "/norestart" -Wait
        Remove-Item $installerPath

        if (Get-Command "aws" -ErrorAction SilentlyContinue) {
            Write-Host "AWS CLI instalado com sucesso!"
        } else {
            Write-Host "Falha ao instalar o AWS CLI. Por favor, instale manualmente."
            Exit
        }
    } else {
        Write-Host "AWS CLI já está instalado."
    }
}

# Função para verificar se as credenciais da AWS estão configuradas
function Check-AwsCredentials {
    Write-Host "Verificando se as credenciais da AWS estão configuradas..."
    try {
        aws sts get-caller-identity | Out-Null
        Write-Host "Credenciais AWS encontradas e válidas."
    } catch {
        Write-Host "As credenciais da AWS não estão configuradas ou são inválidas."
        Write-Host "Iniciando configuração do AWS CLI..."
        aws configure
    }
}

# Função para verificar se o IP já existe com base no 'name'
function Check-ExistingIP {
    param (
        [string]$name,
        [string]$ipVersion
    )

    Write-Host "Verificando IP existente para $name..."

    if ($ipVersion -eq "IPv4") {
        $existingIP = aws ec2 describe-security-groups --group-ids $env:SECURITY_GROUP_ID --query "SecurityGroups[0].IpPermissions[?IpRanges[?Description=='$name']].IpRanges[0].CidrIp" --output text
    } else {
        $existingIP = aws ec2 describe-security-groups --group-ids $env:SECURITY_GROUP_ID --query "SecurityGroups[0].IpPermissions[?Ipv6Ranges[?Description=='$name']].Ipv6Ranges[0].CidrIpv6" --output text
    }

    Write-Host "IP encontrado: $existingIP"
    return $existingIP
}

# Função para remover regras antigas associadas ao nome
function Remove-OldRules {
    param (
        [string]$name,
        [string]$ipVersion
    )

    Write-Host "Removendo regras antigas associadas ao nome $name..."

    if ($ipVersion -eq "IPv4") {
        aws ec2 revoke-security-group-ingress --group-id $env:SECURITY_GROUP_ID --ip-permissions "IpProtocol=tcp,FromPort=$env:PORT,ToPort=$env:PORT,IpRanges=[{Description='$name'}]" > $null 2>&1
    } else {
        aws ec2 revoke-security-group-ingress --group-id $env:SECURITY_GROUP_ID --ip-permissions "IpProtocol=tcp,FromPort=$env:PORT,ToPort=$env:PORT,Ipv6Ranges=[{Description='$name'}]" > $null 2>&1
    }
}

# Função principal para atualizar o IP no Security Group
function Update-SecurityGroupIP {
    # Obtém o IP público atual (IPv4 e IPv6)
    $IPV4 = (Invoke-WebRequest -Uri "https://ipv4.icanhazip.com").Content.Trim()
    $IPV6 = (Invoke-WebRequest -Uri "https://ipv6.icanhazip.com").Content.Trim()

    # Verifica se o IPv4 foi obtido
    if (-not $IPV4) {
        Write-Host "Nenhum endereço IPv4 encontrado."
        exit 1
    }

    # Verifica se o IPv6 foi obtido
    if (-not $IPV6) {
        Write-Host "Nenhum endereço IPv6 encontrado."
        exit 1
    }

    # Define os nomes das regras usando a variável `name` do arquivo .env
    $NAME_IPV4 = "$env:name`+`Ipv4"
    $NAME_IPV6 = "$env:name`+`Ipv6"
    Write-Host "NAME_IPV4 = $NAME_IPV4, NAME_IPV6 = $NAME_IPV6"

    # Verifica os IPs atuais no Security Group para IPv4 e IPv6
    $existingIPv4 = Check-ExistingIP -name $NAME_IPV4 -ipVersion "IPv4"
    if ($existingIPv4 -ne "$IPV4/32") {
        Write-Host "O IP IPv4 mudou, removendo o antigo e adicionando o novo..."
        Remove-OldRules -name $NAME_IPV4 -ipVersion "IPv4"
        aws ec2 authorize-security-group-ingress --group-id $env:SECURITY_GROUP_ID --ip-permissions "IpProtocol=tcp,FromPort=$env:PORT,ToPort=$env:PORT,IpRanges=[{CidrIp='$IPV4/32',Description='$NAME_IPV4'}]" > $null 2>&1
        Write-Host "IPv4 atualizado com sucesso!"
    } else {
        Write-Host "O IP IPv4 é o mesmo, nenhuma alteração necessária."
    }

    $existingIPv6 = Check-ExistingIP -name $NAME_IPV6 -ipVersion "IPv6"
    if ($existingIPv6 -ne "$IPV6/128") {
        Write-Host "O IP IPv6 mudou, removendo o antigo e adicionando o novo..."
        Remove-OldRules -name $NAME_IPV6 -ipVersion "IPv6"
        aws ec2 authorize-security-group-ingress --group-id $env:SECURITY_GROUP_ID --ip-permissions "IpProtocol=tcp,FromPort=$env:PORT,ToPort=$env:PORT,Ipv6Ranges=[{CidrIpv6='$IPV6/128',Description='$NAME_IPV6'}]" > $null 2>&1
        Write-Host "IPv6 atualizado com sucesso!"
    } else {
        Write-Host "O IP IPv6 é o mesmo, nenhuma alteração necessária."
    }
}

# Função para validar a instalação e as credenciais AWS, carregar o .env, e atualizar o IP
function Main {
    Load-Env
    Install-AwsCLI
    Check-AwsCredentials
    Update-SecurityGroupIP
}

# Inicia o processo
Main
