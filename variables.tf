# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organisation name (e.g. 'imovelle')"
  type        = string
}

variable "keyvault_name" {
  description = "Name of the existing Azure Key Vault"
  type        = string
}

variable "keyvault_resource_group" {
  description = "Resource group that contains the Key Vault"
  type        = string
}

# -----------------------------------------------------------------------------
# App Registration groups
#
# Azure AD hard limit: 20 federated credentials per App Registration.
# To stay under the limit, repos are split into named groups.
# Each group gets its own App Registration and client_id.
#
# Rule of thumb: keep each group under 8 repos when using 2 branches,
# or under 18 repos when deploying from main only.
#
# Structure:
#   app_registrations = {
#     "group-name" = {
#       repos    = ["repo-a", "repo-b"]
#       branches = ["main"]          # optional — defaults to var.default_branches
#     }
#   }
# -----------------------------------------------------------------------------

variable "app_registrations" {
  description = "Named groups of repos, each getting its own App Registration"
  type = map(object({
    repos    = list(string)
    branches = optional(list(string))
  }))
  default = {}
}

variable "default_branches" {
  description = "Branches used when a group does not specify its own"
  type        = list(string)
  default     = ["main"]
}
