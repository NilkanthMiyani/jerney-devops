# ==============================================================
# Jerney - GKE Bootstrap
#
# Replaces k8s-gke/bootstrap/install-argocd.sh with Terraform.
# Terraform manages ONLY two things here:
#   1. helm_release.argocd   — installs ArgoCD into the cluster
#   2. null_resource.argocd_root_app — applies root-app.yaml via kubectl
#                              (null_resource used instead of kubernetes_manifest
#                               because ArgoCD CRDs don't exist at plan time)
#
# Everything else (ingress-nginx, cert-manager, prometheus, ArgoCD
# ingress, etc.) is deployed by ArgoCD from k8s-gke/apps/ in Git.
#
# GitOps deploy order after terraform apply:
#   ArgoCD wave 0: cert-manager
#   ArgoCD wave 1: cluster-issuer, prometheus-stack, signoz
#   ArgoCD wave 2: argocd-ingress, loki-stack  (GKE ingress controller is built-in, always ready)
#   ArgoCD wave 3: jerney
# ==============================================================

# ---- GCP auth token for helm + kubernetes providers ----
data "google_client_config" "default" {}

# ---- Helm provider — connects directly to GKE via cluster endpoint ----
provider "helm" {
  kubernetes {
    host  = "https://${google_container_cluster.jerney.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      google_container_cluster.jerney.master_auth[0].cluster_ca_certificate
    )
  }
}

# ---- 1. ArgoCD Helm Release ----
resource "helm_release" "argocd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.3"
  namespace        = "argocd"
  create_namespace = true
  wait             = true # blocks until all ArgoCD pods are Running
  timeout          = 300

  set {
    # Runs ArgoCD server without TLS — GKE LB handles TLS termination
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  values = [
    yamlencode({
      server = {
        service = {
          annotations = {
            "cloud.google.com/neg" = "{\"ingress\": true}"
          }
        }
      }
      configs = {
        cm = {
          # K8s 1.35 adds StatefulSet.status.terminatingReplicas which ArgoCD 2.13's
          # structured-merge-diff schema doesn't know about. Strip it globally before
          # schema validation so prometheus-stack StatefulSets don't get ComparisonError.
          "resource.customizations.ignoreDifferences.apps_StatefulSet" = "jqPathExpressions:\n- .status.terminatingReplicas\n"
        }
      }
    })
  ]

  depends_on = [google_container_node_pool.jerney_nodes]
}

# ---- 2. Root App-of-Apps ----
# Applies root-app.yaml after ArgoCD is running.
# Uses null_resource + local-exec (kubectl) instead of kubernetes_manifest
# because the argoproj.io/Application CRD doesn't exist at plan time —
# kubernetes_manifest validates CRD schemas during plan, which fails on a fresh cluster.
resource "null_resource" "argocd_root_app" {
  triggers = {
    # Re-applies if the manifest changes
    manifest_hash = filemd5("${path.module}/../k8s-gke/apps/root-app.yaml")
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud container clusters get-credentials ${var.cluster_name} \
        --zone ${var.zone} \
        --project ${var.project_id}
      kubectl apply -f ${path.module}/../k8s-gke/apps/root-app.yaml
    EOT
  }

  depends_on = [helm_release.argocd]
}
