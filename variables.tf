variable "location" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "object_id" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}

variable "administrator_login" {
  type = string
}


