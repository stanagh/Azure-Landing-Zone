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
    {
    "policyRule": {
        "if": {
            "allOf": [{
                    "field": "type",
                    "equals": "Microsoft.Compute/virtualMachines"
                },
                {
                    "field": "Microsoft.Compute/virtualMachines/sku.name",
                    "like": "F1"
                }
            ]
        },
        "then": {
            "effect": "deny"
        }
    }
}
POLICY_RULE
}

resource "azurerm_resource_group_policy_assignment" "restrict_appservice_to_f1" {
  name                 = "enforce-app-service-f1"
  resource_group_id    = azurerm_resource_group.identity_rg.id # or use subscription_id
  policy_definition_id = azurerm_policy_definition.identity_policy.id
}

  
  




