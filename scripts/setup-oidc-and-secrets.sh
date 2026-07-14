#!/usr/bin/env bash
# =============================================================================
# setup-oidc-and-secrets.sh
# -----------------------------------------------------------------------------
# One-time bootstrap for the Star Squad Static Web App pattern.
# Creates an Azure AD app registration + service principal, wires up OIDC
# federated credentials for GitHub Actions (NO client secrets), grants it
# Contributor on the subscription, and sets all required GitHub secrets/vars.
#
# Requires: az CLI (logged in: `az login`), gh CLI (logged in: `gh auth login`),
#           and permission to create app registrations + assign roles.
#
# Idempotent-ish: re-running will reuse the app if APP_NAME already exists.
# Review every value in the CONFIG block before running.
# =============================================================================
set -euo pipefail

# ------------------------------- CONFIG --------------------------------------
GITHUB_ORG="clashi5050"
GITHUB_REPO="iac-patterns"
APP_NAME="gha-oidc-${GITHUB_REPO}-static-web-app"

# GitHub environment these credentials are scoped to (matches workflow input).
GH_ENVIRONMENT="main"

# Remote-state backend (must already exist). Matches vars.TFSTATE_* in the repo.
TFSTATE_RG="rg-tfstate"
TFSTATE_SA="sttfstateexample"   # <-- set to your real state storage account

# Role + scope for the SP. Contributor at subscription scope is typical for
# these patterns; tighten to a resource group if your governance requires it.
ROLE="Contributor"
# -----------------------------------------------------------------------------

echo ">> Using subscription:"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
echo "   subscription: ${SUBSCRIPTION_ID}"
echo "   tenant:       ${TENANT_ID}"

# --- 1. App registration ------------------------------------------------------
echo ">> Creating (or reusing) app registration '${APP_NAME}'..."
CLIENT_ID="$(az ad app list --display-name "${APP_NAME}" --query '[0].appId' -o tsv)"
if [[ -z "${CLIENT_ID}" ]]; then
  CLIENT_ID="$(az ad app create --display-name "${APP_NAME}" --query appId -o tsv)"
  echo "   created app: ${CLIENT_ID}"
else
  echo "   reusing app: ${CLIENT_ID}"
fi

# --- 2. Service principal -----------------------------------------------------
echo ">> Ensuring service principal exists..."
if ! az ad sp show --id "${CLIENT_ID}" >/dev/null 2>&1; then
  az ad sp create --id "${CLIENT_ID}" >/dev/null
  echo "   service principal created"
else
  echo "   service principal already exists"
fi

# --- 3. Role assignment -------------------------------------------------------
echo ">> Assigning '${ROLE}' at subscription scope..."
az role assignment create \
  --assignee "${CLIENT_ID}" \
  --role "${ROLE}" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}" \
  >/dev/null 2>&1 || echo "   (role assignment already present)"

# --- 4. OIDC federated credentials -------------------------------------------
# One credential per GitHub "subject". We add:
#   - the environment subject (used by workflow_dispatch with environment: sndx)
#   - the dev-branch subject (used by the push-triggered deploy workflow)
echo ">> Creating federated credentials..."

create_fic () {
  local name="$1" subject="$2"
  local existing
  existing="$(az ad app federated-credential list --id "${CLIENT_ID}" \
    --query "[?name=='${name}'].name" -o tsv)"
  if [[ -n "${existing}" ]]; then
    echo "   fic '${name}' already exists"
    return
  fi
  az ad app federated-credential create --id "${CLIENT_ID}" --parameters "{
    \"name\": \"${name}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${subject}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" >/dev/null
  echo "   created fic '${name}' -> ${subject}"
}

create_fic "gha-env-${GH_ENVIRONMENT}" \
  "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${GH_ENVIRONMENT}"
create_fic "gha-branch-dev" \
  "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/dev"

# --- 5. GitHub vars (+ secrets) ------------------------------------------------
# Set at the ENVIRONMENT level so they line up with the workflow's
# `environment: ${{ github.event.inputs.environment }}`.
# ARM_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID are *variables*, not secrets: under
# OIDC there's no shared credential behind them, so they're safe to expose in
# a public repo (they grant nothing without a matching federated-credential
# subject on the Azure AD app).
echo ">> Setting GitHub environment vars on ${GITHUB_ORG}/${GITHUB_REPO} (${GH_ENVIRONMENT})..."
REPO="${GITHUB_ORG}/${GITHUB_REPO}"

# Ensure the environment exists (gh has no direct create; the API call is safe).
gh api -X PUT "repos/${REPO}/environments/${GH_ENVIRONMENT}" >/dev/null 2>&1 || true

gh variable set ARM_CLIENT_ID       --env "${GH_ENVIRONMENT}" --repo "${REPO}" --body "${CLIENT_ID}"
gh variable set ARM_TENANT_ID       --env "${GH_ENVIRONMENT}" --repo "${REPO}" --body "${TENANT_ID}"
gh variable set ARM_SUBSCRIPTION_ID --env "${GH_ENVIRONMENT}" --repo "${REPO}" --body "${SUBSCRIPTION_ID}"

# Non-secret backend coordinates as environment variables.
gh variable set TFSTATE_SA --env "${GH_ENVIRONMENT}" --repo "${REPO}" --body "${TFSTATE_SA}"
gh variable set TFSTATE_RG --env "${GH_ENVIRONMENT}" --repo "${REPO}" --body "${TFSTATE_RG}"

echo
echo ">> Done. Still TODO by hand (require values that only exist later):"
echo "   - GH_PAT: a fine-grained PAT with read access to your private iac-modules"
echo "       gh secret set GH_PAT --env ${GH_ENVIRONMENT} --repo ${REPO} --body '<pat>'"
echo "   - AZURE_STATIC_WEB_APPS_API_TOKEN: set AFTER the first Terraform apply"
echo "       (see set-swa-token.sh)"
