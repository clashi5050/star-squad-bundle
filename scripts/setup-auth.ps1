#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GITHUB_ORG = 'clashi5050'
$GITHUB_REPO = 'star-squad-bundle'
$GH_ENVIRONMENT = 'dev'

$EXTERNAL_ID_TENANT = 'cjsazurelab'
$EXTERNAL_ID_TENANT_ID = '7417fa64-1b0e-47b6-a709-0b9623ae176d'
$HOME_TENANT_ID = 'cf0764be-ac77-42a9-878b-4182009c30ea'
$PROVIDER_NAME = 'entraExternalId'
$APP_NAME = 'starsquad-swa-auth'
$SWA_NAME = 'swa-use2-starsquad-swa-dev-use2'
$SWA_RG = 'rg-use2-starsquad-swa-dev-use2'

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$HOST_FILE = Join-Path $SCRIPT_DIR '.setup-auth-host'
$CREDS_FILE = Join-Path $SCRIPT_DIR '.setup-auth-creds'

function Resolve-CommandPath {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidates = @()
    switch ($Name) {
        'az' {
            $candidates += @(
                "$env:ProgramFiles(x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
                "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
                "$env:ProgramFiles\Azure CLI\az.cmd"
            )
        }
        'gh' {
            $candidates += @(
                "$env:ProgramFiles\GitHub CLI\gh.exe",
                "$env:ProgramFiles(x86)\GitHub CLI\gh.exe",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GitHub.cli_Microsoft.Winget.Source_8wekyb3d8bbwe\bin\gh.exe",
                "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
            )
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

$azPath = Resolve-CommandPath -Name 'az'
if (-not $azPath) {
    throw "Azure CLI ('az') was not found. Install it and retry."
}
$env:Path = "$(Split-Path $azPath -Parent);$env:Path"

$ghPath = Resolve-CommandPath -Name 'gh'
if (-not $ghPath) {
    throw "GitHub CLI ('gh') was not found. Install it and retry."
}
$env:Path = "$(Split-Path $ghPath -Parent);$env:Path"

$CURRENT_TENANT = az account show --query tenantId -o tsv
$ISSUER_BASE = "https://$EXTERNAL_ID_TENANT.ciamlogin.com/$EXTERNAL_ID_TENANT.onmicrosoft.com/v2.0"
$WELLKNOWN = "$ISSUER_BASE/.well-known/openid-configuration"

if ($CURRENT_TENANT -eq $HOME_TENANT_ID -and -not (Test-Path $HOST_FILE)) {
    Write-Host '>> [1/3] Home tenant, no cached hostname yet — resolving SWA hostname...'
    $SWA_HOST = az staticwebapp show --name $SWA_NAME --resource-group $SWA_RG --query 'defaultHostname' -o tsv
    "SWA_HOST=$SWA_HOST" | Set-Content -Path $HOST_FILE -Encoding utf8
    Write-Host "   host: $SWA_HOST"
    Write-Host ''
    Write-Host "Next: az login --tenant $EXTERNAL_ID_TENANT_ID   (then re-run this script)"
    return
}

if ($CURRENT_TENANT -eq $EXTERNAL_ID_TENANT_ID) {
    if (-not (Test-Path $HOST_FILE)) {
        throw "${HOST_FILE} not found. Run this script under the home tenant login first."
    }

    $hostContent = Get-Content $HOST_FILE -Raw
    $SWA_HOST = ($hostContent -split '=')[1].Trim()
    $REDIRECT_URI = "https://$SWA_HOST/.auth/login/$PROVIDER_NAME/callback"
    Write-Host ">> [2/3] CIAM tenant — registering app '$APP_NAME'..."
    Write-Host "   redirect: $REDIRECT_URI"

    $CLIENT_ID = az ad app list --display-name $APP_NAME --query '[0].appId' -o tsv
    if ([string]::IsNullOrWhiteSpace($CLIENT_ID)) {
        $CLIENT_ID = az ad app create --display-name $APP_NAME --web-redirect-uris $REDIRECT_URI --enable-id-token-issuance true --query appId -o tsv
        Write-Host "   created app: $CLIENT_ID"
    } else {
        Write-Host "   reusing app: $CLIENT_ID"
        az ad app update --id $CLIENT_ID --web-redirect-uris $REDIRECT_URI --enable-id-token-issuance true | Out-Null
    }

    Write-Host '>> Creating client secret...'
    $CLIENT_SECRET = az ad app credential reset --id $CLIENT_ID --display-name 'swa-oidc' --query password -o tsv
    "CLIENT_ID='$CLIENT_ID'`nCLIENT_SECRET='$CLIENT_SECRET'" | Set-Content -Path $CREDS_FILE -Encoding utf8
    Write-Host ''
    Write-Host "Next: az login --tenant $HOME_TENANT_ID   (then re-run this script)"
    return
}

if ($CURRENT_TENANT -eq $HOME_TENANT_ID -and (Test-Path $HOST_FILE)) {
    if (-not (Test-Path $CREDS_FILE)) {
        throw "${CREDS_FILE} not found. Run this script under the CIAM tenant login first."
    }

    $credsContent = Get-Content $CREDS_FILE -Raw
    $CLIENT_ID = ($credsContent -split "'" | Select-Object -Index 1)
    $CLIENT_SECRET = ($credsContent -split "'" | Select-Object -Index 3)

    Write-Host '>> [3/3] Home tenant — writing AAD_CLIENT_ID / AAD_CLIENT_SECRET into SWA app settings...'
    az staticwebapp appsettings set --name $SWA_NAME --resource-group $SWA_RG --setting-names "AAD_CLIENT_ID=$CLIENT_ID" "AAD_CLIENT_SECRET=$CLIENT_SECRET" | Out-Null
    Write-Host '   set.'

    Write-Host '>> Patching staticwebapp.config.json wellKnownOpenIdConfiguration from EXTERNAL_ID_TENANT...'
    $CONFIG = Join-Path $SCRIPT_DIR '..\apps\star-squad\staticwebapp.config.json'
    if (Test-Path $CONFIG) {
        $json = Get-Content $CONFIG -Raw | ConvertFrom-Json
        $json.auth.identityProviders.customOpenIdConnectProviders.entraExternalId.registration.openIdConnectConfiguration.wellKnownOpenIdConfiguration = $WELLKNOWN
        $json | ConvertTo-Json -Depth 20 | Set-Content -Path $CONFIG -Encoding utf8
        Write-Host "   patched $CONFIG"
    } else {
        Write-Host "   (config not found at $CONFIG; set wellKnownOpenIdConfiguration manually)"
    }

    Remove-Item $HOST_FILE -Force -ErrorAction SilentlyContinue
    Remove-Item $CREDS_FILE -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host "Done. staticwebapp.config.json now points at: $WELLKNOWN"
    return
}

throw "Logged into an unrecognized tenant ($CURRENT_TENANT)."
