# ==============================================================
# Jerney - GKE versions.tf
# Standard file: terraform block + provider block live here
# ==============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote backend — required for team use and production.
  # Uncomment and set bucket/prefix when sharing state across machines.
  # GCS provides built-in locking (no separate lock table needed).
  #
  # backend "gcs" {
  #   bucket = "YOUR_PROJECT_ID-terraform-state"
  #   prefix = "jerney-gke/state"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
