#!/usr/bin/env bash
# =============================================================================
# set-swa-token.sh
# -----------------------------------------------------------------------------
# Run AFTER the "Add Static Web App" workflow (Terraform apply) has created the
# Static Web App. Grabs the deployment API token and stores it as the GitHub
# secret AZURE_STATIC_WEB_APPS_API_TOKEN so the content-deploy workflow can ship
# apps/star-squad/.
#
# Two ways to get the token:
#   A) From Terraform output (if you run this where state is accessible):
#        terraform output -raw api_key
#   B) From Azure directly (no state needed) -- this script uses this path.
#
# Requires: az CLI + gh CLI, both authenticated.
# =============================================================================
set -euo pipefail

# ------------------------------- CONFIG --------------------------------------
GITHUB_ORG="clashi5050"
GITHUB_REPO="star-squad-bundle"
GH_ENVIRONMENT="dev"

# Must match the naming produced by main.tf:
#   rg-<company_loc>-<app>-<type>-<environment>-<short_loc>
#   swa-<company_loc>-<app>-<type>-<environment>-<short_loc>
COMPANY_LOC="use2"
APP="starsquad"
TYPE="swa"
ENVIRONMENT="dev"
SHORT_LOC="use2"
# -----------------------------------------------------------------------------

NAME_PREFIX="${COMPANY_LOC}-${APP}-${TYPE}-${ENVIRONMENT}-${SHORT_LOC}"
RG="rg-${NAME_PREFIX}"
SWA="swa-${NAME_PREFIX}"
REPO="${GITHUB_ORG}/${GITHUB_REPO}"

echo ">> Fetching deployment token for ${SWA} (rg: ${RG})..."
TOKEN="$(az staticwebapp secrets list \
  --name "${SWA}" \
  --resource-group "${RG}" \
  --query 'properties.apiKey' -o tsv)"

if [[ -z "${TOKEN}" ]]; then
  echo "!! No token returned. Check that the SWA exists and names match main.tf." >&2
  exit 1
fi

echo ">> Storing AZURE_STATIC_WEB_APPS_API_TOKEN on ${REPO} (${GH_ENVIRONMENT})..."
gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN \
  --env "${GH_ENVIRONMENT}" --repo "${REPO}" --body "${TOKEN}"

echo ">> Done. Push a change under apps/star-squad/ (or run the deploy workflow"
echo "   manually) and the app will publish to the SWA's default hostname:"
az staticwebapp show --name "${SWA}" --resource-group "${RG}" \
  --query 'defaultHostname' -o tsv | sed 's#^#   https://#'
