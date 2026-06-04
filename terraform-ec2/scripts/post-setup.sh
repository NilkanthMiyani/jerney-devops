#!/bin/bash
# ==============================================================
# Jerney - Post Kubeadm Setup
# Run this AFTER SSH-ing into the EC2 instance
# Installs: NGINX Ingress, cert-manager, ArgoCD, SigNoz
# ==============================================================

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
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: miyaninilkanth2@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
echo "✅ ClusterIssuer created"
echo ""

# ---- 4. Install ArgoCD ----
echo "🔄 Installing ArgoCD..."
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=600s
echo "✅ ArgoCD installed"
echo ""

# ---- 5. Patch ArgoCD to run insecure (TLS terminated at Ingress) ----
echo "🔧 Configuring ArgoCD for Ingress..."
kubectl -n argocd patch deployment argocd-server --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'

echo ""

# ---- 6. Install SigNoz ----
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

# ---- 7. Apply Ingress Resources ----
echo "🌐 Applying Ingress resources..."

# ArgoCD Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - argocd.nilkanthprojects.site
      secretName: argocd-tls
  rules:
    - host: argocd.nilkanthprojects.site
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

# SigNoz Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: signoz-ingress
  namespace: platform
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - signoz.nilkanthprojects.site
      secretName: signoz-tls
  rules:
    - host: signoz.nilkanthprojects.site
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: signoz-frontend
                port:
                  number: 3301
EOF

echo "✅ Ingress resources applied"
echo ""

# ---- 8. Deploy Jerney via ArgoCD ----
echo "🛤️  Deploying Jerney application via ArgoCD..."
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: jerney
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/NilkanthMiyani/jerney-devops.git
    targetRevision: main
    path: k8s/helm/jerney
  destination:
    server: https://kubernetes.default.svc
    namespace: jerney
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
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
