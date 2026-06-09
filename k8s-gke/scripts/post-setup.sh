#!/bin/bash
# ==============================================================
# Jerney - GKE Post-Cluster Setup
#
# Run this AFTER `terraform apply` provisions the GKE cluster.
# Run it from your LOCAL machine (not SSH — there's no VM to SSH into).
#
# Prerequisites on your machine:
#   - gcloud CLI authenticated  (gcloud auth login)
#   - kubectl installed         (gcloud components install kubectl)
#   - helm >= 3.12 installed    (brew install helm)
#
# GKE vs EC2 differences handled here:
#   - No kubeadm / Flannel / local-path-provisioner steps
#   - No Metrics Server install (GKE ships it)
#   - NGINX Ingress uses NodePort (matches GCP firewall rules from Terraform)
#   - ArgoCD Application points to k8s-gke/ values overlay
# ==============================================================

set -e

REPO_DIR="$(git rev-parse --show-toplevel)"
MANIFESTS_DIR="$REPO_DIR/k8s-gke/manifests"

# ---- Read GKE connection details ----
echo "=== Jerney GKE Post-Setup Script ==="
echo "====================================="
echo ""
echo "Provide your GKE cluster details (from terraform output):"
read -rp "GCP Project ID: " GCP_PROJECT
read -rp "GKE Zone (e.g. us-central1-a): " GKE_ZONE
read -rp "Cluster Name (default: jerney-gke): " CLUSTER_NAME
CLUSTER_NAME="${CLUSTER_NAME:-jerney-gke}"

# ---- Configure kubectl ----
echo ""
echo "🔑 Configuring kubectl for GKE cluster..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --zone "$GKE_ZONE" \
  --project "$GCP_PROJECT"

echo "📋 Checking cluster status..."
kubectl get nodes
echo ""

echo "⏳ Waiting for system pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s || true
echo ""

# ---- 1. Install NGINX Ingress Controller ----
# GKE has a built-in HTTP(S) Load Balancer ingress, but we use NGINX for
# consistency with the EC2 setup and to avoid Cloud LB costs.
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
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/component=controller \
  -n ingress-nginx --timeout=300s
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
  --set 'configs.params.server\.insecure=true'

echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available deployment --all -n argocd --timeout=300s
kubectl rollout status statefulset/argo-cd-argocd-application-controller \
  -n argocd --timeout=300s
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
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/component=frontend \
  -n platform --timeout=300s || true
echo "✅ SigNoz installed"
echo ""

# ---- 6. Install Prometheus + Grafana ----
echo "📊 Installing Prometheus + Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

cat <<'EOF' > /tmp/prom-values.yaml
grafana:
  adminPassword: admin123
  service:
    type: ClusterIP
  ingress:
    enabled: false
prometheus:
  prometheusSpec:
    podMonitorSelectorNilMatchesAll: true
    serviceMonitorSelectorNilMatchesAll: true
    additionalScrapeConfigs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: "true"
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: kubernetes_namespace
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: kubernetes_pod_name
EOF

helm install kube-prom prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values /tmp/prom-values.yaml

echo "⏳ Waiting for Prometheus + Grafana to be ready..."
kubectl wait --for=condition=available deployment --all -n monitoring --timeout=300s
echo "✅ Prometheus + Grafana installed"
echo ""

# ---- 7. Install Loki + Promtail ----
echo "🪵 Installing Loki + Promtail..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set loki.enabled=true \
  --set promtail.enabled=true \
  --set grafana.enabled=false \
  --set loki.image.tag=2.9.10 # pinned: Grafana 10/11 health check requires Loki >= 2.9

echo "⏳ Waiting for Loki to be ready..."
kubectl wait --for=condition=Ready pods -l app=loki -n monitoring --timeout=120s \
  || kubectl wait --for=condition=Ready pods \
       -l app.kubernetes.io/name=loki -n monitoring --timeout=60s \
  || true
echo "✅ Loki + Promtail installed"
echo ""

# ---- 8. Apply Ingress Resources ----
echo "🌐 Applying Ingress resources..."
kubectl apply -f "$MANIFESTS_DIR/argocd-ingress.yaml"
kubectl apply -f "$MANIFESTS_DIR/signoz-ingress.yaml"
kubectl apply -f "$MANIFESTS_DIR/grafana-ingress.yaml"
echo "✅ Ingress resources applied"
echo ""

# ---- 9. Deploy Jerney via ArgoCD ----
# Uses multi-source app: base values + k8s-gke/helm/jerney/values-gke.yaml overlay
echo "🛤️  Deploying Jerney via ArgoCD..."
kubectl apply -f "$MANIFESTS_DIR/argocd-app-jerney.yaml"
echo "✅ ArgoCD Application created"
echo ""

# ---- Get node external IP for DNS ----
echo "📋 Node External IP (point your DNS A records here):"
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'
echo ""
echo "   Update nilkanthprojects.site DNS:"
echo "   A  jerney.nilkanthprojects.site   → <node-external-ip>"
echo "   A  argocd.nilkanthprojects.site   → <node-external-ip>"
echo "   A  grafana.nilkanthprojects.site  → <node-external-ip>"
echo "   A  signoz.nilkanthprojects.site   → <node-external-ip>"
echo ""

# ---- Summary ----
echo "==========================================="
echo "🎉 GKE Setup Complete!"
echo "==========================================="
echo ""
echo "📋 ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "📋 Grafana Admin Password: admin123"
echo "   (change after first login)"
echo ""
echo "🌐 Your Services (once DNS propagates):"
echo "  Frontend → https://jerney.nilkanthprojects.site"
echo "  ArgoCD   → https://argocd.nilkanthprojects.site"
echo "  SigNoz   → https://signoz.nilkanthprojects.site"
echo "  Grafana  → https://grafana.nilkanthprojects.site"
echo ""
echo "📋 After logging into Grafana, add Loki as a data source:"
echo "   Connections → Data Sources → Add → Loki"
echo "   URL: http://loki.monitoring.svc.cluster.local:3100"
echo ""
echo "📋 Check status:"
echo "  kubectl get ingress -A"
echo "  kubectl get certificates -A"
echo "  kubectl get pods -A"
echo ""
