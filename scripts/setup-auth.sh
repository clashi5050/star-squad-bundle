#!/usr/bin/env bash
# =============================================================================
# setup-auth.sh
# -----------------------------------------------------------------------------
# One-time bootstrap for Star Squad ACCOUNTS (email sign-in) on Azure Static
# Web Apps, using Microsoft Entra External ID (customer identity / CIAM) as the
# custom OpenID Connect provider referenced in apps/star-squad/staticwebapp.config.json.
#
# This script does the parts that are cleanly scriptable:
#   1. Registers an app in your External ID tenant for the Static Web App.
#   2. Adds the SWA callback redirect URI.
#   3. Creates a client secret.
#   4. Writes AAD_CLIENT_ID / AAD_CLIENT_SECRET into the SWA app settings
#      (the names staticwebapp.config.json expects).
#   5. Prints the wellKnownOpenIdConfiguration URL to paste into that config.
#
# PREREQUISITES (portal, one time — not scriptable today):
#   - An Entra External ID tenant exists, and you have created a sign-up/sign-in
#     user flow that allows Email + password. See:
#     https://learn.microsoft.com/en-us/entra/external-id/customers/
#   - `az login --tenant <external-id-tenant>` targeting THAT tenant.
#   - Custom auth requires the SWA Standard plan (Terraform sets swa_sku=Standard).
#
# Requires: az CLI + gh CLI, both authenticated.
# =============================================================================
set -euo pipefail

# ------------------------------- CONFIG --------------------------------------
GITHUB_ORG="clashi5050"
GITHUB_REPO="iac-patterns"
GH_ENVIRONMENT="sndx"

# The External ID tenant subdomain (the part before .ciamlogin.com / .onmicrosoft.com).
EXTERNAL_ID_TENANT="cjsazurelab"                 # External ID tenant subdomain (single source of truth)

# Must match the provider key in staticwebapp.config.json (customOpenIdConnectProviders).
PROVIDER_NAME="entraExternalId"

# App registration display name + the SWA to configure.
APP_NAME="starsquad-swa-auth"
SWA_NAME="swa-use2-starsquad-swa-sndx-use2"   # from main.tf naming: swa-<company_loc>-<app>-<type>-<environment>-<short_loc>
SWA_RG="rg-use2-starsquad-swa-sndx-use2"      # rg-<same>
# -----------------------------------------------------------------------------

ISSUER_BASE="https://${EXTERNAL_ID_TENANT}.ciamlogin.com/${EXTERNAL_ID_TENANT}.onmicrosoft.com/v2.0"
WELLKNOWN="${ISSUER_BASE}/.well-known/openid-configuration"

echo ">> Resolving Static Web App hostname..."
SWA_HOST="$(az staticwebapp show --name "${SWA_NAME}" --resource-group "${SWA_RG}" --query 'defaultHostname' -o tsv)"
REDIRECT_URI="https://${SWA_HOST}/.auth/login/${PROVIDER_NAME}/callback"
echo "   host:     ${SWA_HOST}"
echo "   redirect: ${REDIRECT_URI}"

echo ">> Creating (or reusing) app registration '${APP_NAME}'..."
CLIENT_ID="$(az ad app list --display-name "${APP_NAME}" --query '[0].appId' -o tsv)"
if [[ -z "${CLIENT_ID}" ]]; then
  CLIENT_ID="$(az ad app create --display-name "${APP_NAME}" \
    --web-redirect-uris "${REDIRECT_URI}" \
    --enable-id-token-issuance true \
    --query appId -o tsv)"
  echo "   created app: ${CLIENT_ID}"
else
  echo "   reusing app: ${CLIENT_ID}"
  az ad app update --id "${CLIENT_ID}" --web-redirect-uris "${REDIRECT_URI}" --enable-id-token-issuance true
fi

echo ">> Creating client secret..."
CLIENT_SECRET="$(az ad app credential reset --id "${CLIENT_ID}" --display-name "swa-oidc" --query password -o tsv)"

echo ">> Writing AAD_CLIENT_ID / AAD_CLIENT_SECRET into SWA app settings..."
az staticwebapp appsettings set --name "${SWA_NAME}" --resource-group "${SWA_RG}" \
  --setting-names "AAD_CLIENT_ID=${CLIENT_ID}" "AAD_CLIENT_SECRET=${CLIENT_SECRET}" >/dev/null
echo "   set."

echo ">> Patching staticwebapp.config.json wellKnownOpenIdConfiguration from EXTERNAL_ID_TENANT..."
CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../apps/star-squad/staticwebapp.config.json"
if [[ -f "${CONFIG}" ]]; then
  python3 - "${CONFIG}" "${WELLKNOWN}" <<'PYEOF'
import json,sys
p,url=sys.argv[1],sys.argv[2]
c=json.load(open(p))
c["auth"]["identityProviders"]["customOpenIdConnectProviders"]["entraExternalId"]["registration"]["openIdConnectConfiguration"]["wellKnownOpenIdConfiguration"]=url
json.dump(c,open(p,"w"),indent=2); open(p,"a").write("\n")
print("   patched", p)
PYEOF
else
  echo "   (config not found at ${CONFIG}; set wellKnownOpenIdConfiguration manually)"
fi

echo
echo ">> Done."
echo "   staticwebapp.config.json now points at:"
echo "     ${WELLKNOWN}"
echo "   Commit apps/star-squad/staticwebapp.config.json so the deploy workflow"
echo "   republishes the auth config."
