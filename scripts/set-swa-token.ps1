#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GITHUB_ORG = 'clashi5050'
$GITHUB_REPO = 'star-squad-bundle'
$GH_ENVIRONMENT = 'dev'

$AZURE_SUBSCRIPTION_ID = '119e0880-44c4-463f-84ab-185efffe44a9'

$COMPANY_LOC = 'use2'
$APP = 'starsquad'
$TYPE = 'swa'
$ENVIRONMENT = 'dev'
$SHORT_LOC = 'use2'

$NAME_PREFIX = "$COMPANY_LOC-$APP-$TYPE-$ENVIRONMENT-$SHORT_LOC"
$RG = "rg-$NAME_PREFIX"
$SWA = "swa-$NAME_PREFIX"
$REPO = "$GITHUB_ORG/$GITHUB_REPO"

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

Write-Host ">> Setting active subscription to $AZURE_SUBSCRIPTION_ID..."
az account set --subscription $AZURE_SUBSCRIPTION_ID

Write-Host ">> Fetching deployment token for $SWA (rg: $RG)..."
$token = az staticwebapp secrets list --name $SWA --resource-group $RG --query 'properties.apiKey' -o tsv 2>$null

if ([string]::IsNullOrWhiteSpace($token)) {
    throw "No token returned. Check that the Static Web App exists and the naming matches the Terraform configuration."
}

Write-Host ">> Storing AZURE_STATIC_WEB_APPS_API_TOKEN on $REPO ($GH_ENVIRONMENT)..."
gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --env $GH_ENVIRONMENT --repo $REPO --body $token | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "gh secret set failed (exit code $LASTEXITCODE). Run 'gh auth login' and retry."
}

Write-Host '>> Done. Push a change under apps/star-squad/ (or run the deploy workflow manually) and the app will publish to the SWA''s default hostname:'
$hostname = az staticwebapp show --name $SWA --resource-group $RG --query 'defaultHostname' -o tsv
Write-Host "   https://$hostname"
