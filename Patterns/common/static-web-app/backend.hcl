# =============================================================================
# backend.hcl
# -----------------------------------------------------------------------------
# Fixed remote state backend for this pattern. Committed so the storage
# account/container don't need to be re-supplied on every `terraform init`.
# `key` still varies per environment/region and is passed separately:
#   terraform init -backend-config=backend.hcl \
#     -backend-config="key=${environment}-${short_loc}-static-web-app.tfstate"
# =============================================================================
resource_group_name  = "tfstatelab"
storage_account_name = "tfstatestoragelab2"
container_name       = "tfstate"
