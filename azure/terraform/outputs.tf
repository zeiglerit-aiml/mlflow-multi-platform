output "resource_group_name" { value = azurerm_resource_group.platform.name }
output "cluster_name" { value = azurerm_kubernetes_cluster.platform.name }
output "acr_name" { value = azurerm_container_registry.platform.name }
output "acr_login_server" { value = azurerm_container_registry.platform.login_server }
output "storage_account_name" { value = azurerm_storage_account.artifacts.name }
output "postgres_host" { value = azurerm_postgresql_flexible_server.mlflow.fqdn }
output "workload_identity_client_id" { value = azurerm_user_assigned_identity.mlflow.client_id }
output "tenant_id" { value = data.azurerm_client_config.current.tenant_id }
output "database_password" {
  value     = random_password.database.result
  sensitive = true
}
