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
