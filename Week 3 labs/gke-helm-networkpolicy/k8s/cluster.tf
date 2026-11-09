# The Lab 3.2 cluster as code: tofu init && tofu apply -var project=<PROJECT_ID>; tofu destroy to clean up.
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
variable "project" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}
provider "google" {
  project = var.project
  region  = var.region
}
resource "google_container_cluster" "silverlake" {
  name                = "silverlake-public"
  location            = var.region
  enable_autopilot    = true
  deletion_protection = false
}
output "get_credentials" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.silverlake.name} --region ${var.region} --project ${var.project}"
}
