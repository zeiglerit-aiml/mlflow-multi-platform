locals {
  services = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each           = local.services
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "platform" {
  name                    = "${var.platform_name}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.required]
}

resource "google_compute_subnetwork" "gke" {
  name          = "${var.platform_name}-gke"
  region        = var.region
  network       = google_compute_network.platform.id
  ip_cidr_range = "10.20.0.0/20"
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.24.0.0/14"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.28.0.0/20"
  }
  private_ip_google_access = true
}

resource "google_compute_global_address" "private_services" {
  name          = "${var.platform_name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.platform.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.platform.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

resource "google_container_cluster" "platform" {
  name     = "${var.platform_name}-gke"
  location = var.zone
  network  = google_compute_network.platform.id
  subnetwork = google_compute_subnetwork.gke.id
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection     = false

  workload_identity_config { workload_pool = "${var.project_id}.svc.id.goog" }
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  release_channel { channel = "REGULAR" }
  network_policy {
    enabled  = true
    provider = "CALICO"
  }
  secret_manager_config { enabled = true }
  depends_on = [google_project_service.required]
}

resource "google_container_node_pool" "general" {
  name     = "general"
  cluster  = google_container_cluster.platform.name
  location = var.zone
  autoscaling {
    min_node_count = var.gke_min_nodes
    max_node_count = var.gke_max_nodes
  }
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  node_config {
    machine_type = var.gke_machine_type
    oauth_scopes  = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config { mode = "GKE_METADATA" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    metadata = { disable-legacy-endpoints = "true" }
  }
}

resource "google_artifact_registry_repository" "platform" {
  location      = var.region
  repository_id = "${var.platform_name}-containers"
  format        = "DOCKER"
  depends_on    = [google_project_service.required]
}

resource "google_storage_bucket" "artifacts" {
  name                        = "${var.project_id}-${var.platform_name}-artifacts"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  versioning { enabled = true }
  lifecycle_rule {
    condition {
      age                = 30
      num_newer_versions = 3
    }
    action { type = "Delete" }
  }
  depends_on = [google_project_service.required]
}

resource "random_password" "database" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "mlflow" {
  name             = "${var.platform_name}-postgres"
  region           = var.region
  database_version = "POSTGRES_16"
  deletion_protection = false
  settings {
    tier              = var.database_tier
    availability_type = "ZONAL"
    disk_autoresize    = true
    disk_type          = "PD_SSD"
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.platform.id
    }
  }
  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "mlflow" {
  name     = "mlflow"
  instance = google_sql_database_instance.mlflow.name
}
resource "google_sql_user" "mlflow" {
  name     = "mlflow"
  instance = google_sql_database_instance.mlflow.name
  password = random_password.database.result
}

resource "google_secret_manager_secret" "database_password" {
  secret_id = "${var.platform_name}-database-password"
  replication { auto {} }
  depends_on = [google_project_service.required]
}
resource "google_secret_manager_secret_version" "database_password" {
  secret      = google_secret_manager_secret.database_password.id
  secret_data = random_password.database.result
}

resource "google_service_account" "mlflow" {
  account_id   = substr(replace("${var.platform_name}-mlflow", "_", "-"), 0, 30)
  display_name = "MLflow GKE workload"
}

resource "google_storage_bucket_iam_member" "mlflow_artifacts" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.mlflow.email}"
}
resource "google_project_iam_member" "mlflow_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.mlflow.email}"
}
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.mlflow.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[ml-platform/mlflow]"
}
