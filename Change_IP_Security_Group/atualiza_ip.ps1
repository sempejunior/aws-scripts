$IPV4_PATTERN = '^(\d{1,3}\.){3}\d{1,3}$'
$IPV6_PATTERN = '^[0-9a-fA-F:]+$'
$NAME_PATTERN = '^[A-Za-z0-9_.-]+$'
$PORT_PATTERN = '^\d+$'
$MAX_RETRIES = 5
$CLOUDFLARE_API_URL = 'https://api.cloudflare.com/client/v4'

function Invoke-Aws {
    param ([string[]]$Arguments)
    $output = & aws @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw $output
    }
    return $output
}

function Invoke-AwsJson {
    param ([string[]]$Arguments)
    return Invoke-Aws ($Arguments + @('--output', 'json')) | ConvertFrom-Json
}

function Load-Env {
    $envFile = Join-Path $PSScriptRoot ".env"
    if (-not (Test-Path $envFile)) {
        Write-Host "Arquivo .env não encontrado em $PSScriptRoot. Copie o .envExample para .env e preencha."
        exit 1
    }
    Write-Host "Carregando o .env de $PSScriptRoot..."
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=\s][^=]*?)\s*=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim())
        }
    }
}

function Test-Env {
    $missing = @('AWS_REGION', 'SECURITY_GROUP_ID', 'PORT', 'name') | Where-Object { -not [Environment]::GetEnvironmentVariable($_) }
    if ($missing) {
        Write-Host "Faltam variáveis no .env: $($missing -join ', ')"
        exit 1
    }
    if ($env:name -notmatch $NAME_PATTERN) {
        Write-Host "O 'name' do .env só pode ter letras, números, ponto, hífen e sublinhado (sem espaço)."
        exit 1
    }
    if ($env:PORT -notmatch $PORT_PATTERN) {
        Write-Host "A PORT do .env precisa ser um número."
        exit 1
    }
}

function Install-AwsCLI {
    Write-Host "Verificando se o AWS CLI está instalado..."
    if (Get-Command "aws" -ErrorAction SilentlyContinue) {
        Write-Host "AWS CLI já está instalado."
        return
    }
    Write-Host "AWS CLI não encontrado. Instalando..."
    $installerPath = Join-Path $env:TEMP "AWSCLIV2.msi"
    Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $installerPath -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i", "`"$installerPath`"", "/quiet", "/norestart" -Wait
    Remove-Item $installerPath
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command "aws" -ErrorAction SilentlyContinue)) {
        Write-Host "Falha ao instalar o AWS CLI. Instale manualmente e rode de novo."
        exit 1
    }
    Write-Host "AWS CLI instalado com sucesso!"
}

function Test-AwsCredentials {
    Write-Host "Verificando as credenciais da AWS..."
    & aws sts get-caller-identity 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Credenciais AWS válidas."
        return
    }
    Write-Host "As credenciais da AWS não estão configuradas. Configurando agora..."
    aws configure
}

function Get-PublicIp {
    param ([string]$Url, [string]$Pattern)
    try {
        $ip = (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10).Content.Trim()
    } catch {
        return ""
    }
    if ($ip -match $Pattern) {
        return $ip
    }
    return ""
}

function Get-PortRules {
    param ([string]$CidrKey)
    $rules = Invoke-AwsJson @('ec2', 'describe-security-group-rules', '--filters', "Name=group-id,Values=$env:SECURITY_GROUP_ID")
    return @($rules.SecurityGroupRules | Where-Object {
        -not $_.IsEgress -and $_.IpProtocol -eq 'tcp' -and
        "$($_.FromPort)" -eq $env:PORT -and "$($_.ToPort)" -eq $env:PORT -and $_.$CidrKey
    })
}

function Sync-SecurityGroupRule {
    param (
        [string]$Label,
        [string]$Ip,
        [int]$Prefix,
        [string]$CidrKey,
        [string]$RangeKey,
        [string]$CidrParam
    )
    $description = "$env:name+$Label"
    $wantedCidr = if ($Ip) { "$Ip/$Prefix" } else { "" }

    $rules = Get-PortRules -CidrKey $CidrKey
    $cidrAlreadyAllowed = [bool]($rules | Where-Object { $_.$CidrKey -eq $wantedCidr })
    $staleRules = @($rules | Where-Object { $_.$CidrKey -ne $wantedCidr -and $_.Description -ieq $description })
    foreach ($rule in $staleRules) {
        Write-Host "${description}: IP antigo $($rule.$CidrKey) será removido."
    }

    if (-not $wantedCidr) {
        Write-Host "${description}: esta rede não tem $Label."
    } elseif ($cidrAlreadyAllowed) {
        Write-Host "${description}: $wantedCidr já está liberado."
    } else {
        Write-Host "${description}: liberando $wantedCidr..."
        Invoke-Aws @('ec2', 'authorize-security-group-ingress', '--group-id', $env:SECURITY_GROUP_ID,
            '--ip-permissions', "IpProtocol=tcp,FromPort=$env:PORT,ToPort=$env:PORT,$RangeKey=[{$CidrParam=$wantedCidr,Description=$description}]") | Out-Null
    }

    if ($staleRules.Count -gt 0) {
        Invoke-Aws (@('ec2', 'revoke-security-group-ingress', '--group-id', $env:SECURITY_GROUP_ID, '--security-group-rule-ids') + @($staleRules | ForEach-Object { $_.SecurityGroupRuleId })) | Out-Null
        Write-Host "${description}: IPs antigos removidos."
    }
}

