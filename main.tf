# -----------------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

data "azurerm_key_vault" "main" {
  name                = var.keyvault_name
  resource_group_name = var.keyvault_resource_group
}

# -----------------------------------------------------------------------------
# Locals
# Flatten the app_registrations map into two derived structures:
#   - one entry per group  → drives App Registration + SP + KV role
#   - one entry per repo×branch → drives federated credentials
# -----------------------------------------------------------------------------

locals {
  # Normalise each group: fill in branches from var.default_branches if not set
  groups = {
    for name, cfg in var.app_registrations : name => {
      repos    = cfg.repos
      branches = coalesce(cfg.branches, var.default_branches)
    }
  }

  # Flat map of every repo × branch pair, keyed by "<group>/<repo>-<branch>"
  # Used to create one federated credential per combination
  federated_credentials = {
    for pair in flatten([
      for group_name, cfg in local.groups : [
        for repo in cfg.repos : [
          for branch in cfg.branches : {
            key        = "${group_name}/${repo}-${branch}"
            group_name = group_name
            repo       = repo
            branch     = branch
          }
        ]
      ]
    ]) : pair.key => pair
  }
}

# -----------------------------------------------------------------------------
# App Registrations — one per group
# -----------------------------------------------------------------------------

resource "azuread_application" "groups" {
  for_each     = local.groups
  display_name = "${var.github_org}-${each.key}-oidc"
}

resource "azuread_service_principal" "groups" {
  for_each  = local.groups
  client_id = azuread_application.groups[each.key].client_id
}

# -----------------------------------------------------------------------------
# Federated credentials — one per repo × branch
# Stays well under Azure AD's 20-credential limit per App Registration
# because repos are spread across multiple registrations
# -----------------------------------------------------------------------------

resource "azuread_application_federated_identity_credential" "repos" {
  for_each = local.federated_credentials

  application_id = azuread_application.groups[each.value.group_name].id
  display_name   = "github-${each.value.repo}-${each.value.branch}"
  description    = "OIDC for ${var.github_org}/${each.value.repo} on branch ${each.value.branch}"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.signing.actions.githubusercontent.com"
  subject   = "repo:${var.github_org}/${each.value.repo}:ref:refs/heads/${each.value.branch}"
}

# -----------------------------------------------------------------------------
# Key Vault role assignments — one per group's service principal
# Each group can read secrets from the shared Key Vault
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "kv_secrets_user" {
  for_each             = local.groups
  scope                = data.azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.groups[each.key].object_id
}
