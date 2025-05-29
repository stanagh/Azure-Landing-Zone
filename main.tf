## Identity
resource "azurerm_resource_group" "identity_rg" {
  name     = "rg-identity-prod-uks"
  location = var.location
}


resource "azurerm_key_vault" "identity_kv" {
  name                = "examplekeyvault"
  location            = var.location
  resource_group_name = azurerm_resource_group.identity_rg.name
  tenant_id           = var.tenant_id
  sku_name            = "premium"
}

resource "azurerm_key_vault_access_policy" "identity_policy" {
  key_vault_id = azurerm_key_vault.identity_kv.id
  tenant_id    = var.tenant_id
  object_id    = var.object_id
  depends_on   = [azurerm_key_vault.identity_kv]

  key_permissions = [
    "Get",
  ]

  secret_permissions = [
    "Get",
  ]
}

resource "azurerm_policy_definition" "identity_policy" {
  name         = "App service SKU restrict"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "This policy is set to allow App services creation of a certain SKU"

  policy_rule = <<POLICY_RULE
{
  "if": {
    "allOf": [
      {
        "field": "type",
        "equals": "Microsoft.Web/serverFarms"
      },
      {
        "field": "Microsoft.Web/serverFarms/sku.name",
        "equals": "F1"
      }
    ]
  },
  "then": {
    "effect": "Deny"
  }
}
POLICY_RULE
}


resource "azurerm_resource_group_policy_assignment" "restrict_appservice_to_f1" {
  name                 = "enforce-app-service-f1"
  resource_group_id    = azurerm_resource_group.identity_rg.id
  policy_definition_id = azurerm_policy_definition.identity_policy.id
}

resource "azurerm_security_center_workspace" "identity_security_center" {
  scope        = "/subscriptions/${var.subscription_id}"
  workspace_id = azurerm_log_analytics_workspace.management_log.id
  depends_on   = [azurerm_log_analytics_workspace.management_log]
}

## management

resource "azurerm_resource_group" "management_rg" {
  name     = "rg-management-prod-uks"
  location = var.location
}

resource "azurerm_log_analytics_workspace" "management_log" {
  name                = "log-management-workspace-uks"
  location            = azurerm_resource_group.management_rg.location
  resource_group_name = azurerm_resource_group.management_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}


## network 

resource "azurerm_resource_group" "network_rg" {
  name     = "rg-network-prod-uks"
  location = var.location
}

resource "azurerm_virtual_network" "network_vnet" {
  name                = "vnet-hub-uks"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_network_security_group" "network_nsg" {
  name                = "hub-nsg"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
}

resource "azurerm_application_security_group" "network_asg" {
  name                = "asg-uks-1"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
}

resource "azurerm_subnet" "network_firewall_subnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.network_rg.name
  virtual_network_name = azurerm_virtual_network.network_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "network_ip" {
  name                = "PIP-firewall"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "network_firewall" {
  name                = "Azure-Firewall"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "IPconfig"
    subnet_id            = azurerm_subnet.network_firewall_subnet
    public_ip_address_id = azurerm_public_ip.network_ip
  }
}

resource "azurerm_private_dns_zone" "example" {
  name                = "internal.stanagh.com"
  resource_group_name = azurerm_resource_group.network_rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "network_vnet_link" {
  name                  = "dns-vnet-link"
  resource_group_name   = azurerm_resource_group.network_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.example.name
  virtual_network_id    = azurerm_virtual_network.network_vnet.id
}

resource "azurerm_firewall_network_rule_collection" "network_firewwall_rule" {
  name                = "NetRules-Allow"
  azure_firewall_name = azurerm_firewall.network_firewall.name
  resource_group_name = azurerm_resource_group.network_rg.name
  priority            = 100
  action              = "Allow"

  rule {
    name = "testrule"
    source_addresses = ["*"]
    destination_ports = ["443"]
    destination_addresses = ["10.0.1.0/24"]
    protocols = ["TCP"]
  }
}

#### application layer

resource "azurerm_resource_group" "app_rg" {
  name     = "rg-application-prod-uks"
  location = var.location
}


resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "project-appserviceplan"
  location            = azurerm_resource_group.app_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name

  sku {
    tier = "Standard"
    size = "F1"
  }
}

resource "azurerm_app_service" "app_service_webapp" {
  name                = "project-appservice"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name
  app_service_plan_id = azurerm_app_service_plan.app_service_plan.id

    site_config {
    linux_fx_version = "DOTNETCORE|6.0" 
  }
}











