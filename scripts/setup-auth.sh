#!/usr/bin/env bash
# =============================================================================
# setup-auth.sh
# -----------------------------------------------------------------------------
# One-time bootstrap for Star Squad ACCOUNTS (email sign-in) on Azure Static
# Web Apps, using Microsoft Entra External ID (customer identity / CIAM) as the
# custom OpenID Connect provider referenced in apps/star-squad/staticwebapp.config.json.
#
# This script does the parts that are cleanly scriptable:
#   1. Resolves the SWA hostname (needs the home/subscription tenant).
#   2. Registers an app in the External ID tenant + adds the callback redirect
#      URI + creates a client secret (needs the CIAM tenant).
#   3. Writes AAD_CLIENT_ID / AAD_CLIENT_SECRET into the SWA app settings and
#      patches wellKnownOpenIdConfiguration in staticwebapp.config.json (back
#      in the home tenant).
#
# PREREQUISITES (portal, one time — not scriptable today):
#   - An Entra External ID tenant exists, and you have created a sign-up/sign-in
#     user flow that allows Email + password. See:
#     https://learn.microsoft.com/en-us/entra/external-id/customers/
#   - Custom auth requires the SWA Standard plan (Terraform sets swa_sku=Standard).
#
# TWO SEPARATE ENTRA TENANTS ARE INVOLVED, so this runs in three passes,
# switching tenants with `az login --tenant <id>` (interactive, your own
# terminal) between them. Just re-run this same script after each switch —
# it detects which tenant you're on and does the right thing:
#   1. az login --tenant cf0764be-ac77-42a9-878b-4182009c30ea   (home)
#      ./setup-auth.sh   -> resolves + caches the SWA hostname
#   2. az login --tenant 7417fa64-1b0e-47b6-a709-0b9623ae176d   (CIAM)
#      ./setup-auth.sh   -> registers the app, creates the client secret
#   3. az login --tenant cf0764be-ac77-42a9-878b-4182009c30ea   (home)
#      ./setup-auth.sh   -> writes SWA app settings, patches the config
#
# Requires: az CLI + gh CLI, both authenticated.
# =============================================================================
set -euo pipefail

# ------------------------------- CONFIG --------------------------------------
GITHUB_ORG="clashi5050"
GITHUB_REPO="star-squad-bundle"
GH_ENVIRONMENT="dev"

# The External ID tenant subdomain (the part before .ciamlogin.com / .onmicrosoft.com)
# and its resolved tenant ID (a genuinely separate Entra tenant from HOME_TENANT_ID).
# If you rotate tenants, re-resolve with:
#   curl https://<tenant>.ciamlogin.com/<tenant>.onmicrosoft.com/v2.0/.well-known/openid-configuration | jq -r .issuer
EXTERNAL_ID_TENANT="cjsazurelab"
EXTERNAL_ID_TENANT_ID="7417fa64-1b0e-47b6-a709-0b9623ae176d"

# The tenant that owns the subscription/Static Web App (where you're logged in
# for everything else in this repo, e.g. setup-oidc-and-secrets.sh).
HOME_TENANT_ID="cf0764be-ac77-42a9-878b-4182009c30ea"

# Must match the provider key in staticwebapp.config.json (customOpenIdConnectProviders).
PROVIDER_NAME="entraExternalId"

# App registration display name + the SWA to configure.
APP_NAME="starsquad-swa-auth"
SWA_NAME="swa-use2-starsquad-swa-dev-use2"   # from main.tf naming: swa-<company_loc>-<app>-<type>-<environment>-<short_loc>
SWA_RG="rg-use2-starsquad-swa-dev-use2"      # rg-<same>

# Cross-pass handoff files (gitignored; never commit these — HOST_FILE is
# harmless but CREDS_FILE holds a live client secret).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_FILE="${SCRIPT_DIR}/.setup-auth-host"
CREDS_FILE="${SCRIPT_DIR}/.setup-auth-creds"
# -----------------------------------------------------------------------------

