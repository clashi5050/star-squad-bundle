# =============================================================================
# outputs.tf
# -----------------------------------------------------------------------------
# Surfaces values needed after provisioning. The deployment API token is
# sensitive and is used to configure the AZURE_STATIC_WEB_APPS_API_TOKEN secret
# for the separate content-deploy workflow.
# =============================================================================

output "static_web_app_name" {
  description = "Name of the provisioned Static Web App."
  value       = azurerm_static_web_app.app.name
}

output "resource_group_name" {
  description = "Resource group containing the Static Web App."
  value       = azurerm_resource_group.swa.name
}

output "default_host_name" {
  description = "Auto-generated public hostname (https://<this>)."
  value       = azurerm_static_web_app.app.default_host_name
}

output "api_key" {
  description = "Deployment API token for the content-deploy workflow. Store as the AZURE_STATIC_WEB_APPS_API_TOKEN secret."
  value       = azurerm_static_web_app.app.api_key
  sensitive   = true
}

output "cosmos_account_name" {
  description = "Cosmos DB account backing cross-device sync."
  value       = azurerm_cosmosdb_account.db.name
}

output "cosmos_endpoint" {
  description = "Cosmos DB endpoint used by the managed Functions API."
  value       = azurerm_cosmosdb_account.db.endpoint
}
