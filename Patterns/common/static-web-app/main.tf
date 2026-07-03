# =============================================================================
# main.tf
# -----------------------------------------------------------------------------
# Static Terraform config. No runtime templating: every environment-specific
# value arrives through variables (rendered into nonsecret.auto.tfvars from the
# JSON matrix) and the backend is configured via -backend-config flags on
# `terraform init`. This avoids the fragile eval/echo templating and is the
# recommended way to parameterize remote state.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Partial backend config — concrete values supplied at init time:
  #   terraform init \
  #     -backend-config="resource_group_name=$TFSTATE_RG" \
  #     -backend-config="storage_account_name=$TFSTATE_SA" \
  #     -backend-config="container_name=tfstate" \
  #     -backend-config="key=${environment}-${short_loc}-static-web-app.tfstate"
  backend "azurerm" {
    use_oidc = true
  }
}

provider "azurerm" {
  features {}

  use_oidc        = true
  client_id       = var.arm_client_id
  subscription_id = var.arm_subscription_id
  tenant_id       = var.arm_tenant_id
}

locals {
  # Naming convention: <company_loc>-<app>-<type>-<environment>-<short_loc>
  # e.g. use2-starsquad-swa-sndx-use2
  name_prefix = "${var.company_loc}-${var.app}-${var.type}-${var.environment}-${var.short_loc}"

  common_tags = {
    environment = var.environment
    app         = var.app
    type        = var.type
    location    = var.location
    managed-by  = "terraform"
    repo        = "iac-patterns"
    pattern     = "static-web-app"
  }
}

# -----------------------------------------------------------------------------
# Resource Group dedicated to this Static Web App
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "swa" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------------
# Azure Static Web App (Free tier)
# Content is deployed separately via the static-web-app-deploy workflow using
# the deployment API token. Terraform only provisions the resource here.
# -----------------------------------------------------------------------------
resource "azurerm_static_web_app" "app" {
  name                = "swa-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.swa.name

  # Static Web Apps Free tier is only available in a subset of regions.
  # Override var.location via the JSON input if the region is not supported.
  location = var.location

  sku_tier = var.swa_sku
  sku_size = var.swa_sku

  # App settings consumed by the managed Functions API (see /api). The auth
  # provider's client id/secret are set out-of-band by scripts/setup-auth.sh so
  # the OIDC secret never passes through Terraform state.
  app_settings = {
    COSMOS_ENDPOINT  = azurerm_cosmosdb_account.db.endpoint
    COSMOS_KEY       = azurerm_cosmosdb_account.db.primary_key
    COSMOS_DATABASE  = azurerm_cosmosdb_sql_database.db.name
    COSMOS_CONTAINER = azurerm_cosmosdb_sql_container.families.name
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Cosmos DB (serverless, SQL/NoSQL API) — cross-device app data store.
# One document per family, partitioned by the authenticated user's id. Serverless
# means you pay per request (pennies at this scale) with no provisioned RU/s.
# -----------------------------------------------------------------------------
resource "azurerm_cosmosdb_account" "db" {
  name                = "cosmos-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.swa.name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = local.common_tags
}

resource "azurerm_cosmosdb_sql_database" "db" {
  name                = var.cosmos_db_name
  resource_group_name = azurerm_cosmosdb_account.db.resource_group_name
  account_name        = azurerm_cosmosdb_account.db.name
}

resource "azurerm_cosmosdb_sql_container" "families" {
  name                = var.cosmos_container_name
  resource_group_name = azurerm_cosmosdb_account.db.resource_group_name
  account_name        = azurerm_cosmosdb_account.db.name
  database_name       = azurerm_cosmosdb_sql_database.db.name
  partition_key_paths = ["/userId"]
  # Serverless: do not set throughput.
}
