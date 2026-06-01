# -----------------------------------------------------------------------------
# One client_id output per group.
# Each repo's workflow uses the client_id of its own group.
#
# Copy tenant_id and subscription_id once as org-level GitHub secrets.
# For client_id, you have two options:
#   A) Store each group's client_id as a named org secret, e.g:
#        AZURE_CLIENT_ID_FRONTEND
#        AZURE_CLIENT_ID_BACKEND
#   B) Store it as a repo-level secret in each repo (only that group's value)
# -----------------------------------------------------------------------------

output "client_ids" {
  description = "Map of group name → client_id. Add each as a GitHub org or repo secret."
  value = {
    for name in keys(local.groups) :
    name => azuread_application.groups[name].client_id
  }
}

output "tenant_id" {
  description = "GitHub org secret: AZURE_TENANT_ID (same for all groups)"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "GitHub org secret: AZURE_SUBSCRIPTION_ID (same for all groups)"
  value       = data.azurerm_client_config.current.subscription_id
}

output "service_principal_object_ids" {
  description = "Map of group name → service principal object ID (for reference)"
  value = {
    for name in keys(local.groups) :
    name => azuread_service_principal.groups[name].object_id
  }
}

output "credential_count_per_group" {
  description = "How many federated credentials each group is using (Azure limit: 20)"
  value = {
    for group_name, cfg in local.groups :
    group_name => length(cfg.repos) * length(cfg.branches)
  }
}
