#!/bin/bash
# ==============================================================
# Jerney - Post Kubeadm Setup
# Run this AFTER SSH-ing into the EC2 instance
# Installs: NGINX Ingress, cert-manager, ArgoCD, SigNoz
#
# Manifests are in: terraform-ec2/manifests/
# ==============================================================

MANIFESTS_DIR="$(cd "$(dirname "$0")/../manifests" && pwd)"

set -e

echo "=== Jerney Post-Setup Script ==="
echo "================================"

# ---- Verify cluster is ready ----
echo ""
echo "📋 Checking cluster status..."
kubectl get nodes
echo ""

# Wait for all system pods to be ready
echo "⏳ Waiting for system pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s || true
echo ""

# ---- 1. Install NGINX Ingress Controller ----
echo "🌐 Installing NGINX Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.hostPort.enabled=true \
  --set controller.service.type=NodePort \
  --set controller.kind=DaemonSet \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

echo "⏳ Waiting for Ingress Controller to be ready..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=300s
echo "✅ NGINX Ingress Controller installed"
echo ""

# ---- 2. Install cert-manager ----
echo "🔐 Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

echo "⏳ Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s
echo "✅ cert-manager installed"
echo ""

# ---- 3. Create Let's Encrypt ClusterIssuer ----
echo "📜 Creating Let's Encrypt ClusterIssuer..."
kubectl apply -f "$MANIFESTS_DIR/clusterissuer.yaml"
echo "✅ ClusterIssuer created"
echo ""

# ---- 4. Install ArgoCD ----
echo "🔄 Installing ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argo-cd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 7.8.0 \
  --set server.insecure=true

echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=600s
echo "✅ ArgoCD installed"
echo ""

# ---- 5. Install SigNoz ----
echo "📊 Installing SigNoz..."
helm repo add signoz https://charts.signoz.io
helm repo update

helm install signoz signoz/signoz \
  --namespace platform \
  --create-namespace \
  --set frontend.service.type=ClusterIP

echo "⏳ Waiting for SigNoz pods (this may take a few minutes)..."
sleep 30
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=frontend -n platform --timeout=600s || true
echo "✅ SigNoz installed"
echo ""

# ---- 6. Apply Ingress Resources ----
echo "🌐 Applying Ingress resources..."
kubectl apply -f "$MANIFESTS_DIR/argocd-ingress.yaml"
kubectl apply -f "$MANIFESTS_DIR/signoz-ingress.yaml"
echo "✅ Ingress resources applied"
echo ""

# ---- 7. Deploy Jerney via ArgoCD ----
echo "🛤️  Deploying Jerney application via ArgoCD..."
kubectl apply -f "$MANIFESTS_DIR/argocd-app-jerney.yaml"
echo "✅ ArgoCD Application created"
echo ""

# ---- Summary ----
echo ""
echo "==========================================="
echo "🎉 Setup Complete!"
echo "==========================================="
echo ""
echo "📋 ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "🌐 Your Services:"
echo "  Frontend → https://jerney.nilkanthprojects.site"
echo "  ArgoCD   → https://argocd.nilkanthprojects.site"
echo "  SigNoz   → https://signoz.nilkanthprojects.site"
echo ""
echo "📋 Check status:"
echo "  kubectl get ingress -A"
echo "  kubectl get certificates -A"
echo "  kubectl get pods -A"
echo ""
