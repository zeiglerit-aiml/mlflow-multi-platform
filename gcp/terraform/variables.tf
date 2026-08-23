variable "project_id" {
  type = string
}
variable "region" {
  type    = string
  default = "us-central1"
}
variable "zone" {
  type    = string
  default = "us-central1-a"
}
variable "platform_name" {
  type    = string
  default = "agentic-ml"
}
variable "gke_machine_type" {
  type    = string
  default = "e2-standard-4"
}
variable "gke_min_nodes" {
  type    = number
  default = 1
}
variable "gke_max_nodes" {
  type    = number
  default = 4
}
variable "database_tier" {
  type    = string
  default = "db-custom-2-7680"
}
