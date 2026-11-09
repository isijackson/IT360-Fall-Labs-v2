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
variable "zone" {
  type    = string
  default = "us-central1-a"
}
variable "name" {
  type    = string
  default = "it360-web"
}
variable "ssh_public_key" { type = string }
variable "ssh_source_cidr" {
  type    = string
  default = "0.0.0.0/0" # narrow this to <your public ip>/32 outside a sandbox
}

provider "google" {
  project = var.project
  zone    = var.zone
}

resource "google_compute_firewall" "web" {
  name    = "${var.name}-allow-ssh-http"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.name]
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.name}-allow-ssh"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = [var.ssh_source_cidr]
  target_tags   = [var.name]
}

resource "google_compute_instance" "web" {
  name         = var.name
  machine_type = "e2-micro"
  tags         = [var.name]
  boot_disk {
    initialize_params { image = "ubuntu-os-cloud/ubuntu-2204-lts" }
  }
  network_interface {
    network = "default"
    access_config {}
  }
  metadata = {
    ssh-keys       = "ubuntu:${var.ssh_public_key}"
    startup-script = <<-EOT
      #!/bin/bash
      apt-get update && apt-get install -y nginx
      echo "<h1>served from Google Cloud by $(hostname)</h1>" > /var/www/html/index.html
    EOT
  }
}

output "public_ip" {
  value = google_compute_instance.web.network_interface[0].access_config[0].nat_ip
}
