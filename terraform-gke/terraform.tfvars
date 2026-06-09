# ---------------------------------------------------------------
# Fill in your GCP project ID before running terraform apply
# Find it: GCP Console → click project dropdown → copy Project ID
# ---------------------------------------------------------------
project_id = "YOUR_GCP_PROJECT_ID"

region = "us-central1"
zone   = "us-central1-a"

cluster_name      = "jerney-gke"
environment       = "dev"
node_machine_type = "e2-medium"
min_node_count    = 1
max_node_count    = 3
disk_size_gb      = 30
