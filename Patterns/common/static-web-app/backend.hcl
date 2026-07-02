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
# tfstatestoragelab2 lives in the "cjsazurelab" subscription, which is
# separate from the subscription the deploy service principal otherwise
# operates in (see provider "azurerm" in main.tf) — pin it explicitly so
# backend init doesn't default to the wrong subscription.
subscription_id      = "17c87a53-9192-4a5c-b1fc-0bfa7f8e947a"