function Get-TeamListItems {
    $items = @(Get-PortRules -CidrKey 'CidrIpv4' | Where-Object { $_.CidrIpv4 -like '*/32' } |
        ForEach-Object { [pscustomobject]@{ ip = $_.CidrIpv4 -replace '/32$', ''; comment = "$($_.Description)" } })
    $items += @(Get-PortRules -CidrKey 'CidrIpv6' | Where-Object { $_.CidrIpv6 -like '*/128' } |
        ForEach-Object { [pscustomobject]@{ ip = $_.CidrIpv6 -replace '/128$', ''; comment = "$($_.Description)" } })
    return @($items | Sort-Object ip -Unique)
}

function Invoke-Cloudflare {
    param ([string]$Method, [string]$Path, [string]$Body)
    $request = @{
        Method          = $Method
        Uri             = "$CLOUDFLARE_API_URL/accounts/$env:CLOUDFLARE_ACCOUNT_ID/rules/lists$Path"
        Headers         = @{ Authorization = "Bearer $env:CLOUDFLARE_API_TOKEN" }
        ContentType     = 'application/json'
        TimeoutSec      = 30
        UseBasicParsing = $true
    }
    if ($Body) {
        $request.Body = [Text.Encoding]::UTF8.GetBytes($Body)
    }
    try {
        return Invoke-RestMethod @request
    } catch {
        $detail = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        return [pscustomobject]@{ success = $false; errors = $detail }
    }
}

function Wait-BulkOperation {
    param ([string]$OperationId)
    for ($attempt = 1; $attempt -le $MAX_RETRIES; $attempt++) {
        $status = (Invoke-Cloudflare -Method 'GET' -Path "/bulk_operations/$OperationId").result.status
        if ($status -eq 'completed') { return $true }
        if ($status -eq 'failed') { return $false }
        Start-Sleep -Seconds $attempt
    }
    return $false
}

function Sync-CloudflareList {
    if (-not $env:CLOUDFLARE_API_TOKEN -or -not $env:CLOUDFLARE_ACCOUNT_ID -or -not $env:CLOUDFLARE_LIST_ID) {
        Write-Host "ATENÇÃO: faltam CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID ou CLOUDFLARE_LIST_ID no .env. Só o banco foi atualizado; o Swagger continua com a lista antiga."
        return
    }

    $items = @(Get-TeamListItems)
    $desired = @($items | ForEach-Object { $_.ip })

    $response = Invoke-Cloudflare -Method 'GET' -Path "/$env:CLOUDFLARE_LIST_ID/items?per_page=500"
    if (-not $response.success) {
        Write-Host "Cloudflare recusou a leitura da lista: $($response.errors | ConvertTo-Json -Compress)"
        exit 1
    }
    $current = @($response.result | ForEach-Object { $_.ip -replace '/(32|128)$', '' } | Where-Object { $_ } | Sort-Object -Unique)
    if (($current -join ' ') -eq ($desired -join ' ')) {
        Write-Host "Swagger: lista do Cloudflare já está atualizada."
        return
    }

    $body = ConvertTo-Json -InputObject @($items) -Compress
    for ($attempt = 1; $attempt -le $MAX_RETRIES; $attempt++) {
        $response = Invoke-Cloudflare -Method 'PUT' -Path "/$env:CLOUDFLARE_LIST_ID/items" -Body $body
        if ($response.success) {
            if (Wait-BulkOperation -OperationId $response.result.operation_id) {
                Write-Host "Swagger: liberado para $($desired.Count) IP(s) do time."
                return
            }
            Write-Host "Swagger: o Cloudflare não confirmou a atualização. Rode o script de novo."
            exit 1
        }
        Write-Host "Swagger: Cloudflare ocupado com outra atualização, tentando de novo..."
        Start-Sleep -Seconds ($attempt + 1)
    }
    Write-Host "Cloudflare recusou a atualização da lista: $($response.errors | ConvertTo-Json -Compress)"
    exit 1
}

function Main {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Load-Env
    Test-Env
    Install-AwsCLI
    Test-AwsCredentials

    $ipv4 = Get-PublicIp -Url "https://ipv4.icanhazip.com" -Pattern $IPV4_PATTERN
    $ipv6 = Get-PublicIp -Url "https://ipv6.icanhazip.com" -Pattern $IPV6_PATTERN
    if (-not $ipv4 -and -not $ipv6) {
        Write-Host "Não consegui descobrir seu IP público. Confira a internet e rode de novo."
        exit 1
    }
    Write-Host "IP público: IPv4=$(if ($ipv4) { $ipv4 } else { 'nenhum' }) IPv6=$(if ($ipv6) { $ipv6 } else { 'nenhum' })"

    try {
        Sync-SecurityGroupRule -Label 'Ipv4' -Ip $ipv4 -Prefix 32 -CidrKey 'CidrIpv4' -RangeKey 'IpRanges' -CidrParam 'CidrIp'
        Sync-SecurityGroupRule -Label 'Ipv6' -Ip $ipv6 -Prefix 128 -CidrKey 'CidrIpv6' -RangeKey 'Ipv6Ranges' -CidrParam 'CidrIpv6'
        Sync-CloudflareList
    } catch {
        Write-Host "Erro da AWS: $_"
        exit 1
    }
    Write-Host "Pronto."
}

Main
