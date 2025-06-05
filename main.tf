## Identity
resource "azurerm_resource_group" "identity_rg" {
  name     = "rg-identity-prod-uks"
  location = var.location
}


resource "azurerm_key_vault" "identity_kv" {
  name                = "identitykeyvault"
  location            = var.location
  resource_group_name = azurerm_resource_group.identity_rg.name
  tenant_id           = var.tenant_id
  sku_name            = "standard"
}

resource "azurerm_key_vault_access_policy" "identity_policy" {
  key_vault_id = azurerm_key_vault.identity_kv.id
  tenant_id    = var.tenant_id
  object_id    = var.object_id
  depends_on   = [azurerm_key_vault.identity_kv]

  key_permissions = [
    "Get", "List"
  ]

  secret_permissions = [
    "Get", "List"
  ]
}

resource "azurerm_policy_definition" "identity_policy" {
  name         = "deny-non-premium-appservice"
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
        "notIn": ["P1", "P2"]
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
  address_space       = ["10.5.0.0/16"]
}

resource "azurerm_virtual_network_peering" "network_peering-1" {
  name                      = "hub-spoke"
  resource_group_name       = azurerm_resource_group.network_rg.name
  virtual_network_name      = azurerm_virtual_network.network_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.app_vnet.id
  depends_on                = [azurerm_virtual_network.network_vnet]
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
  address_prefixes     = ["10.5.1.0/24"]
}

resource "azurerm_public_ip" "network_ip" {
  name                = "PIP-firewall"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  allocation_method   = "Static"
}

resource "azurerm_firewall" "network_firewall" {
  name                = "Azure-Firewall"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "IPconfig"
    subnet_id            = azurerm_subnet.network_firewall_subnet.id
    public_ip_address_id = azurerm_public_ip.network_ip.id
  }
}

resource "azurerm_firewall_network_rule_collection" "network_firewwall_rule" {
  name                = "NetRules-Allow"
  azure_firewall_name = azurerm_firewall.network_firewall.name
  resource_group_name = azurerm_resource_group.network_rg.name
  priority            = 100
  action              = "Allow"
  depends_on          = [azurerm_firewall.network_firewall]

  rule {
    name                  = "testrule"
    source_addresses      = ["*"]
    destination_ports     = ["443"]
    destination_addresses = ["10.5.1.0/24"]
    protocols             = ["TCP"]
  }
}

resource "azurerm_route_table" "app_udr" {
  name                = "rt-app-to-firewall"
  location            = var.location
  resource_group_name = azurerm_resource_group.network_rg.name
}

resource "azurerm_route" "app_to_fw_default" {
  name                   = "default-to-fw"
  resource_group_name    = azurerm_resource_group.network_rg.name
  route_table_name       = azurerm_route_table.app_udr.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.network_firewall.ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "app_subnet_udr_association" {
  subnet_id      = azurerm_subnet.app_vnet_subnet.id
  route_table_id = azurerm_route_table.app_udr.id
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

resource "azurerm_network_watcher" "network_watcher" {
  name                = "production-nwwatcher"
  location            = azurerm_resource_group.network_rg.location
  resource_group_name = azurerm_resource_group.network_rg.name
}

#### application layer

resource "azurerm_resource_group" "app_rg" {
  name     = "rg-application-prod-uks"
  location = var.location
}

resource "azurerm_virtual_network" "app_vnet" {
  name                = "example-virtual-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.app_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name
}

resource "azurerm_subnet" "app_vnet_subnet" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.app_rg.name
  virtual_network_name = azurerm_virtual_network.app_vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "private-vnet-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_service_plan" "app_service_plan" {
  name                = "example-app-service-plan"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = azurerm_resource_group.app_rg.location
  os_type             = "Linux"
  sku_name            = "S1"
}

resource "azurerm_linux_web_app" "app_service_webapp" {
  name                = "project-web-app"
  resource_group_name = azurerm_resource_group.app_rg.name
  location            = azurerm_service_plan.app_service_plan.location
  service_plan_id     = azurerm_service_plan.app_service_plan.id
  depends_on          = [azurerm_service_plan.app_service_plan]
  site_config {
    application_stack {
      dotnet_version = "6.0"
    }
  }
}

resource "azurerm_app_service_virtual_network_swift_connection" "app_vnet_intergration" {
  app_service_id = azurerm_linux_web_app.app_service_webapp.id
  subnet_id      = azurerm_subnet.app_vnet_subnet.id
  depends_on     = [azurerm_subnet.app_vnet_subnet]
}

resource "azurerm_virtual_network_peering" "app_peering-2" {
  name                      = "spoke-hub"
  resource_group_name       = azurerm_resource_group.app_rg.name
  virtual_network_name      = azurerm_virtual_network.app_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.network_vnet.id
  depends_on                = [azurerm_virtual_network.app_vnet]
}

resource "azurerm_network_security_group" "app_nsg" {
  name                = "app-vnet-nsg"
  location            = azurerm_resource_group.app_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name
}

resource "azurerm_subnet_network_security_group_association" "app_vnet_association" {
  subnet_id                 = azurerm_subnet.app_vnet_subnet.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
}

## app monitoring

resource "azurerm_application_insights" "app_insights" {
  name                = "web-app-insights"
  location            = azurerm_resource_group.app_rg.location
  resource_group_name = azurerm_resource_group.app_rg.name
  application_type    = "web"
  depends_on          = [azurerm_linux_web_app.app_service_webapp]
}

output "instrumentation_key" {
  value = azurerm_application_insights.app_insights.instrumentation_key
}

output "app_id" {
  value = azurerm_application_insights.app_insights.app_id
}


### backend

resource "azurerm_mssql_server" "app_sql_server" {
  name                         = "app-sqlserver"
  resource_group_name          = azurerm_resource_group.app_rg.name
  location                     = azurerm_resource_group.app_rg.location
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = var.sql_admin_password
}

resource "azurerm_mssql_database" "app_sql_db" {
  name         = "example-db"
  server_id    = azurerm_mssql_server.app_sql_server.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  max_size_gb  = 2
  sku_name     = "S0"
  enclave_type = "VBS"
  depends_on   = [azurerm_mssql_server.app_sql_server]


  # prevent the possibility of accidental data loss
  lifecycle {
    prevent_destroy = true
  }
}












