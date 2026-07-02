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

  # Partial backend config. Storage account/container/resource group are fixed
  # in backend.hcl (committed) so they don't need to be re-supplied each time.
  # Only `key` still varies per environment/region and is passed at init time:
  #   terraform init -backend-config=backend.hcl \
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

  sku_tier = "Free"
  sku_size = "Free"

  tags = local.common_tags
}
