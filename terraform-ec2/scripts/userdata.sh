#!/bin/bash
# ==============================================================
# Jerney - Kubeadm Single-Node Cluster Bootstrap Script
# This runs as user-data on EC2 instance launch
# ==============================================================

set -e

exec > >(tee /var/log/kubeadm-setup.log) 2>&1
echo "=== Kubeadm Setup Started at $(date) ==="

# ---- System Prerequisites ----
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Disable swap (required by kubeadm)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Sysctl params for Kubernetes networking
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# ---- Install containerd ----
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y containerd.io

# Configure containerd to use systemd cgroup driver
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# ---- Install kubeadm, kubelet, kubectl ----
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# ---- Install Helm ----
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ---- Initialize kubeadm (single-node) ----
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address="${PRIVATE_IP}" \
  --apiserver-cert-extra-sans="${PRIVATE_IP}"

# Setup kubeconfig for ubuntu user
mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Also setup for root
export KUBECONFIG=/etc/kubernetes/admin.conf

# ---- Install Flannel CNI ----
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# ---- Remove control-plane taint (single-node: allow workloads on master) ----
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# ---- Install local-path-provisioner (for PersistentVolumes) ----
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Set local-path as default StorageClass
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo ""
echo "=== Kubeadm Setup Completed at $(date) ==="
echo "=== SSH in and run the post-setup script to install Ingress, ArgoCD, SigNoz ==="
