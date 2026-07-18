# =============================================================================
# backend.hcl
# -----------------------------------------------------------------------------
# Fixed remote state backend for this pattern. Committed so the storage
# account/container don't need to be re-supplied on every `terraform init`.
# Two values still vary per invocation and are passed separately via
# -backend-config, NOT committed here:
#   - key: varies per environment/region
#   - subscription_id: the storage account lives in a different subscription
#     than the one the deploy service principal otherwise operates in (see
#     provider "azurerm" in main.tf). This repo is public and that
#     subscription ID is treated as sensitive, so it's supplied at init time
#     from the TFSTATE_SUBSCRIPTION_ID GitHub secret rather than committed.
#   terraform init -backend-config=backend.hcl \
#     -backend-config="key=${environment}-${short_loc}-static-web-app.tfstate" \
#     -backend-config="subscription_id=${TFSTATE_SUBSCRIPTION_ID}"
# =============================================================================
resource_group_name  = "tfstatelab"
storage_account_name = "tfstatestoragelab2"
container_name       = "tfstate"
