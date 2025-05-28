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


resource "azurerm_policy_definition" "policy" {
  name         = "VM restrict"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "This policy is set to allow VM creation of a certain SKU"

  policy_rule = <<POLICY_RULE
 {
    "if": {
      "not": {
        "field": "Microsoft.Compute.Data",
        "in": "[parameters('allowedLocations')]"
      }
    },
    "then": {
      "effect": "deny"
    }
  }
POLICY_RULE

}






