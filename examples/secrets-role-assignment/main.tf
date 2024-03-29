terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.7.0, < 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.1, < 4.0.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # useful when doing demos and test/dev!
      prevent_deletion_if_contains_resources = false
    }
  }
  skip_provider_registration = true
}

# We need the tenant id for the key vault.
data "azurerm_client_config" "this" {}

# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/regions/azurerm"
  version = ">= 0.3.0"
}

# This allows us to randomize the region for the resource group.
resource "random_integer" "region_index" {
  min = 0
  max = length(module.regions.regions) - 1
}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.0"
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name_unique
  location = module.regions.regions[random_integer.region_index.result].name
}

resource "random_password" "first_secret" {
  length  = 15
  special = true
}

resource "random_password" "second_secret" {
  length  = 20
  special = true
}

# get the IP client running terraform
data "http" "my_ip" {
  url = "https://ifconfig.me/ip"
}

module "keyvault" {
  source                        = "Azure/avm-res-keyvault-vault/azurerm"
  version                       = "0.5.1"
  name                          = module.naming.key_vault.name_unique
  enable_telemetry              = var.enable_telemetry
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.this.tenant_id
  purge_protection_enabled      = false
  public_network_access_enabled = true # so we can check the secrets get created ok.
  sku_name                      = "standard"
  tags                          = var.tags

  network_acls = {
    ip_rules = [data.http.my_ip.response_body]
  }

  role_assignments = {
    devops_principal_secrets_officer = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.this.object_id
    },
  }

  # an alternative way, rather than to supply secrets inline, is to build secrets as local variables
  secrets = {
    "my_first_secret" = {
      name = "my-1st-secret"
    }
    "my_second_secret" = {
      name = "my-2nd-secret"
      # illustrating a role assignment for a specific secret
      role_assignments = {
        my_test_group = {
          role_definition_id_or_name = "Key Vault Secrets User"
          principal_id               = "dcade1b3-d52e-479e-aefd-6e6e4128959f" # make sure you use a principal that exists in Entra ID!
        }
      }
    }
  }

  # secret values are marked as sensitive and thus can not be used in a for_each loop
  secrets_value = {
    "my_first_secret"  = random_password.second_secret.result,
    "my_second_secret" = random_password.second_secret.result
  }
}
