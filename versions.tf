terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.48"
    }
  }

  # Uncomment and configure to store state remotely (recommended for teams)
  # backend "azurerm" {
  #   resource_group_name  = "your-tfstate-rg"
  #   storage_account_name = "yourtfstatestorage"
  #   container_name       = "tfstate"
  #   key                  = "oidc.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}
