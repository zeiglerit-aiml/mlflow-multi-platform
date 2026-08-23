resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "random_password" "database" {
  length  = 32
  special = false
}

locals {
  compact_name = substr(replace("${var.platform_name}${random_string.suffix.result}", "-", ""), 0, 20)
}

resource "azurerm_resource_group" "platform" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "platform" {
  name                = "${var.platform_name}-logs"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_virtual_network" "platform" {
  name                = "${var.platform_name}-vnet"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  address_space       = ["10.40.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = ["10.40.0.0/20"]
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = ["10.40.16.0/24"]
  delegation {
    name = "postgres"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.platform_name}.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.platform.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.platform_name}-postgres-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.platform.id
  resource_group_name   = azurerm_resource_group.platform.name
}

resource "azurerm_container_registry" "platform" {
  name                = local.compact_name
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
  sku                 = "Standard"
  admin_enabled       = false
}

resource "azurerm_storage_account" "artifacts" {
  name                            = "${local.compact_name}art"
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = azurerm_resource_group.platform.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "artifacts" {
  name                  = "mlflow"
  storage_account_id    = azurerm_storage_account.artifacts.id
  container_access_type = "private"
}

resource "azurerm_user_assigned_identity" "mlflow" {
  name                = "${var.platform_name}-mlflow"
  resource_group_name = azurerm_resource_group.platform.name
  location            = azurerm_resource_group.platform.location
}

resource "azurerm_kubernetes_cluster" "platform" {
  name                = "${var.platform_name}-aks"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  dns_prefix          = var.platform_name
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  role_based_access_control_enabled = true

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_vm_size
    vnet_subnet_id       = azurerm_subnet.aks.id
    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 5
    node_count           = 2
  }

  identity { type = "SystemAssigned" }
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
  oms_agent { log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id }
}

resource "azurerm_federated_identity_credential" "mlflow" {
  name                = "mlflow-aks"
  resource_group_name = azurerm_resource_group.platform.name
  parent_id           = azurerm_user_assigned_identity.mlflow.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.platform.oidc_issuer_url
  subject             = "system:serviceaccount:ml-platform:mlflow"
}

resource "azurerm_role_assignment" "blob" {
  scope                = azurerm_storage_account.artifacts.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mlflow.principal_id
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.platform.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.platform.kubelet_identity[0].object_id
}

resource "azurerm_postgresql_flexible_server" "mlflow" {
  name                          = "${local.compact_name}-pg"
  resource_group_name           = azurerm_resource_group.platform.name
  location                      = azurerm_resource_group.platform.location
  version                       = "16"
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  administrator_login           = "mlflow"
  administrator_password        = random_password.database.result
  storage_mb                    = 131072
  sku_name                      = "GP_Standard_D2ds_v5"
  backup_retention_days         = 7
  public_network_access_enabled = false
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "mlflow" {
  name      = "mlflow"
  server_id = azurerm_postgresql_flexible_server.mlflow.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}
