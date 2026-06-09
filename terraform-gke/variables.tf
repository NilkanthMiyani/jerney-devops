variable "project_id" {
  description = "GCP project ID (find it in GCP Console → Project Info)"
  type        = string
}

variable "region" {
  description = "GCP region — us-central1 has the cheapest compute in GCP"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Single GCP zone — single-zone cluster is ~3x cheaper than regional"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "jerney-gke"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "node_machine_type" {
  description = "GCE machine type — e2-medium (2 vCPU, 4GB) is the minimum practical for this stack"
  type        = string
  default     = "e2-medium"
}

variable "min_node_count" {
  description = "Minimum nodes when idle — 1 keeps cost minimal"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum nodes under load"
  type        = number
  default     = 3
}

variable "disk_size_gb" {
  description = "Node boot disk size in GB"
  type        = number
  default     = 30
}
