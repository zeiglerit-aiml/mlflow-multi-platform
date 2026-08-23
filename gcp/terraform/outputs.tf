output "cluster_name" { value = google_container_cluster.platform.name }
output "registry_host" { value = "${var.region}-docker.pkg.dev" }
output "artifact_repository" { value = google_artifact_registry_repository.platform.repository_id }
output "artifact_bucket" { value = google_storage_bucket.artifacts.name }
output "cloud_sql_connection_name" { value = google_sql_database_instance.mlflow.connection_name }
output "mlflow_service_account_email" { value = google_service_account.mlflow.email }
output "database_password_secret_id" { value = google_secret_manager_secret.database_password.secret_id }
