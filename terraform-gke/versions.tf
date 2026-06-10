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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "gcs" {
    bucket = "project-f26ca60a-38f7-49d3-b7b-tf-state"
    prefix = "jerney-gke/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
