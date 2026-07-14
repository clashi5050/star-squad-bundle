# =============================================================================
# variables.tf
# -----------------------------------------------------------------------------
# Variable declarations for the static-web-app pattern.
# The arm_* variables are supplied via terraform.auto.tfvars (written by the
# workflow from GitHub secrets). The rest come from nonsecret.auto.tfvars,
# rendered from the environment JSON input.
# =============================================================================

# --- OIDC / Azure auth (secret, injected by the workflow) --------------------
variable "arm_client_id" {
  description = "Azure AD application (client) ID used for OIDC auth."
  type        = string
}

variable "arm_subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "arm_tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
}

# --- Non-secret, from JSON matrix -------------------------------------------
variable "company_loc" {
  description = "Company/location short code used in resource naming."
  type        = string
}

variable "location" {
  description = "Azure region (long form, e.g. eastus2)."
  type        = string
}

variable "short_loc" {
  description = "Short region code used in naming (e.g. use2)."
  type        = string
}

variable "environment" {
  description = "Deployment environment (sndx, dev, test, np, stg, uat, prod)."
  type        = string
}

variable "type" {
  description = "Resource type short code (e.g. swa for static web app)."
  type        = string
}

variable "app" {
  description = "Application name used in resource naming (e.g. starsquad)."
  type        = string
}

# --- Plan / backend services (added for accounts + sync) ---------------------
variable "swa_sku" {
  description = "Static Web App plan. Standard is required for custom auth, the managed API, and private endpoints. Was Free before accounts were added."
  type        = string
  default     = "Standard"
}

variable "cosmos_db_name" {
  description = "Cosmos DB SQL database name that stores per-user app data."
  type        = string
  default     = "starsquad"
}

variable "cosmos_container_name" {
  description = "Cosmos DB container holding one document per family, partitioned by /userId."
  type        = string
  default     = "families"
}
