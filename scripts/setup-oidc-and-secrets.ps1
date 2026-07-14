#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GITHUB_ORG = 'clashi5050'
$GITHUB_REPO = 'star-squad-bundle'
$APP_NAME = "gha-oidc-$GITHUB_REPO-static-web-app"
$GH_ENVIRONMENT = 'dev'
$ROLE = 'Contributor'

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
    throw "Required command 'az' was not found. Install Azure CLI and retry."
}
$env:Path = "$(Split-Path $azPath -Parent);$env:Path"

$ghPath = Resolve-CommandPath -Name 'gh'
$GH_AVAILABLE = $false
if ($ghPath) {
    $GH_AVAILABLE = $true
    $env:Path = "$(Split-Path $ghPath -Parent);$env:Path"
} else {
    Write-Warning "GitHub CLI ('gh') was not found. The script will continue using the GitHub REST API if a token is available."
}

Write-Host '>> Using subscription:'
$SUBSCRIPTION_ID = az account show --query id -o tsv
$TENANT_ID = az account show --query tenantId -o tsv
Write-Host "   subscription: $SUBSCRIPTION_ID"
Write-Host "   tenant:       $TENANT_ID"

Write-Host " >> Creating (or reusing) app registration '$APP_NAME'..."
$CLIENT_ID = az ad app list --display-name $APP_NAME --query '[0].appId' -o tsv
if ([string]::IsNullOrWhiteSpace($CLIENT_ID)) {
    $CLIENT_ID = az ad app create --display-name $APP_NAME --query appId -o tsv
    Write-Host "   created app: $CLIENT_ID"
} else {
    Write-Host "   reusing app: $CLIENT_ID"
}

Write-Host '>> Ensuring service principal exists...'
$spExists = az ad sp show --id $CLIENT_ID 2>$null
if (-not $spExists) {
    az ad sp create --id $CLIENT_ID | Out-Null
    Write-Host '   service principal created'
} else {
    Write-Host '   service principal already exists'
}

Write-Host " >> Assigning '$ROLE' at subscription scope..."
az role assignment create --assignee $CLIENT_ID --role $ROLE --scope "/subscriptions/$SUBSCRIPTION_ID" 2>$null | Out-Null

Write-Host '>> Creating federated credentials...'
function New-FederatedCredential {
    param([string]$Name, [string]$Subject)

    $existing = az ad app federated-credential list --id $CLIENT_ID --query "[?name=='$Name'].name" -o tsv
    if ([string]::IsNullOrWhiteSpace($existing)) {
        $tempJson = Join-Path $env:TEMP "fic-$Name.json"
        try {
            @"
{
  "name": "$Name",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$Subject",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ | Set-Content -Path $tempJson -Encoding utf8
            az ad app federated-credential create --id $CLIENT_ID --parameters "@$tempJson" | Out-Null
            Write-Host "   created fic '$Name' -> $Subject"
        } finally {
            if (Test-Path $tempJson) {
                Remove-Item $tempJson -Force
            }
        }
    } else {
        Write-Host "   fic '$Name' already exists"
    }
}

New-FederatedCredential -Name "gha-env-$GH_ENVIRONMENT" -Subject "repo:$GITHUB_ORG/$GITHUB_REPO:environment:$GH_ENVIRONMENT"
New-FederatedCredential -Name 'gha-branch-dev' -Subject "repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/dev"

Write-Host " >> Setting GitHub environment vars on $GITHUB_ORG/$GITHUB_REPO ($GH_ENVIRONMENT)..."
$REPO = "$GITHUB_ORG/$GITHUB_REPO"

if ($GH_AVAILABLE) {
    gh api -X PUT "repos/$REPO/environments/$GH_ENVIRONMENT" 2>$null | Out-Null
    gh variable set ARM_CLIENT_ID --env $GH_ENVIRONMENT --repo $REPO --body $CLIENT_ID | Out-Null
    gh variable set ARM_TENANT_ID --env $GH_ENVIRONMENT --repo $REPO --body $TENANT_ID | Out-Null
    gh variable set ARM_SUBSCRIPTION_ID --env $GH_ENVIRONMENT --repo $REPO --body $SUBSCRIPTION_ID | Out-Null
} else {
    Write-Warning "GitHub CLI is not available, so GitHub variables were not updated automatically."
    Write-Host "Please set the following variables manually in the GitHub UI for environment '$GH_ENVIRONMENT':"
    Write-Host '  - ARM_CLIENT_ID'
    Write-Host '  - ARM_TENANT_ID'
    Write-Host '  - ARM_SUBSCRIPTION_ID'
}

Write-Host ''
Write-Host '>> Done. Still TODO by hand:'
Write-Host '   - GH_PAT: a fine-grained PAT with read access to your private iac-modules'
Write-Host "       gh secret set GH_PAT --env $GH_ENVIRONMENT --repo $REPO --body '<pat>'"
Write-Host '   - AZURE_STATIC_WEB_APPS_API_TOKEN: set AFTER the first Terraform apply'
Write-Host '       (see set-swa-token.sh)'
