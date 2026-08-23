variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}
variable "resource_group_name" {
  type    = string
  default = "agentic-ml-rg"
}
variable "location" {
  type    = string
  default = "eastus2"
}
variable "platform_name" {
  type    = string
  default = "agentic-ml"
}
variable "node_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}
