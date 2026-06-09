#!/bin/bash
# ==============================================================
# Jerney GKE — One-Time Bootstrap
#
# Run this ONCE after `terraform apply`.
# After this script finishes, ArgoCD owns everything from Git.
# You never run a shell script to deploy again.
#
# What this does:
#   1. Configures kubectl for the GKE cluster
#   2. Installs ArgoCD via Helm (the only manual Helm install)
#   3. Applies the ArgoCD Ingress so the UI is accessible
#   4. Applies the root App-of-Apps → ArgoCD deploys everything else
#
# After this runs, ArgoCD installs:
#   ingress-nginx, cert-manager, cluster-issuer,
#   prometheus-stack, loki-stack, signoz, jerney
# ==============================================================

set -e

REPO_DIR="$(git rev-parse --show-toplevel)"

echo "=== Jerney GKE Bootstrap ==="
echo ""

# ---- Get cluster details from terraform output ----
cd "$REPO_DIR/terraform-gke"
GCP_PROJECT=$(terraform output -raw project_id 2>/dev/null || true)
GKE_ZONE=$(terraform output -raw zone 2>/dev/null || true)
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || true)

# Fall back to prompts if terraform output didn't work
if [ -z "$GCP_PROJECT" ]; then
  read -rp "GCP Project ID: " GCP_PROJECT
fi
if [ -z "$GKE_ZONE" ]; then
  read -rp "GKE Zone (default: us-central1-a): " GKE_ZONE
  GKE_ZONE="${GKE_ZONE:-us-central1-a}"
fi
if [ -z "$CLUSTER_NAME" ]; then
  read -rp "Cluster name (default: jerney-gke): " CLUSTER_NAME
  CLUSTER_NAME="${CLUSTER_NAME:-jerney-gke}"
fi

# ---- Configure kubectl ----
echo "🔑 Configuring kubectl..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --zone "$GKE_ZONE" \
  --project "$GCP_PROJECT"

kubectl get nodes
echo ""

# ---- Install ArgoCD ----
echo "🔄 Installing ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argo-cd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set 'configs.params.server\.insecure=true' \
  --wait --timeout 5m

echo "✅ ArgoCD installed"
echo ""

# ---- Apply ArgoCD Ingress ----
# ArgoCD manages everything else, but it can't manage its own ingress
# (chicken-and-egg). We apply it manually once here.
echo "🌐 Applying ArgoCD Ingress..."
kubectl apply -f "$REPO_DIR/k8s-gke/platform/argocd/manifests/ingress.yaml"
echo "✅ ArgoCD Ingress applied"
echo ""

# ---- Hand off to GitOps ----
# This ONE command triggers ArgoCD to deploy the entire platform from Git.
# ingress-nginx → cert-manager → cluster-issuer → prometheus → loki → signoz → jerney
echo "🚀 Applying root App-of-Apps — handing off to GitOps..."
kubectl apply -f "$REPO_DIR/k8s-gke/apps/root-app.yaml"
echo "✅ Root Application applied"
echo ""

# ---- Summary ----
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

echo "==========================================="
echo "🎉 Bootstrap Complete!"
echo "==========================================="
echo ""
echo "ArgoCD is now syncing the platform from Git."
echo "Watch progress: kubectl get applications -n argocd"
echo ""
echo "📋 ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "📋 Node External IP: $NODE_IP"
echo "   Set these DNS A records → $NODE_IP"
echo "   jerney.nilkanthprojects.site"
echo "   argocd.nilkanthprojects.site"
echo "   grafana.nilkanthprojects.site"
echo "   signoz.nilkanthprojects.site"
echo ""
echo "📋 Check sync status:"
echo "   kubectl get applications -n argocd"
echo "   kubectl get pods -A"
echo ""
