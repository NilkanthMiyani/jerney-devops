# terraform-ec2

Provisions a single-node Kubernetes cluster on AWS EC2 using kubeadm, then installs the full Jerney platform stack via Helm.

## Architecture

```
EC2 (t3.medium, ap-south-1)
└── kubeadm single-node cluster
    ├── containerd (runtime)
    ├── Flannel (CNI)
    ├── local-path-provisioner (PersistentVolumes)
    ├── NGINX Ingress Controller
    ├── cert-manager + Let's Encrypt
    ├── ArgoCD
    └── SigNoz
```

## Prerequisites

- Terraform installed
- AWS CLI configured (`aws configure`)
- An existing EC2 key pair in `ap-south-1`
- DNS A records pointing to the EC2 public IP (see [DNS Setup](#dns-setup))

## Usage

### 1. Provision the EC2 instance

```bash
cd terraform-ec2
terraform init
terraform apply
```

Terraform will output the public IP and the SSH command. User data runs automatically on launch — it installs containerd, kubeadm, kubectl, Helm, initialises the cluster, and sets up Flannel CNI. This takes ~5 minutes.

Check bootstrap progress:
```bash
ssh -i nilkanth-personal.pem ubuntu@<public-ip>
tail -f /var/log/kubeadm-setup.log
```

### 2. DNS Setup

Before running the post-setup script, create DNS A records pointing to the EC2 public IP (shown in `terraform output`):

| Subdomain | Record |
|---|---|
| `jerney.nilkanthprojects.site` | EC2 public IP |
| `argocd.nilkanthprojects.site` | EC2 public IP |
| `signoz.nilkanthprojects.site` | EC2 public IP |

### 3. Run the post-setup script

SSH into the instance and run:

```bash
git clone https://github.com/NilkanthMiyani/jerney-devops.git
cd jerney-devops/terraform-ec2/scripts
bash post-setup.sh
```

This installs (in order):

| Step | Component | Method |
|---|---|---|
| 1 | NGINX Ingress Controller | Helm (`ingress-nginx/ingress-nginx`) |
| 2 | cert-manager | Helm (`jetstack/cert-manager`) |
| 3 | Let's Encrypt ClusterIssuer | `manifests/clusterissuer.yaml` |
| 4 | ArgoCD | Helm (`argo/argo-cd`) |
| 5 | SigNoz | Helm (`signoz/signoz`) |
| 6 | Ingress resources | `manifests/argocd-ingress.yaml`, `manifests/signoz-ingress.yaml` |
| 7 | Jerney ArgoCD Application | `manifests/argocd-app-jerney.yaml` |

At the end of the script, the ArgoCD initial admin password is printed.

## Configuration

Edit `terraform.tfvars` to change instance type, region, or key pair:

```hcl
aws_region    = "ap-south-1"
instance_type = "t3.medium"
key_name      = "nilkanth-personal"
volume_size   = 30
```

> **Security note:** `allowed_ssh_cidr` defaults to `0.0.0.0/0`. Restrict it to your IP in production: `allowed_ssh_cidr = "YOUR_IP/32"`

## Manifests

Kubernetes manifests applied during post-setup are in [`manifests/`](./manifests/):

| File | Description |
|---|---|
| `clusterissuer.yaml` | Let's Encrypt ACME ClusterIssuer |
| `argocd-ingress.yaml` | Ingress for ArgoCD UI with TLS |
| `signoz-ingress.yaml` | Ingress for SigNoz UI with TLS |
| `argocd-app-jerney.yaml` | ArgoCD Application pointing to `k8s/helm/jerney` |

## ArgoCD

After setup, ArgoCD manages the Jerney application with auto-sync enabled (prune + self-heal). Any push to `main` triggers a new image build via CI, which updates the Helm image tag, and ArgoCD deploys the new version automatically.

**Access:** `https://argocd.nilkanthprojects.site`
**Username:** `admin`
**Password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## Teardown

```bash
terraform destroy
```

This terminates the EC2 instance and deletes the security group. The EBS volume is automatically deleted (`delete_on_termination = true`).