ISSUER_BASE="https://${EXTERNAL_ID_TENANT}.ciamlogin.com/${EXTERNAL_ID_TENANT}.onmicrosoft.com/v2.0"
WELLKNOWN="${ISSUER_BASE}/.well-known/openid-configuration"

CURRENT_TENANT="$(az account show --query tenantId -o tsv)"

if [[ "${CURRENT_TENANT}" == "${HOME_TENANT_ID}" && ! -f "${HOST_FILE}" ]]; then
  # --- Step 1: resolve the SWA hostname (needs subscription access) ---------
  echo ">> [1/3] Home tenant, no cached hostname yet — resolving SWA hostname..."
  SWA_HOST="$(az staticwebapp show --name "${SWA_NAME}" --resource-group "${SWA_RG}" --query 'defaultHostname' -o tsv)"
  echo "SWA_HOST=${SWA_HOST}" > "${HOST_FILE}"
  echo "   host: ${SWA_HOST}"
  echo
  echo ">> Next: az login --tenant ${EXTERNAL_ID_TENANT_ID}   (then re-run this script)"

elif [[ "${CURRENT_TENANT}" == "${EXTERNAL_ID_TENANT_ID}" ]]; then
  # --- Step 2: app registration + secret (needs the CIAM tenant) ------------
  if [[ ! -f "${HOST_FILE}" ]]; then
    echo "!! ${HOST_FILE} not found. Run this script under the home tenant login" >&2
    echo "   first (az login --tenant ${HOME_TENANT_ID}) to resolve the SWA hostname." >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${HOST_FILE}"
  REDIRECT_URI="https://${SWA_HOST}/.auth/login/${PROVIDER_NAME}/callback"
  echo ">> [2/3] CIAM tenant — registering app '${APP_NAME}'..."
  echo "   redirect: ${REDIRECT_URI}"

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

  {
    echo "CLIENT_ID='${CLIENT_ID}'"
    echo "CLIENT_SECRET='${CLIENT_SECRET}'"
  } > "${CREDS_FILE}"
  chmod 600 "${CREDS_FILE}"
  echo
  echo ">> Next: az login --tenant ${HOME_TENANT_ID}   (then re-run this script)"

elif [[ "${CURRENT_TENANT}" == "${HOME_TENANT_ID}" && -f "${HOST_FILE}" ]]; then
  # --- Step 3: write SWA app settings + patch config (back in home tenant) --
  if [[ ! -f "${CREDS_FILE}" ]]; then
    echo "!! ${CREDS_FILE} not found. Run this script under the CIAM tenant login" >&2
    echo "   first (az login --tenant ${EXTERNAL_ID_TENANT_ID}) to register the app." >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${CREDS_FILE}"
  echo ">> [3/3] Home tenant — writing AAD_CLIENT_ID / AAD_CLIENT_SECRET into SWA app settings..."
  az staticwebapp appsettings set --name "${SWA_NAME}" --resource-group "${SWA_RG}" \
    --setting-names "AAD_CLIENT_ID=${CLIENT_ID}" "AAD_CLIENT_SECRET=${CLIENT_SECRET}" >/dev/null
  echo "   set."

  echo ">> Patching staticwebapp.config.json wellKnownOpenIdConfiguration from EXTERNAL_ID_TENANT..."
  CONFIG="${SCRIPT_DIR}/../apps/star-squad/staticwebapp.config.json"
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

  rm -f "${HOST_FILE}" "${CREDS_FILE}"
  echo
  echo ">> Done. staticwebapp.config.json now points at: ${WELLKNOWN}"
  echo "   Commit apps/star-squad/staticwebapp.config.json (if changed) so the"
  echo "   deploy workflow republishes the auth config, then push"
  echo "   apps/star-squad/** to redeploy — sign-in should work after that."

else
  echo "!! Logged into an unrecognized tenant (${CURRENT_TENANT})." >&2
  echo "   Run: az login --tenant ${HOME_TENANT_ID}          (step 1/3: resolve SWA hostname)" >&2
  echo "   or:  az login --tenant ${EXTERNAL_ID_TENANT_ID}   (step 2/3: app registration)" >&2
  exit 1
fi
